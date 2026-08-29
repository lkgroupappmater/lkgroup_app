import '../config/supabase_config.dart';
import '../models/app_user.dart';
import '../models/shipment.dart';
import '../data/mock_data.dart';
import 'supabase_service.dart';

class ShipmentService {
  ShipmentService._();
  static final ShipmentService instance = ShipmentService._();
  factory ShipmentService() => instance;

  Future<List<Shipment>> getAllShipments() async {
    if (!SupabaseConfig.isConfigured) return MockShipments.all;
    final rows = await SupabaseService.client
        .from('shipments')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map((row) => Shipment.fromJson(_normaliseRow(row))).toList();
  }

  Future<List<Map<String, dynamic>>> searchRows({
    String route = '전체',
    String boxNumber = '',
    String invoice = '',
    String recipient = '',
    String phone = '',
    String year = '',
    String voyage = '',
    AppUser? currentUser,
  }) async {
    if (!SupabaseConfig.isConfigured || currentUser == null) return const [];

    var query = SupabaseService.client.from('shipments').select();

    if (route != '전체' && route.isNotEmpty) query = query.eq('route', route);
    if (year.isNotEmpty) {
      final parsedYear = int.tryParse(
        year.replaceAll(RegExp(r'[^0-9]'), ''),
      );
      if (parsedYear != null) {
        query = query.eq('shipment_year', parsedYear);
      }
    }
    if (voyage.isNotEmpty) query = query.eq('voyage', voyage.replaceAll('항차', '').trim());

    if (currentUser.role.canSeeAllShipments) {
      if (boxNumber.isNotEmpty) {
        query = query.ilike('box_number', '%${_escape(boxNumber)}%');
      }
      if (recipient.isNotEmpty) {
        query = query.ilike('consignee_name', '%${_escape(recipient)}%');
      }
      if (phone.isNotEmpty) {
        query = query.ilike('consignee_phone', '%${_escape(phone)}%');
      }
    }

    if (invoice.isNotEmpty) {
      query = query.ilike('invoice_number', '%${_escape(invoice)}%');
    }

    final rows = await query.order('received_at', ascending: false).limit(300);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> getRowsByIds(List<String> ids) async {
    if (!SupabaseConfig.isConfigured || ids.isEmpty) return const [];
    final rows = await SupabaseService.client
        .from('shipments')
        .select()
        .inFilter('id', ids.map(int.tryParse).whereType<int>().toList());
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<int> upsertFromRows(List<Map<String, dynamic>> rows) async {
    if (!SupabaseConfig.isConfigured || rows.isEmpty) return 0;
    final payload = rows.map(_shipmentPayload).toList();
    await SupabaseService.client
        .from('shipments')
        .upsert(payload, onConflict: 'import_key');
    return payload.length;
  }

  Future<void> updateRow(String id, Map<String, dynamic> changes) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.from('shipments').update(changes).eq('id', id);
  }

  Future<Shipment?> findByTrackingNumber(String trackingNumber) async {
    if (!SupabaseConfig.isConfigured) return MockShipments.findByTracking(trackingNumber);
    final rows = await SupabaseService.client
        .from('shipments')
        .select()
        .or('invoice_number.ilike.%${_escape(trackingNumber)}%,box_number.ilike.%${_escape(trackingNumber)}%')
        .limit(20);
    if (rows.isEmpty) return null;
    return Shipment.fromJson(_normaliseRow(rows.first));
  }

  Future<List<Shipment>> getShipmentsForCustomer(String customerId) async {
    if (!SupabaseConfig.isConfigured) return MockShipments.forCustomer(customerId);
    final rows = await SupabaseService.client
        .from('shipments')
        .select()
        .eq('customer_id', customerId);
    return rows.map((row) => Shipment.fromJson(_normaliseRow(row))).toList();
  }

  Future<void> updateStatus(String id, ShipmentStatus status) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client
        .from('shipments')
        .update({'status': status.name}).eq('id', id);
  }

  static Map<String, dynamic> _shipmentPayload(Map<String, dynamic> row) {
    final route = '${row['route'] ?? ''}';
    final year = int.tryParse('${row['shipment_year'] ?? row['year'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), ''));
    final voyage = '${row['voyage'] ?? ''}'.replaceAll('항차', '').trim().padLeft(2, '0');
    final box = '${row['box_number'] ?? row['boxNo'] ?? ''}'.trim();

    return {
      'box_number': box,
      'invoice_number': '${row['invoice_number'] ?? row['invoice'] ?? row['shipment_no'] ?? ''}'.trim(),
      'route': route,
      'shipment_year': year,
      'voyage': voyage,
      'import_key': '${row['import_key'] ?? '$route|${year ?? ''}|$voyage|$box'}',
      'sender_name': '${row['sender_name'] ?? row['sender'] ?? ''}',
      'consignee_name': '${row['consignee_name'] ?? row['name'] ?? ''}',
      'consignee_phone': '${row['consignee_phone'] ?? row['phone'] ?? ''}',
      'contents': '${row['contents'] ?? row['cargo_type'] ?? ''}',
      'package_type': '${row['package_type'] ?? ''}',
      'quantity': int.tryParse('${row['quantity'] ?? row['qty'] ?? ''}') ?? 1,
      'weight_kg': _num(row['weight_kg'] ?? row['weight']),
      'length_cm': _num(row['length_cm'] ?? row['length']),
      'width_cm': _num(row['width_cm'] ?? row['width']),
      'height_cm': _num(row['height_cm'] ?? row['height']),
      'receipt_number': '${row['receipt_number'] ?? row['receiptNo'] ?? row['receipt'] ?? ''}',
      'unloading_zone': '${row['unloading_zone'] ?? row['zone'] ?? ''}',
      'notes': '${row['notes'] ?? row['remark'] ?? ''}',
      'received_at': row['received_at'],
      'status': row['status'] ?? 'registered',
    };
  }

  static Map<String, dynamic> _normaliseRow(Map<String, dynamic> row) => {
        ...row,
        'id': row['id']?.toString() ?? '',
        'tracking_number': row['tracking_number'] ?? row['invoice_number'] ?? '',
        'customer_name': row['customer_name'] ?? row['consignee_name'] ?? '',
        'customer_id': row['customer_id']?.toString() ?? '',
        'origin': row['origin'] ?? '',
        'destination': row['destination'] ?? '',
        'route': _routeEnum(row['route']?.toString()),
        'created_at': row['created_at'] ?? DateTime.now().toIso8601String(),
      };

  static String _routeEnum(String? route) {
    if (route == null) return 'krLaosSeaExport';
    if (route.contains('항공')) {
      return route.contains('라오스->한국') ? 'laosKrAirImport' : 'krLaosAirExport';
    }
    if (route.contains('육로')) return 'laosThailandLand';
    return route;
  }

  static num? _num(dynamic value) => num.tryParse('${value ?? ''}'.trim());
  static String _escape(String value) => value.replaceAll(',', '');
}
