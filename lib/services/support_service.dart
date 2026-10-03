import 'dart:math';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class SupportService {
  static String newId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final s = b.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  static const extensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'pdf',
    'zip',
    'txt',
    'csv',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'xlsm',
    'ppt',
    'pptx'
  ];
  static Future<Map<String, dynamic>> list(
          {bool manager = false,
          String search = '',
          String kind = '',
          int offset = 0}) async =>
      Map<String, dynamic>.from(await SupabaseService.client
          .rpc('list_support_requests', params: {
        'p_manager': manager,
        'p_search': search,
        'p_kind': kind,
        'p_offset': offset
      }) as Map);
  static Future<Map<String, dynamic>> open(int id) async =>
      Map<String, dynamic>.from(await SupabaseService.client
          .rpc('open_support_request', params: {'p_quote_id': id}) as Map);
  static Future<int> start(String content, String clientId,
          {int? quoteId, String route = ''}) async =>
      (await SupabaseService.client.rpc('start_staff_consultation', params: {
        'p_content': content,
        'p_route': route,
        'p_quote_id': quoteId,
        'p_client_id': clientId
      }) as num)
          .toInt();
  static Future<void> send(int id, String message, String contact,
      List<Map<String, dynamic>> files, String clientId) async {
    await SupabaseService.client.rpc('send_support_reply', params: {
      'p_quote_id': id,
      'p_message': message,
      'p_contact': contact,
      'p_attachments': files,
      'p_client_id': clientId
    });
  }

  static Future<List<SupportFile>> pick() async {
    final selected = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: extensions);
    final result = <SupportFile>[];
    for (final f in selected) {
      final size = await f.length();
      if (size > 10485760) throw Exception('10MB / file');
      result.add(SupportFile(f.name, () => f.readAsBytes(), size));
    }
    if (result.length > 5) throw Exception('Maximum 5 files');
    return result;
  }

  static Future<Map<String, dynamic>> upload(int id, SupportFile file) async {
    if (file.uploaded != null) return file.uploaded!;
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) throw Exception('Sign in required');
    final ext = file.name.split('.').last.toLowerCase();
    if (!extensions.contains(ext)) throw Exception('Unsupported file');
    final bytes = await file.readBytes();
    if (bytes.length > 10485760) throw Exception('10MB / file');
    final path = '$id/${user.id}/${newId()}.$ext';
    await SupabaseService.client.storage.from('quote-attachments').uploadBinary(
        path, bytes,
        fileOptions:
            const FileOptions(contentType: 'application/octet-stream'));
    return file.uploaded = {
      'path': path,
      'name': file.name.length > 180 ? file.name.substring(0, 180) : file.name
    };
  }

  static Future<String> fileUrl(String path) => SupabaseService.client.storage
      .from('quote-attachments')
      .createSignedUrl(path, 600);
}

class SupportFile {
  SupportFile(this.name, this.readBytes, this.size);
  final String name;
  final Future<Uint8List> Function() readBytes;
  final int size;
  Map<String, dynamic>? uploaded;
}
