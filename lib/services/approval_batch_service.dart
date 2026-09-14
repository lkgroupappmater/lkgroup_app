import '../core/approval_batch.dart';
import 'shipment_service.dart';
import 'supabase_service.dart';

typedef ApprovalRpc = Future<dynamic> Function(
  String name,
  Map<String, dynamic> params,
);

class ApprovalBatchService {
  ApprovalBatchService({
    ApprovalRpc? rpc,
    Future<void> Function(String)? clearManualUncertain,
  }) : _rpc =
           rpc ??
           ((name, params) => SupabaseService.client.rpc(name, params: params)),
       _clearManualUncertain =
           clearManualUncertain ??
           ((id) => ShipmentService.instance.setManualUncertain(id, false));
  final ApprovalRpc _rpc;
  final Future<void> Function(String) _clearManualUncertain;

  Future<void> apply(
    ApprovalItem item,
    String action, {
    Map<String, dynamic> changes = const {},
  }) async {
    final allowed = switch (item.kind) {
      ApprovalKind.changes => const {'approve', 'reject', 'modified_approve'},
      ApprovalKind.invoiceClaims ||
      ApprovalKind.unknownClaims => const {'approve', 'reject'},
      ApprovalKind.autoUnmatched => const {'keep', 'resolve'},
      ApprovalKind.incomplete => const {'edit', 'complete'},
    };
    if (!allowed.contains(action) || item.id.isEmpty)
      throw StateError('처리할 요청을 다시 확인해 주세요.');
    switch (item.kind) {
      case ApprovalKind.changes:
        await _rpc('review_shipment_change_request', {
          'p_request_id': int.parse(item.id),
          'p_action': action,
          'p_admin_changes': action == 'modified_approve'
              ? changes
              : <String, dynamic>{},
        });
      case ApprovalKind.invoiceClaims:
        await _rpc('admin_review_invoice_correction_request', {
          'p_request_id': int.parse(item.id),
          'p_action': action,
        });
      case ApprovalKind.unknownClaims:
        await _rpc('admin_review_unknown_recipient_claim', {
          'p_claim_id': int.parse(item.id),
          'p_action': action,
        });
      case ApprovalKind.autoUnmatched:
        if (action == 'keep') {
          await _rpc('admin_keep_auto_unmatched_recipient', {
            'p_queue_id': int.parse(item.id),
          });
        } else {
          final values = {...item.values, ...changes};
          await _rpc('admin_resolve_auto_unmatched_recipient', {
            'p_queue_id': int.parse(item.id),
            for (final key in item.fields)
              'p_$key': '${values[key] ?? ''}'.trim(),
          });
        }
      case ApprovalKind.incomplete:
        final values = {...item.values, ...changes};
        final check = await _rpc('admin_check_receipt_number', {
          'p_shipment_id': item.id,
          'p_receipt_number': '${values['receipt_number'] ?? ''}'.trim(),
        });
        if (check is Map && check['duplicate'] == true) {
          throw StateError(
            '이미 사용 중인 영수번호입니다. 추천: ${check['suggested_receipt'] ?? ''}',
          );
        }
        await _rpc('admin_review_incomplete_shipment', {
          'p_shipment_id': item.id,
          for (final key in item.fields)
            'p_$key': '${values[key] ?? ''}'.trim(),
          'p_lock':
              action == 'complete' ||
              (changes['lock'] ?? item.row['data_locked']) == true,
        });
        if (item.row['manual_uncertain'] == true)
          await _clearManualUncertain(item.id);
    }
  }
}
