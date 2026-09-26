import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'domestic_tracking_service.dart';

class IntakeFile {
  const IntakeFile(this.name, this.size, this.readBytes);
  final String name;
  final int size;
  final Future<Uint8List> Function() readBytes;
  String get mime => name.toLowerCase().endsWith('.png') ? 'image/png' : name.toLowerCase().endsWith('.webp') ? 'image/webp' : 'image/jpeg';
}

class WaybillIntakeService {
  static Future<List<IntakeFile>> pick() async {
    final selected = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'webp']);
    final files = <IntakeFile>[];
    for (final f in selected) { files.add(IntakeFile(f.name, await f.length(), f.readAsBytes)); }
    if (files.isNotEmpty) validate(files);
    return files;
  }
  static void validate(List<IntakeFile> files) {
    if (files.isEmpty || files.length > 50) throw const DomesticTrackingException('INVALID_BATCH');
    if (files.any((f) => f.size > 5242880) || files.fold<int>(0, (s,f) => s+f.size) > 262144000) throw const DomesticTrackingException('FILE_TOO_LARGE');
  }
  static Future<Map<String,dynamic>> call(String action, [Map<String,dynamic> body = const {}]) async {
    if (DomesticTrackingService.currentUserId == null) throw const DomesticTrackingException('LOGIN_REQUIRED');
    try {
      final response = await SupabaseService.client.functions.invoke('waybill-intake', body: {'action': action, ...body});
      final data = Map<String,dynamic>.from(response.data as Map);
      if (data['error'] != null) throw DomesticTrackingException('${data['error']}');
      return data;
    } on FunctionException catch(e) {
      throw DomesticTrackingException(e.details is Map ? '${e.details['error'] ?? 'REQUEST_FAILED'}' : 'REQUEST_FAILED');
    }
  }
  static Future<Map<String,dynamic>> begin(List<IntakeFile> files, String purpose, {int? shipmentId, Map<String,dynamic>? fixedLink}) {
    validate(files);
    return call('begin', {'purpose': purpose, 'shipment_id': shipmentId, 'fixed_link': fixedLink, 'files': files.map((f) => {'name': f.name, 'size': f.size}).toList()});
  }
  static Future<void> upload(IntakeFile file, Map<String,dynamic> target) async {
    final bytes = await file.readBytes();
    if (bytes.length != file.size || bytes.length > 5242880) throw const DomesticTrackingException('FILE_TOO_LARGE');
    await SupabaseService.client.storage.from('domestic-waybills').uploadBinaryToSignedUrl(
      '${target['path']}', '${target['token']}', bytes, FileOptions(contentType: file.mime));
  }
  static Future<String?> stage(List<IntakeFile> files) async {
    if (files.isEmpty) return null;
    final batch = await begin(files, 'photos');
    for (var i=0;i<files.length;i++) {
      final target = Map<String,dynamic>.from(batch['files'][i]);
      await upload(files[i], target);
      await call('verify', {'batch_id': batch['batch_id'], 'file_id': target['id']});
    }
    return '${batch['batch_id']}';
  }
}
