import '../config/supabase_config.dart';
import '../models/app_user.dart';
import '../models/shipment.dart';
import '../data/mock_data.dart';
import 'supabase_service.dart';

class ShipmentImportSummary {
  const ShipmentImportSummary({
    this.newRows = 0,
    this.unchanged = 0,
    this.changeRequests = 0,
    this.alreadyPending = 0,
    this.protectedRows = 0,
  });

  final int newRows;
  final int unchanged;
  final int changeRequests;
  final int alreadyPending;
  final int protectedRows;

  int get existingRows =>
      unchanged + changeRequests + alreadyPending + protectedRows;
  int get actions => newRows + changeRequests;

  ShipmentImportSummary operator +(ShipmentImportSummary other) =>
      ShipmentImportSummary(
        newRows: newRows + other.newRows,
        unchanged: unchanged + other.unchanged,
        changeRequests: changeRequests + other.changeRequests,
        alreadyPending: alreadyPending + other.alreadyPending,
        protectedRows: protectedRows + other.protectedRows,
      );

  factory ShipmentImportSummary.fromRpc(dynamic value) {
    final map = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    int count(String key) => (map[key] as num?)?.toInt() ?? 0;
    return ShipmentImportSummary(
      newRows: count('new_rows'),
      unchanged: count('unchanged'),
      changeRequests: count('change_requests'),
      alreadyPending: count('already_pending'),
      protectedRows: count('protected_rows'),
    );
  }
}

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

  /// Search is intentionally routed through a SECURITY DEFINER RPC.
  /// It applies different partial-match rules for member vs manager roles
  /// without opening the full shipments table through RLS.
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

    final parsedYear = int.tryParse(year.replaceAll(RegExp(r'[^0-9]'), ''));
    final voyageValue = voyage == '전체'
        ? ''
        : voyage.replaceAll('항차', '').trim();

    final rows = await SupabaseService.client.rpc(
      'search_shipments_for_current_user',
      params: {
        'p_route': route == '전체' ? '' : route,
        'p_year': year == '전체' ? null : parsedYear,
        'p_voyage': voyageValue,
        'p_box_number': boxNumber.trim(),
        'p_invoice': invoice.trim(),
        'p_recipient': recipient.trim(),
        'p_phone': phone.trim(),
      },
    );

    final result = List<Map<String, dynamic>>.from(rows as List);

    // A member may need to recover cargo whose recipient name/phone was entered
    // incorrectly at the logistics center.  The dedicated RPC accepts an exact
    // invoice suffix of at least four characters and only returns masked
    // recipient data.  It is deliberately separate from the normal RLS-scoped
    // result so an invoice suffix never opens another customer's full record.
    if (currentUser.role == UserRole.member && invoice.trim().isNotEmpty) {
      final suffix = invoice
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (suffix.length < 4) {
        throw StateError('송장번호 뒤 4자리 이상을 입력해 주세요.');
      }
      final maskedRaw = await SupabaseService.client.rpc(
        'search_shipments_by_invoice_suffix',
        params: {'p_invoice_suffix': suffix},
      );
      final existingIds = result.map((row) => '${row['id']}').toSet();
      for (final raw in List<Map<String, dynamic>>.from(maskedRaw as List)) {
        if (existingIds.add('${raw['id']}')) result.add(raw);
      }
    }

    // 관리자·직원·협력/파트너 검색에서는 수취인 불명 화물도 일반 화물 검색 결과
    // 아래에 보여야 합니다. 과거 RPC 버전에 recipient_unknown 제외 조건이 남아 있어도
    // 앱에서 해당 항차의 불명 화물을 보강해 누락되지 않게 합니다.
    final isManager = currentUser.role == UserRole.admin ||
        currentUser.role == UserRole.staff ||
        currentUser.role == UserRole.partner;

    if (isManager) {
      try {
        var query = SupabaseService.client
            .from('shipments')
            .select()
            .eq('recipient_unknown', true);

        if (route != '전체') {
          query = query.eq('route', route);
        }
        if (parsedYear != null && year != '전체') {
          query = query.eq('shipment_year', parsedYear);
        }
        if (voyageValue.isNotEmpty) {
          query = query.eq('voyage', voyageValue);
        }

        final unknownRaw = await query;
        final unknownRows =
            List<Map<String, dynamic>>.from(unknownRaw as List);

        bool containsIgnoreCase(dynamic source, String term) {
          if (term.trim().isEmpty) return true;
          return '${source ?? ''}'
              .toLowerCase()
              .contains(term.trim().toLowerCase());
        }

        final filtered = unknownRows.where((row) {
          if (!containsIgnoreCase(row['box_number'], boxNumber)) return false;
          if (!containsIgnoreCase(row['invoice_number'], invoice)) return false;
          if (!containsIgnoreCase(row['consignee_name'], recipient)) return false;
          if (!containsIgnoreCase(row['consignee_phone'], phone)) return false;

          final deletionStatus =
              '${row['deletion_status'] ?? 'active'}'.trim().toLowerCase();
          return deletionStatus != 'pending';
        });

        final existingIds = result.map((row) => '${row['id']}').toSet();
        for (final row in filtered) {
          if (existingIds.add('${row['id']}')) {
            result.add(row);
          }
        }
      } catch (_) {
        // 불명 화물 보강 실패가 기존 검색 RPC 결과까지 막지는 않도록 합니다.
      }
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> getRowsByIds(List<String> ids) async {
    if (!SupabaseConfig.isConfigured || ids.isEmpty) return const [];
    final numericIds = ids.map(int.tryParse).whereType<int>().toList();
    if (numericIds.isEmpty) return const [];
    final rows = await SupabaseService.client
        .from('shipments')
        .select()
        .inFilter('id', numericIds);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<int> upsertFromRows(List<Map<String, dynamic>> rows) async {
    final summary = await importDifferencesFromRows(rows);
    return summary.actions;
  }

  Future<ShipmentImportSummary> importDifferencesFromRows(
    List<Map<String, dynamic>> rows,
  ) async {
    if (!SupabaseConfig.isConfigured || rows.isEmpty) {
      return const ShipmentImportSummary();
    }

    // 대용량 Excel을 한 번의 RPC로 보내면 PostgreSQL statement_timeout(57014)에
    // 걸릴 수 있으므로 작은 묶음으로 나눠 순차 반영합니다.
    // 신규 화물만 추가하고 기존 화물의 차이는 승인 요청으로 보내며,
    // 동일값은 다시 저장하지 않습니다.
    // Keep each request below the shared DB budget even for complex rules.
    // Web uses the same 20-row starting size and timeout subdivision.
    const chunkSize = 20;
    var summary = const ShipmentImportSummary();

    for (var start = 0; start < rows.length; start += chunkSize) {
      final end = (start + chunkSize < rows.length)
          ? start + chunkSize
          : rows.length;
      final chunk = rows.sublist(start, end);
      summary += await _importShipmentDifferenceChunk(chunk);
    }

    return summary;
  }

  Future<ShipmentImportSummary> _importShipmentDifferenceChunk(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return const ShipmentImportSummary();

    final payload = rows.map(_shipmentPayload).toList();

    try {
      final result = await SupabaseService.client.rpc(
        'manager_import_shipment_differences_bulk',
        params: {'p_rows': payload},
      );
      return ShipmentImportSummary.fromRpc(result);
    } catch (error) {
      final message = error.toString();

      // DB statement_timeout이면 현재 묶음을 한 번 더 쪼개서 재시도합니다.
      // 최소 1행까지 자동 분할하고, 한 행도 실패하면 오류를 그대로 알립니다.
      final lower = message.toLowerCase();
      final isRetryable =
          message.contains('57014') ||
          lower.contains('statement timeout') ||
          lower.contains('connection abort') ||
          lower.contains('connection reset') ||
          lower.contains('connection closed') ||
          lower.contains('clientexception');

      if (isRetryable && rows.length > 1) {
        final middle = (rows.length / 2).ceil();
        final left = rows.sublist(0, middle);
        final right = rows.sublist(middle);

        final leftSummary = await _importShipmentDifferenceChunk(left);
        final rightSummary = await _importShipmentDifferenceChunk(right);
        return leftSummary + rightSummary;
      }

      rethrow;
    }
  }

  Future<void> updateRow(String id, Map<String, dynamic> changes) async {
    if (!SupabaseConfig.isConfigured || changes.isEmpty) return;
    await SupabaseService.client.from('shipments').update(changes).eq('id', id);
  }

  Future<void> setManualUncertain(String id, bool value) async {
    if (!SupabaseConfig.isConfigured) return;
    final numericId = int.tryParse(id.trim());
    if (numericId == null) throw StateError('화물 ID가 올바르지 않습니다.');
    await SupabaseService.client
        .from('shipments')
        .update({'manual_uncertain': value})
        .eq('id', numericId);
  }

  Future<List<Map<String, dynamic>>> listManualUncertainForAdmin() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final raw = await SupabaseService.client
        .from('shipments')
        .select()
        .eq('manual_uncertain', true)
        .order('shipment_year', ascending: false)
        .order('voyage', ascending: false)
        .order('box_number');
    return List<Map<String, dynamic>>.from(raw as List);
  }

  Future<void> adminUpdateBoxNumber({
    required String shipmentId,
    required String boxNumber,
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    final id = int.tryParse(shipmentId);
    if (id == null) return;
    await SupabaseService.client.rpc(
      'admin_update_shipment_box_number',
      params: {'p_shipment_id': id, 'p_box_number': boxNumber.trim()},
    );
  }

  Future<String> getNextBoxNumber({
    required String route,
    required int year,
    required String voyage,
    required String prefix,
  }) async {
    if (!SupabaseConfig.isConfigured) return '${prefix}001';
    final value = await SupabaseService.client.rpc(
      'manager_next_box_number',
      params: {
        'p_route': route,
        'p_year': year,
        'p_voyage': voyage.replaceAll('항차', '').trim(),
        'p_prefix': prefix,
      },
    );
    return '${value ?? '${prefix}001'}';
  }

  Future<Map<String, dynamic>> adminAddShipmentRow({
    required String route,
    required int year,
    required String voyage,
    required String boxNumber,
    required String invoiceNumber,
    required String consigneeName,
    required String consigneePhone,
    String notes = '',
    String unloadingZone = '',
    num? weightKg,
    num? lengthCm,
    num? widthCm,
    num? heightCm,
  }) async {
    if (!SupabaseConfig.isConfigured) return const {};
    final row = await SupabaseService.client.rpc(
      'admin_add_shipment_row',
      params: {
        'p_route': route,
        'p_year': year,
        'p_voyage': voyage.replaceAll('항차', '').trim(),
        'p_box_number': boxNumber.trim(),
        'p_invoice_number': invoiceNumber.trim(),
        'p_consignee_name': consigneeName.trim(),
        'p_consignee_phone': consigneePhone.trim(),
        'p_notes': notes.trim(),
        'p_unloading_zone': unloadingZone.trim(),
        'p_weight_kg': weightKg,
        'p_length_cm': lengthCm,
        'p_width_cm': widthCm,
        'p_height_cm': heightCm,
      },
    );
    return Map<String, dynamic>.from(row as Map);
  }

  Future<void> requestChanges({
    required List<String> shipmentIds,
    required Map<String, dynamic> changes,
  }) async {
    if (!SupabaseConfig.isConfigured || shipmentIds.isEmpty || changes.isEmpty) {
      return;
    }
    final ids = shipmentIds.map(int.tryParse).whereType<int>().toList();
    if (ids.isEmpty) return;
    await SupabaseService.client.rpc(
      'create_shipment_change_requests',
      params: {
        'p_shipment_ids': ids,
        'p_changes': changes,
      },
    );
  }

  Future<void> requestInvoiceCorrection({
    required String shipmentId,
    required String invoiceSuffix,
    required String claimantName,
    required String claimantPhone,
    String note = '',
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    final id = int.tryParse(shipmentId.trim());
    if (id == null) throw StateError('화물 ID가 올바르지 않습니다.');
    await SupabaseService.client.rpc(
      'create_invoice_correction_request',
      params: {
        'p_shipment_id': id,
        'p_invoice_suffix': invoiceSuffix.trim(),
        'p_claimant_name': claimantName.trim(),
        'p_claimant_phone': claimantPhone.trim(),
        'p_note': note.trim(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> getPendingChangeRequests() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final raw = await SupabaseService.client.rpc(
      'get_pending_shipment_change_requests',
    );
    final rows = List<Map<String, dynamic>>.from(raw as List);

    for (final request in rows) {
      try {
        final route = '${request['route'] ?? ''}';
        final year = (request['shipment_year'] as num?)?.toInt();
        final voyage = '${request['voyage'] ?? ''}';
        final box = '${request['box_number'] ?? ''}';
        if (route.isEmpty || year == null || voyage.isEmpty || box.isEmpty) {
          continue;
        }
        final matches = await SupabaseService.client
            .from('shipments')
            .select('data_locked')
            .eq('route', route)
            .eq('shipment_year', year)
            .eq('voyage', voyage)
            .eq('box_number', box)
            .limit(1);
        if (matches.isNotEmpty) {
          request['data_locked'] = matches.first['data_locked'] == true;
        }
      } catch (_) {
        // 잠금 표시 보강 실패가 기존 승인 요청 조회 자체를 막으면 안 됩니다.
      }
    }
    return rows;
  }

  Future<void> reviewChangeRequest({
    required int requestId,
    required String action,
    Map<String, dynamic> adminChanges = const {},
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.rpc(
      'review_shipment_change_request',
      params: {
        'p_request_id': requestId,
        'p_action': action,
        'p_admin_changes': adminChanges,
      },
    );
  }


  Future<void> requestShipmentDeletion(String shipmentId) async {
    if (!SupabaseConfig.isConfigured) return;
    final id = int.tryParse(shipmentId);
    if (id == null) return;
    await SupabaseService.client.rpc(
      'manager_request_shipment_deletion',
      params: {'p_shipment_id': id},
    );
  }

  Future<List<Map<String, dynamic>>> getPendingShipmentDeletions() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final rows = await SupabaseService.client.rpc(
      'manager_list_pending_shipment_deletions',
    );
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<void> cancelShipmentDeletion(String shipmentId) async {
    if (!SupabaseConfig.isConfigured) return;
    final id = int.tryParse(shipmentId);
    if (id == null) return;
    await SupabaseService.client.rpc(
      'manager_cancel_shipment_deletion',
      params: {'p_shipment_id': id},
    );
  }

  Future<void> deleteShipmentNow(String shipmentId) async {
    if (!SupabaseConfig.isConfigured) return;
    final id = int.tryParse(shipmentId);
    if (id == null) return;
    await SupabaseService.client.rpc(
      'manager_delete_shipment_now',
      params: {'p_shipment_id': id},
    );
  }

  Future<Shipment?> findByTrackingNumber(String trackingNumber) async {
    if (!SupabaseConfig.isConfigured) {
      return MockShipments.findByTracking(trackingNumber);
    }
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
    final year = int.tryParse(
      '${row['shipment_year'] ?? row['year'] ?? ''}'
          .replaceAll(RegExp(r'[^0-9]'), ''),
    );
    final voyage = '${row['voyage'] ?? ''}'
        .replaceAll('항차', '')
        .trim()
        .padLeft(2, '0');
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

