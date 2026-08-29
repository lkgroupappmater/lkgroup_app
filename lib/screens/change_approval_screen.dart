import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../services/shipment_service.dart';
import '../services/unknown_recipient_service.dart';

class ChangeApprovalScreen extends StatefulWidget {
  const ChangeApprovalScreen({super.key});

  @override
  State<ChangeApprovalScreen> createState() => _ChangeApprovalScreenState();
}

class _ChangeApprovalScreenState extends State<ChangeApprovalScreen> {
  List<Map<String, dynamic>> _requests = const [];
  List<Map<String, dynamic>> _unknownClaims = const [];
  final Set<int> _checked = <int>{};
  final Set<int> _editing = <int>{};
  final Map<int, Map<String, TextEditingController>> _controllers = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final group in _controllers.values) {
      for (final controller in group.values) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await ShipmentService.instance.getPendingChangeRequests();
      final unknownClaims =
          await UnknownRecipientService.instance.listPendingClaimsForAdmin();
      if (!mounted) return;
      setState(() {
        _requests = rows;
        _unknownClaims = unknownClaims;
        _checked.clear();
        _editing.clear();
      });
    } catch (error) {
      if (mounted) _message('승인 요청 조회 실패: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, TextEditingController> _editControllersFor(Map<String, dynamic> r) {
    final id = (r['request_id'] as num).toInt();
    return _controllers.putIfAbsent(id, () {
      String value(String key) => '${r[key] ?? ''}';
      return {
        'invoice_number': TextEditingController(text: value('invoice_number')),
        'consignee_name': TextEditingController(text: value('consignee_name')),
        'consignee_phone': TextEditingController(text: value('consignee_phone')),
        'notes': TextEditingController(text: value('notes')),
        'weight_kg': TextEditingController(text: value('weight_kg')),
        'length_cm': TextEditingController(text: value('length_cm')),
        'width_cm': TextEditingController(text: value('width_cm')),
        'height_cm': TextEditingController(text: value('height_cm')),
      };
    });
  }

  Map<String, dynamic> _adminChanges(Map<String, dynamic> r) {
    final c = _editControllersFor(r);
    final changes = <String, dynamic>{};
    void addText(String key) {
      final text = c[key]!.text.trim();
      if (text != '${r[key] ?? ''}'.trim()) changes[key] = text;
    }
    void addNum(String key) {
      final text = c[key]!.text.trim();
      final old = '${r[key] ?? ''}'.trim();
      if (text != old) changes[key] = text.isEmpty ? null : num.tryParse(text);
    }
    addText('invoice_number');
    addText('consignee_name');
    addText('consignee_phone');
    addText('notes');
    addNum('weight_kg');
    addNum('length_cm');
    addNum('width_cm');
    addNum('height_cm');
    return changes;
  }

  Future<void> _review(Map<String, dynamic> r, String action) async {
    final id = (r['request_id'] as num).toInt();
    try {
      final adminChanges = action == 'modified_approve' ? _adminChanges(r) : <String, dynamic>{};
      await ShipmentService.instance.reviewChangeRequest(
        requestId: id,
        action: action,
        adminChanges: adminChanges,
      );
      if (!mounted) return;
      _message(action == 'reject'
          ? '거절되었습니다.'
          : action == 'modified_approve'
              ? '수정 후 승인되었습니다.'
              : '승인되었습니다.');
      await _load();
    } catch (error) {
      _message('처리 실패: $error');
    }
  }

  Future<void> _reviewUnknownClaim(
    Map<String, dynamic> claim,
    String action,
  ) async {
    final id = (claim['claim_id'] as num).toInt();
    final approve = action == 'approve';

    if (approve) {
      final ok = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('수취인 불명 화물 확인 승인'),
              content: Text(
                '이 요청을 승인하면:\n'
                '이름: 수취인 불명 / ${claim['claimant_name'] ?? ''}\n'
                '연락처: ${claim['claimant_phone'] ?? ''}\n'
                '영수번호: 해당 항차 마지막 영수번호 다음 번호\n\n'
                '으로 반영됩니다.'
                '${claim['data_locked'] == true ? '\n\n데이터 잠금은 승인 후에도 유지됩니다.' : ''}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('확인 및 승인'),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok) return;
    }

    try {
      await UnknownRecipientService.instance.reviewClaim(
        claimId: id,
        action: action,
      );
      if (!mounted) return;
      _message(approve
          ? '수취인 불명 화물을 본인 화물로 확인 승인했습니다.'
          : '수취인 불명 화물 확인 요청을 거절했습니다.');
      await _load();
    } catch (error) {
      _message('수취인 불명 화물 요청 처리 실패: $error');
    }
  }

  Widget _unknownClaimCard(Map<String, dynamic> claim) {
    return Card(
      color: const Color(0xFFFFFBF2),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.help_outline, color: Colors.orange),
                SizedBox(width: 6),
                Text(
                  '수취인 불명 · 본인 화물 확인 요청',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${claim['box_number'] ?? ''} · ${claim['invoice_number'] ?? ''}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            Text(
              '${claim['route'] ?? ''} · ${claim['shipment_year'] ?? ''}년 · '
              '${claim['voyage'] ?? ''}항차',
            ),
            const SizedBox(height: 6),
            Text('현재 이름: ${claim['current_unknown_name'] ?? ''}'),
            Text('현재 연락처: ${claim['current_unknown_phone'] ?? ''}'),
            const Divider(height: 20),
            Text(
              '요청 회원: ${claim['claimant_name'] ?? ''} '
              '(${claim['requester_email'] ?? ''})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('요청 연락처: ${claim['claimant_phone'] ?? ''}'),
            if ('${claim['note'] ?? ''}'.trim().isNotEmpty)
              Text('확인 참고 내용: ${claim['note']}'),
            if (claim['data_locked'] == true) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.lock, size: 16, color: Colors.redAccent),
                  SizedBox(width: 5),
                  Text(
                    '데이터 수정 잠금된 화물',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _reviewUnknownClaim(claim, 'reject'),
                  child: const Text('거절'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: () => _reviewUnknownClaim(claim, 'approve'),
                  child: const Text('본인 화물 확인 승인'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  Future<void> _bulk(String action) async {
    final ids = _checked.toList();
    for (final id in ids) {
      final r = _requests.firstWhere((item) => (item['request_id'] as num).toInt() == id);
      await ShipmentService.instance.reviewChangeRequest(
        requestId: id,
        action: action,
      );
    }
    if (!mounted) return;
    _message(action == 'reject' ? '체크된 요청을 거절했습니다.' : '체크된 요청을 승인했습니다.');
    await _load();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('화물 내용 변경 승인 관리'),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
        ),
        backgroundColor: AppColors.background,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_unknownClaims.isNotEmpty) ...[
                      const Text(
                        '수취인 불명 화물 확인 요청',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._unknownClaims.map(_unknownClaimCard),
                      const SizedBox(height: 14),
                      const Divider(),
                      const SizedBox(height: 8),
                    ],
                    if (_requests.isEmpty && _unknownClaims.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: Text('대기 중인 화물 내용 변경 승인 요청이 없습니다.')),
                      )
                    if (_requests.isNotEmpty) ...[
                      CheckboxListTile(
                        value: _checked.length == _requests.length,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _checked.addAll(_requests.map(
                                (r) => (r['request_id'] as num).toInt()));
                          } else {
                            _checked.clear();
                          }
                        }),
                        title: const Text('전체 선택',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      ..._requests.map(_requestCard),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _checked.isEmpty ? null : () => _bulk('reject'),
                              child: const Text('체크된 요청 전체 거절'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: _checked.isEmpty ? null : () => _bulk('approve'),
                              child: const Text('체크된 요청 전체 승인'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
      );

  Widget _requestCard(Map<String, dynamic> r) {
    final id = (r['request_id'] as num).toInt();
    final editing = _editing.contains(id);
    final requested = Map<String, dynamic>.from(r['requested_changes'] ?? const {});
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: _checked.contains(id),
                  onChanged: (v) => setState(() =>
                      v == true ? _checked.add(id) : _checked.remove(id)),
                ),
                Expanded(
                  child: Text(
                    '${r['box_number'] ?? ''} · ${r['invoice_number'] ?? ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              '${r['route'] ?? ''} · ${r['shipment_year'] ?? ''}년 · ${r['voyage'] ?? ''}항차\n'
              '요청인: ${r['requester_name'] ?? ''} (${r['requester_email'] ?? ''})',
            ),
            if (r['data_locked'] == true) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.lock, size: 16, color: Colors.redAccent),
                  SizedBox(width: 5),
                  Text(
                    '데이터 수정 잠금된 화물',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            const Text('요청 내용', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(_changesText(requested)),
            if (editing) ...[
              const Divider(height: 22),
              const Text('관리자 수정', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._editorFields(r),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => setState(() => _editing.remove(id)),
                      child: const Text('취소'),
                    ),
                    FilledButton(
                      onPressed: () => _review(r, 'modified_approve'),
                      child: const Text('수정 후 승인'),
                    ),
                  ],
                ),
              ),
            ] else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      _editControllersFor(r);
                      setState(() => _editing.add(id));
                    },
                    child: const Text('수정'),
                  ),
                  TextButton(
                    onPressed: () => _review(r, 'reject'),
                    child: const Text('거절'),
                  ),
                  FilledButton(
                    onPressed: () => _review(r, 'approve'),
                    child: const Text('승인'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _editorFields(Map<String, dynamic> r) {
    final c = _editControllersFor(r);
    Widget field(String key, String label, {bool number = false, int maxLines = 1}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: c[key],
            maxLines: maxLines,
            keyboardType: number
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        );
    return [
      field('invoice_number', '송장번호'),
      field('consignee_name', '이름/라오스 수령인'),
      field('consignee_phone', '연락처'),
      field('notes', '기타 내용', maxLines: 2),
      Row(children: [
        Expanded(child: field('weight_kg', '무게(kg)', number: true)),
        const SizedBox(width: 8),
        Expanded(child: field('length_cm', '가로(cm)', number: true)),
      ]),
      Row(children: [
        Expanded(child: field('width_cm', '세로(cm)', number: true)),
        const SizedBox(width: 8),
        Expanded(child: field('height_cm', '높이(cm)', number: true)),
      ]),
    ];
  }

  String _changesText(Map<String, dynamic> changes) {
    if (changes.isEmpty) return '변경 내용 없음';
    const labels = {
      'consignee_name': '이름/수령인',
      'consignee_phone': '연락처',
      'notes': '기타 내용',
      'invoice_number': '송장번호',
      'weight_kg': '무게',
      'length_cm': '가로',
      'width_cm': '세로',
      'height_cm': '높이',
    };
    return changes.entries
        .map((e) => '${labels[e.key] ?? e.key}: ${e.value ?? ''}')
        .join('\n');
  }
}



