import '../core/cargo_note_colors.dart';
import '../core/route_catalog.dart';
import 'supabase_service.dart';

/// Lightweight palette-only reads, shared by all visible rows in the same voyage.
class CargoNotePaletteService {
  CargoNotePaletteService._();
  static final instance = CargoNotePaletteService._();
  final _cache = <String, ({DateTime time, Future<Map> value})>{};
  String? _owner;
  Future<Map> _read(String route, int year, String voyage) {
    final key = '$route|$year|$voyage';
    final old = _cache[key];
    if (old != null && DateTime.now().difference(old.time).inSeconds < 60) return old.value;
    final value = (() async {
      try {
        final rows = await SupabaseService.client.from('excel_workbook_policies')
            .select('appearance:changes->appearance').eq('route_key', route)
            .eq('shipment_year', year).eq('voyage', voyage).limit(1);
        return rows.isNotEmpty && rows.first['appearance'] is Map ? rows.first['appearance'] as Map : const {};
      } catch (_) { _cache.remove(key); return const {}; }
    })();
    _cache[key] = (time: DateTime.now(), value: value);
    if (_cache.length > 128) _cache.remove(_cache.keys.first);
    return value;
  }
  Future<Map<String, String>> colors(Map<String, dynamic> row) async {
    if (CargoNoteColors.kind(row).isEmpty) return CargoNoteColors.defaults;
    try {
      final owner = SupabaseService.client.auth.currentUser?.id;
      if (_owner != owner) { _cache.clear(); _owner = owner; }
      if (owner == null) return CargoNoteColors.defaults;
      final route = RouteCatalog.keyFor('${row['route'] ?? row['route_key'] ?? ''}');
      if (route.isEmpty) return CargoNoteColors.defaults;
      final year = int.tryParse('${row['shipment_year'] ?? row['year'] ?? 0}') ?? 0;
      final raw = '${row['voyage'] ?? ''}'.replaceAll(RegExp(r'항차|\s'), '');
      final number = RegExp(r'^\d{1,3}$').hasMatch(raw) ? int.tryParse(raw) ?? 0 : 0;
      final values = await Future.wait([_read(route, 0, '00'), if (year > 0 && number > 0) _read(route, year, '$number'.padLeft(2, '0'))]);
      if (_owner != owner) return CargoNoteColors.defaults;
      return CargoNoteColors.palette(values.first, values.length > 1 ? values[1] : const {});
    } catch (_) { return CargoNoteColors.defaults; }
  }
}
