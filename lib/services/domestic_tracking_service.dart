import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class DomesticTrackingException implements Exception {
  const DomesticTrackingException(this.code);
  final String code;
}

class DomesticTrackingService {
  static const carriers = <String, String>{
    'HAL': 'HAL · Houng Aloun',
    'ANS': 'ANS · Anousith',
    'MIXAY': 'Mixay',
    'JT': 'J&T Express',
    'LAOPOST': 'Lao Post',
  };
  static const statuses = [
    'registered',
    'accepted',
    'in_transit',
    'ready_for_pickup',
    'out_for_delivery',
    'delivered',
    'returned',
    'exception',
    'unknown',
  ];
  static Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> body = const {},
  ]) async {
    if (!SupabaseService.isReady ||
        SupabaseService.client.auth.currentUser == null) {
      throw const DomesticTrackingException('LOGIN_REQUIRED');
    }
    try {
      final response = await SupabaseService.client.functions.invoke(
        'domestic-tracking',
        body: {'action': action, ...body},
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['error'] != null)
        throw DomesticTrackingException('${data['error']}');
      return data;
    } on FunctionException catch (e) {
      final details = e.details;
      throw DomesticTrackingException(
        details is Map
            ? '${details['error'] ?? 'REQUEST_FAILED'}'
            : 'REQUEST_FAILED',
      );
    }
  }

  static String laoDate(dynamic value) {
    final date = DateTime.tryParse('$value')
        ?.toUtc()
        .add(const Duration(hours: 7));
    if (date == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }
}
