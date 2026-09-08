import '../config/supabase_config.dart';
import '../core/cargo_tracking.dart';
import 'supabase_service.dart';

class ScheduleService {
  ScheduleService._();
  static final instance = ScheduleService._();

  Future<List<Map<String, dynamic>>> list() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final rows = await SupabaseService.client.from('shipping_schedules').select().order('estimated_arrival_date');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>?> findForCargo(
    Map<String, dynamic> cargo, {
    List<Map<String, dynamic>>? schedules,
  }) async {
    final rows = schedules ?? await list();
    return CargoTracking.findSchedule(cargo, rows);
  }

  Future<void> save(Map<String, dynamic> data, {int? id}) async {
    if (!SupabaseConfig.isConfigured) return;
    if (id == null) {
      await SupabaseService.client.from('shipping_schedules').insert(data);
    } else {
      await SupabaseService.client.from('shipping_schedules').update(data).eq('id', id);
    }
  }

  Future<void> delete(int id) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.from('shipping_schedules').delete().eq('id', id);
  }
}
