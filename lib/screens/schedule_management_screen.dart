import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/route_catalog.dart';
import '../models/app_user.dart';
import '../services/content_service.dart';
import '../utils/form_validators.dart';

class ScheduleManagementScreen extends StatefulWidget {
  const ScheduleManagementScreen({super.key, required this.user});
  final AppUser user;

  @override
  State<ScheduleManagementScreen> createState() =>
      _ScheduleManagementScreenState();
}

class _ScheduleManagementScreenState extends State<ScheduleManagementScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _text(Map<String, dynamic> row, String key) => '${row[key] ?? ''}';

  Future<void> _load() async {
    try {
      final rows = await ContentService.fetchSchedules(includePendingDeletion: true);
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('일정 조회 실패: $e');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _requestDelete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('선적 일정 삭제 확인'),
        content: const Text(
          '삭제하면 홈 화면에서는 즉시 보이지 않습니다.\n'
          '삭제된 자료는 30일 동안 임시 보관 후 완전히 삭제됩니다.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('확인')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ContentService.requestScheduleDeletion(_text(row, 'id'));
      _message('삭제 대기중으로 변경했습니다. 30일 후 완전히 삭제됩니다.');
      await _load();
    } catch (e) {
      _message('삭제 요청 실패: $e');
    }
  }

  Future<void> _restore(Map<String, dynamic> row) async {
    try {
      await ContentService.restoreSchedule(_text(row, 'id'));
      _message('삭제를 취소했습니다. 홈 화면에 다시 표시됩니다.');
      await _load();
    } catch (e) {
      _message('삭제 취소 실패: $e');
    }
  }

  Future<void> _hardDelete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('바로 삭제'),
        content: const Text('임시 보관 기간을 무시하고 DB에서 완전히 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('바로 삭제')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ContentService.hardDeleteSchedule(_text(row, 'id'));
      _message('선적 일정을 완전히 삭제했습니다.');
      await _load();
    } catch (e) {
      _message('바로 삭제 실패: $e');
    }
  }

  Future<void> _showEditor({Map<String, dynamic>? existing}) async {
    final formKey = GlobalKey<FormState>();
    final from = TextEditingController(text: _text(existing ?? {}, 'origin'));
    final to = TextEditingController(text: _text(existing ?? {}, 'destination'));
    final voyage = TextEditingController(text: _text(existing ?? {}, 'voyage'));
    final close = TextEditingController(text: _text(existing ?? {}, 'booking_close_date'));
    final eta = TextEditingController(text: _text(existing ?? {}, 'estimated_arrival_date'));
    final detail = TextEditingController(text: _text(existing ?? {}, 'detail'));
    var route = _text(existing ?? {}, 'route').isEmpty
        ? RouteCatalog.routes.first
        : _text(existing!, 'route');
    var year = _text(existing ?? {}, 'year').isEmpty
        ? '2026년'
        : _text(existing!, 'year');

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '선적 일정 추가' : '선적 일정 편집'),
          content: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: route,
                    decoration: const InputDecoration(labelText: '운송 경로'),
                    items: RouteCatalog.routes
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => route = v ?? route),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: year,
                    decoration: const InputDecoration(labelText: '년도'),
                    items: const ['2026년', '2027년', '2028년']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => year = v ?? year),
                  ),
                  TextFormField(
                    controller: voyage,
                    decoration: const InputDecoration(
                      labelText: '항차',
                      hintText: '예: 17항차',
                    ),
                    validator: (v) => FormValidators.requiredText(v, '항차'),
                  ),
                  TextFormField(
                    controller: from,
                    decoration: const InputDecoration(
                      labelText: '출발지',
                      hintText: '예: 인천 국제 공항',
                    ),
                    validator: (v) => FormValidators.requiredText(v, '출발지'),
                  ),
                  TextFormField(
                    controller: to,
                    decoration: const InputDecoration(
                      labelText: '도착지',
                      hintText: '예: 라오스 왓따이 공항',
                    ),
                    validator: (v) => FormValidators.requiredText(v, '도착지'),
                  ),
                  TextFormField(
                    controller: close,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(
                      labelText: '접수 마감일',
                      hintText: '예: 2026-09-03',
                      helperText: '20260903으로 입력해도 작성 시 2026-09-03으로 자동 변환됩니다.',
                    ),
                    validator: (v) => FormValidators.date(v, required: true),
                  ),
                  TextFormField(
                    controller: eta,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(
                      labelText: '도착 예정일',
                      hintText: '예: 2026-09-04',
                      helperText: 'YYYY-MM-DD 또는 YYYYMMDD 형식',
                    ),
                    validator: (v) => FormValidators.date(v, required: true),
                  ),
                  TextFormField(
                    controller: detail,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '상세 내용 또는 추가 내용',
                      hintText: '예: 출항/도착 일정은 현지 사정에 따라 변경될 수 있습니다.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final item = <String, dynamic>{
                  'route': route,
                  'year': year,
                  'voyage': voyage.text.trim(),
                  'origin': from.text.trim(),
                  'destination': to.text.trim(),
                  'booking_close_date': FormValidators.normalizeDate(close.text),
                  'estimated_arrival_date': FormValidators.normalizeDate(eta.text),
                  'detail': detail.text.trim(),
                };
                if (existing != null && existing['status'] != null) {
                  item['status'] = existing['status'];
                }
                try {
                  if (existing == null) {
                    await ContentService.createSchedule(item);
                  } else {
                    await ContentService.updateSchedule(_text(existing, 'id'), item);
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _load();
                } catch (e) {
                  _message('${existing == null ? '작성' : '저장'} 실패: $e');
                }
              },
              child: Text(existing == null ? '작성' : '저장'),
            ),
          ],
        ),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 250));
    from.dispose();
    to.dispose();
    voyage.dispose();
    close.dispose();
    eta.dispose();
    detail.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('선적 일정 목록 관리'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        backgroundColor: AppColors.background,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showEditor(),
          icon: const Icon(Icons.add),
          label: const Text('일정 추가'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_items.isEmpty)
                      const Card(child: ListTile(title: Text('등록된 선적 일정이 없습니다.'))),
                    ..._items.map((row) {
                      final pending = _text(row, 'deletion_status') == 'pending';
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              ListTile(
                                title: Text(
                                  '${_text(row, 'route')} · ${_text(row, 'year')} ${_text(row, 'voyage')}',
                                ),
                                subtitle: Text(
                                  '${_text(row, 'origin')} → ${_text(row, 'destination')}\n'
                                  '마감: ${_text(row, 'booking_close_date')} · 도착예정: ${_text(row, 'estimated_arrival_date')}\n'
                                  '${_text(row, 'detail')}',
                                ),
                                isThreeLine: true,
                                trailing: pending
                                    ? const Chip(label: Text('삭제 대기중'))
                                    : Wrap(
                                        children: [
                                          IconButton(
                                            onPressed: () => _showEditor(existing: row),
                                            icon: const Icon(Icons.edit_outlined),
                                          ),
                                          IconButton(
                                            onPressed: () => _requestDelete(row),
                                            icon: const Icon(Icons.delete_outline, color: AppColors.error),
                                          ),
                                        ],
                                      ),
                              ),
                              if (pending)
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _restore(row),
                                        child: const Text('삭제 취소'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: () => _hardDelete(row),
                                        child: const Text('바로 삭제'),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
      );
}
