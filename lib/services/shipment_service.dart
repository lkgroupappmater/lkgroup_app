import '../config/supabase_config.dart';
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
        .from('shipments').select().order('created_at', ascending: false).limit(100);
    return rows.map((row) => Shipment.fromJson(_normaliseRow(row))).toList();
  }

  Future<Shipment?> findByTrackingNumber(String trackingNumber) async {
    if (!SupabaseConfig.isConfigured) return MockShipments.findByTracking(trackingNumber);
    final rows = await SupabaseService.client.from('shipments').select()
        .or('invoice_number.ilike.%${_escape(trackingNumber)}%,box_number.ilike.%${_escape(trackingNumber)}%')
        .limit(20);
    if (rows.isEmpty) return null;
    return Shipment.fromJson(_normaliseRow(rows.first));
  }

  Future<List<Map<String, dynamic>>> searchRows({
    String route = '전체',
    String boxNumber = '',
    String invoice = '',
    String recipient = '',
    String phone = '',
  }) async {
    if (!SupabaseConfig.isConfigured) return const [];
    var query = SupabaseService.client.from('shipments').select();
    if (route != '전체' && route.isNotEmpty) query = query.eq('route', route);
    if (boxNumber.isNotEmpty) {
      query = query.ilike('box_number', '%${_escape(boxNumber)}%');
    }
    if (invoice.isNotEmpty) {
      query = query.ilike('invoice_number', '%${_escape(invoice)}%');
    }
    if (recipient.isNotEmpty) {
      query = query.ilike('consignee_name', '%${_escape(recipient)}%');
    }
    if (phone.isNotEmpty) {
      query = query.ilike('consignee_phone', '%${_escape(phone)}%');
    }
    final rows = await query.order('received_at', ascending: false).limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Shipment>> getShipmentsForCustomer(String customerId) async {
    if (!SupabaseConfig.isConfigured) return MockShipments.forCustomer(customerId);
    final rows = await SupabaseService.client.from('shipments').select().eq('customer_id', customerId);
    return rows.map((row) => Shipment.fromJson(_normaliseRow(row))).toList();
  }

  Future<int> bulkCreateFromRows(List<Map<String, dynamic>> rows) async {
    if (!SupabaseConfig.isConfigured || rows.isEmpty) return 0;
    final payload = rows.map(_shipmentPayload).toList();
    await SupabaseService.client.from('shipments').insert(payload);
    return payload.length;
  }

  Future<void> updateStatus(String id, ShipmentStatus status) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.from('shipments').update({'status': status.name}).eq('id', id);
  }

  static Map<String, dynamic> _normaliseRow(Map<String, dynamic> row) => {
    ...row,
    'id': row['id']?.toString() ?? '',
    'tracking_number': row['tracking_number'] ?? row['invoice_number'] ?? '',
    'customer_name': row['customer_name'] ?? row['consignee_name'] ?? '',
    'customer_id': row['customer_id']?.toString() ?? '',
    'origin': row['origin'] ?? '', 'destination': row['destination'] ?? '',
    'route': _routeEnum(row['route']?.toString()),
    'created_at': row['created_at'] ?? DateTime.now().toIso8601String(),
  };

  static String _routeEnum(String? route) {
    if (route == null) return 'krLaosSeaExport';
    if (route.contains('항공')) return route.contains('라오스->한국') ? 'laosKrAirImport' : 'krLaosAirExport';
    if (route.contains('육로')) return 'laosThailandLand';
    return route;
  }

  static Map<String, dynamic> _shipmentPayload(Map<String, dynamic> row) => {
    'box_number': row['box_number'] ?? row['boxNo'] ?? '',
    'invoice_number': row['invoice_number'] ?? row['invoice'] ?? row['shipment_no'] ?? '',
    'route': row['route'] ?? '',
    'consignee_name': row['consignee_name'] ?? row['name'] ?? '',
    'consignee_phone': row['consignee_phone'] ?? row['phone'] ?? '',
    'origin': row['origin'] ?? '', 'destination': row['destination'] ?? '',
    'status': row['status'] ?? 'registered',
    'received_at': row['received_at'] ?? row['arrival'],
    'weight_kg': _num(row['weight_kg'] ?? row['weight']),
    'width_cm': _num(row['width_cm'] ?? row['width']),
    'length_cm': _num(row['length_cm'] ?? row['length']),
    'height_cm': _num(row['height_cm'] ?? row['height']),
    'quantity': int.tryParse('${row['quantity'] ?? row['qty'] ?? ''}'),
    'receipt_number': row['receipt_number'] ?? row['receiptNo'] ?? row['receipt'] ?? '',
    'cargo_type': row['cargo_type'] ?? '', 'notes': row['notes'] ?? '',
  };

  static num? _num(dynamic value) => num.tryParse('${value ?? ''}'.trim());
  static String _escape(String value) => value.replaceAll(',', '');
}


