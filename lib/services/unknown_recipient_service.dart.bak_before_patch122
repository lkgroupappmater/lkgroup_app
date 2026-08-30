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
