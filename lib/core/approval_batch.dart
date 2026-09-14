enum ApprovalKind {
  changes,
  invoiceClaims,
  unknownClaims,
  autoUnmatched,
  incomplete,
}

class ApprovalItem {
  ApprovalItem(this.kind, Map<String, dynamic> row) : row = Map.of(row);
  final ApprovalKind kind;
  final Map<String, dynamic> row;
  String get id =>
      '${row[switch (kind) {
            ApprovalKind.unknownClaims => 'claim_id',
            ApprovalKind.autoUnmatched => 'queue_id',
            ApprovalKind.incomplete => 'shipment_id',
            _ => 'request_id',
          }] ?? ''}';
  String get key => '${kind.name}:$id';
  String get label =>
      '${row['box_number'] ?? '-'} · ${row['invoice_number'] ?? '-'}';
  List<String> get fields => switch (kind) {
    ApprovalKind.changes => const [
      'invoice_number',
      'sender_name',
      'consignee_name',
      'consignee_phone',
      'contents',
      'package_type',
      'quantity',
      'weight_kg',
      'length_cm',
      'width_cm',
      'height_cm',
      'receipt_number',
      'unloading_zone',
      'notes',
      'received_at',
    ],
    ApprovalKind.autoUnmatched => const [
      'consignee_name',
      'consignee_phone',
      'invoice_number',
      'notes',
    ],
    ApprovalKind.incomplete => const [
      'invoice_number',
      'consignee_name',
      'consignee_phone',
      'receipt_number',
      'notes',
    ],
    _ => const [],
  };
  Map<String, dynamic> get values => {
    ...row,
    ...Map<String, dynamic>.from(row['requested_changes'] ?? {}),
  };
}

const approvalFieldLabels = {
  'invoice_number': '송장번호',
  'sender_name': '발신인',
  'consignee_name': '수취인 이름/회사명',
  'consignee_phone': '연락처',
  'contents': '내용물',
  'package_type': '포장형태',
  'quantity': '수량',
  'weight_kg': '중량 (kg)',
  'length_cm': '가로 (cm)',
  'width_cm': '세로 (cm)',
  'height_cm': '높이 (cm)',
  'receipt_number': '영수번호',
  'unloading_zone': '구획',
  'notes': '비고',
  'received_at': '접수일 (YYYY-MM-DD)',
};
const approvalNumericFields = {
  'quantity',
  'weight_kg',
  'length_cm',
  'width_cm',
  'height_cm',
};

/// An independent draft for each selected cargo; never copies one cargo onto another.
class ApprovalDraft {
  ApprovalDraft(this.item, {Map<String, dynamic>? saved}) {
    final initial = {...item.values, ...?saved};
    for (final field in item.fields) {
      values[field] = '${initial[field] ?? ''}';
    }
    lock =
        saved?['lock'] == true ||
        (saved == null && item.row['data_locked'] == true);
  }
  final ApprovalItem item;
  final values = <String, String>{};
  late bool lock;

  Map<String, dynamic> payload() {
    final data = <String, dynamic>{};
    for (final field in item.fields) {
      final text = values[field]!.trim();
      dynamic value = text;
      if (approvalNumericFields.contains(field)) {
        value = text.isEmpty ? null : num.tryParse(text);
        if (text.isNotEmpty &&
            (value == null ||
                !(value as num).isFinite ||
                value < 0 ||
                (field == 'quantity' && value % 1 != 0))) {
          throw FormatException(
            '${item.label}: ${approvalFieldLabels[field]} 값을 확인해 주세요.',
          );
        }
      }
      if (field == 'received_at' && text.isNotEmpty) {
        final date = DateTime.tryParse(text);
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
            date == null ||
            date.toIso8601String().substring(0, 10) != text) {
          throw FormatException('${item.label}: 접수일을 YYYY-MM-DD로 입력해 주세요.');
        }
      }
      // The server merges these edits with the original request. Untouched fields
      // must not overwrite a newer cargo value or erase another requested change.
      if (item.kind != ApprovalKind.changes ||
          text != '${item.values[field] ?? ''}'.trim())
        data[field] = value;
    }
    if (item.kind == ApprovalKind.autoUnmatched &&
        '${data['consignee_name'] ?? ''}'.isEmpty) {
      throw FormatException('${item.label}: 수취인 이름을 입력해 주세요.');
    }
    if (item.kind == ApprovalKind.incomplete) data['lock'] = lock;
    return data;
  }
}

class ApprovalBatchResult {
  final succeeded = <String>{};
  final failures = <String, String>{};
}

Future<ApprovalBatchResult> processApprovalBatch({
  required List<ApprovalItem> items,
  required Future<void> Function(ApprovalItem) worker,
  required bool Function() canContinue,
  void Function(int done, int total)? onProgress,
}) async {
  final result = ApprovalBatchResult();
  final targets = {for (final item in items) item.key: item}.values.toList();
  for (var i = 0; i < targets.length; i++) {
    final item = targets[i];
    if (!canContinue()) {
      for (final pending in targets.skip(i)) {
        result.failures[pending.key] = '로그인 상태가 변경되어 처리를 중단했습니다.';
      }
      break;
    }
    try {
      if (item.id.isEmpty) throw StateError('요청 ID가 없습니다.');
      await worker(item);
      result.succeeded.add(item.key);
    } catch (error) {
      result.failures[item.key] = '$error';
    }
    onProgress?.call(i + 1, targets.length);
  }
  return result;
}

/// Competing ownership requests need an explicit choice, not list-order approval.
Set<String> conflictingApprovalKeys(List<ApprovalItem> items, String action) {
  if (action != 'approve') return {};
  final groups = <String, List<String>>{};
  for (final item in items) {
    if (item.kind != ApprovalKind.invoiceClaims &&
        item.kind != ApprovalKind.unknownClaims)
      continue;
    final shipment = '${item.row['shipment_id'] ?? ''}';
    if (shipment.isNotEmpty)
      (groups['${item.kind.name}:$shipment'] ??= []).add(item.key);
  }
  return {
    for (final keys in groups.values)
      if (keys.toSet().length > 1) ...keys,
  };
}
