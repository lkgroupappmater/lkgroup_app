import '../config/supabase_config.dart';
import 'supabase_service.dart';

class UnknownRecipientService {
  UnknownRecipientService._();
  static final instance = UnknownRecipientService._();

  Future<List<Map<String, dynamic>>> listVisibleUnknownCargo() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final raw =
        await SupabaseService.client.rpc('list_unknown_recipient_cargo') as List;
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Future<void> resolveUnknownFromSearch({
    required String shipmentId,
    required String consigneeName,
    required String consigneePhone,
    String notes = '',
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    final id = int.tryParse(shipmentId.trim());
    if (id == null) throw StateError('화물 ID가 올바르지 않습니다.');
    await SupabaseService.client.rpc(
      'admin_resolve_unknown_recipient_from_search',
      params: {
        'p_shipment_id': id,
        'p_consignee_name': consigneeName.trim(),
        'p_consignee_phone': consigneePhone.trim(),
        'p_notes': notes.trim(),
      },
    );
  }

  Future<void> createClaim({
    required String shipmentId,
    required String claimantName,
    required String claimantPhone,
    String note = '',
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    final id = int.tryParse(shipmentId);
    if (id == null) throw StateError('화물 ID가 올바르지 않습니다.');

    await SupabaseService.client.rpc(
      'create_unknown_recipient_claim',
      params: {
        'p_shipment_id': id,
        'p_claimant_name': claimantName.trim(),
        'p_claimant_phone': claimantPhone.trim(),
        'p_note': note.trim(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> listPendingClaimsForAdmin() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final raw =
        await SupabaseService.client.rpc('admin_list_unknown_recipient_claims')
            as List;
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> listAutoUnmatchedForAdmin() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final raw = await SupabaseService.client
        .rpc('admin_list_auto_unmatched_recipients') as List;
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> listIncompleteForAdmin() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final raw =
        await SupabaseService.client.rpc('admin_list_incomplete_shipments')
            as List;
    return raw.map((e) {
      final row = Map<String, dynamic>.from(e as Map);
      row['id'] ??= row['shipment_id'];
      row['reason'] ??= row['uncertainty_reason'];
      return row;
    }).toList(growable: false);
  }

  Future<void> reviewIncomplete({
    required String shipmentId,
    required String invoiceNumber,
    required String consigneeName,
    required String consigneePhone,
    required String receiptNumber,
    required String notes,
    required bool lock,
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    final id = shipmentId.trim();
    if (id.isEmpty) throw StateError('화물 ID가 비어 있습니다.');
    await SupabaseService.client.rpc(
      'admin_review_incomplete_shipment',
      params: {
        'p_shipment_id': id,
        'p_invoice_number': invoiceNumber.trim(),
        'p_consignee_name': consigneeName.trim(),
        'p_consignee_phone': consigneePhone.trim(),
        'p_receipt_number': receiptNumber.trim(),
        'p_notes': notes.trim(),
        'p_lock': lock,
      },
    );
  }
  Future<Map<String, dynamic>> checkReceiptNumber({
    required String shipmentId,
    required String receiptNumber,
  }) async {
    if (!SupabaseConfig.isConfigured) {
      return const {'duplicate': false};
    }
    final raw = await SupabaseService.client.rpc(
      'admin_check_receipt_number',
      params: {
        'p_shipment_id': shipmentId.trim(),
        'p_receipt_number': receiptNumber.trim(),
      },
    );
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<void> resolveAutoUnmatched({
    required int queueId,
    required String consigneeName,
    required String consigneePhone,
    required String invoiceNumber,
    required String notes,
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.rpc(
      'admin_resolve_auto_unmatched_recipient',
      params: {
        'p_queue_id': queueId,
        'p_consignee_name': consigneeName.trim(),
        'p_consignee_phone': consigneePhone.trim(),
        'p_invoice_number': invoiceNumber.trim(),
        'p_notes': notes.trim(),
      },
    );
  }

  Future<void> keepAutoUnmatched(int queueId) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.rpc(
      'admin_keep_auto_unmatched_recipient',
      params: {'p_queue_id': queueId},
    );
  }

  Future<void> reviewClaim({
    required int claimId,
    required String action,
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.rpc(
      'admin_review_unknown_recipient_claim',
      params: {
        'p_claim_id': claimId,
        'p_action': action,
      },
    );
  }
}


