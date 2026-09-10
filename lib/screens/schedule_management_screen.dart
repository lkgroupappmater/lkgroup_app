import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../core/route_catalog.dart';
import '../core/shipment_period_labels.dart';
import '../core/ui_localizations.dart';
import '../models/app_user.dart';
import '../services/content_service.dart';
import '../widgets/content_media.dart';
import '../utils/form_validators.dart';

class ScheduleManagementScreen extends StatefulWidget {
  const ScheduleManagementScreen({
    super.key,
    required this.user,
    this.language = AppLanguage.korean,
  });
  final AppUser user;
  final AppLanguage language;

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
  String _u(String korean) => UiLocalizations.get(widget.language, korean);
  String _uf(String korean, Map<String, Object?> values) =>
      UiLocalizations.format(widget.language, korean, values);
  String _ue(String prefix, Object error) =>
      UiLocalizations.error(widget.language, prefix, error);
  String? _validation(String? value) => value == null ? null : _u(value);
  String _yearLabel(String value) =>
      ShipmentPeriodLabels.year(value, widget.language);
  String _voyageLabel(String value) =>
      ShipmentPeriodLabels.voyage(value, widget.language);

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
      _message(_ue('일정 조회 실패', e));
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
        title: Text(_u('선적 일정 삭제 확인')),
        content: Text(_u(
          '삭제하면 홈 화면에서는 즉시 보이지 않습니다.\n삭제된 자료는 30일 동안 임시 보관 후 완전히 삭제됩니다.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_u('취소'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_u('확인'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ContentService.requestScheduleDeletion(_text(row, 'id'));
      _message(_u('삭제 대기중으로 변경했습니다. 30일 후 완전히 삭제됩니다.'));
      await _load();
    } catch (e) {
      _message(_ue('삭제 요청 실패', e));
    }
  }

  Future<void> _restore(Map<String, dynamic> row) async {
    try {
      await ContentService.restoreSchedule(_text(row, 'id'));
      _message(_u('삭제를 취소했습니다. 홈 화면에 다시 표시됩니다.'));
      await _load();
    } catch (e) {
      _message(_ue('삭제 취소 실패', e));
    }
  }

  Future<void> _hardDelete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_u('바로 삭제')),
        content: Text(_u('임시 보관 기간을 무시하고 DB에서 완전히 삭제할까요?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_u('취소'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_u('바로 삭제'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ContentService.hardDeleteSchedule(_text(row, 'id'));
      _message(_u('선적 일정을 완전히 삭제했습니다.'));
      await _load();
    } catch (e) {
      _message(_ue('바로 삭제 실패', e));
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
    final routeEn =
        TextEditingController(text: _text(existing ?? {}, 'route_en'));
    final originEn =
        TextEditingController(text: _text(existing ?? {}, 'origin_en'));
    final destinationEn =
        TextEditingController(text: _text(existing ?? {}, 'destination_en'));
    final statusEn =
        TextEditingController(text: _text(existing ?? {}, 'status_en'));
    final detailEn =
        TextEditingController(text: _text(existing ?? {}, 'detail_en'));
    final routeLo =
        TextEditingController(text: _text(existing ?? {}, 'route_lo'));
    final originLo =
        TextEditingController(text: _text(existing ?? {}, 'origin_lo'));
    final destinationLo =
        TextEditingController(text: _text(existing ?? {}, 'destination_lo'));
    final statusLo =
        TextEditingController(text: _text(existing ?? {}, 'status_lo'));
    final detailLo =
        TextEditingController(text: _text(existing ?? {}, 'detail_lo'));
    var route = _text(existing ?? {}, 'route').isEmpty
        ? RouteCatalog.routes.first
        : _text(existing!, 'route');
    var year = _text(existing ?? {}, 'year').isEmpty
        ? '2026년'
        : _text(existing!, 'year');

    final attachments = contentAttachments(existing?['attachments']);
    bool mediaBusy = false;
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => PopScope(canPop: !mediaBusy && !saving, child: AlertDialog(
          title: Text(_u(existing == null ? '선적 일정 추가' : '선적 일정 편집')),
          content: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: route,
                    decoration: InputDecoration(labelText: _u('운송 경로')),
                    items: RouteCatalog.routes
                        .map((e) => DropdownMenuItem(
                              value: e,
                              child: Text(RouteCatalog.localizedLabel(
                                e,
                                widget.language,
                              )),
                            ))
                        .toList(),
                    onChanged: (v) => setDialogState(() => route = v ?? route),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: year,
                    decoration: InputDecoration(labelText: _u('년도')),
                    items: const ['2026년', '2027년', '2028년']
                        .map((e) => DropdownMenuItem(
                              value: e,
                              child: Text(_yearLabel(e)),
                            ))
                        .toList(),
                    onChanged: (v) => setDialogState(() => year = v ?? year),
                  ),
                  TextFormField(
                    controller: voyage,
                    decoration: InputDecoration(
                      labelText: _u('항차'),
                      hintText: _u('예: 17항차'),
                    ),
                    validator: (v) => _validation(
                      FormValidators.requiredText(v, '항차'),
                    ),
                  ),
                  TextFormField(
                    controller: from,
                    decoration: InputDecoration(
                      labelText: _u('출발지'),
                      hintText: _u('예: 인천 국제 공항'),
                    ),
                    validator: (v) => _validation(
                      FormValidators.requiredText(v, '출발지'),
                    ),
                  ),
                  TextFormField(
                    controller: to,
                    decoration: InputDecoration(
                      labelText: _u('도착지'),
                      hintText: _u('예: 라오스 왓따이 공항'),
                    ),
                    validator: (v) => _validation(
                      FormValidators.requiredText(v, '도착지'),
                    ),
                  ),
                  TextFormField(
                    controller: close,
                    keyboardType: TextInputType.datetime,
                    decoration: InputDecoration(
                      labelText: _u('접수 마감일'),
                      hintText: '2026-09-03',
                      helperText: _u('20260903으로 입력해도 작성 시 2026-09-03으로 자동 변환됩니다.'),
                    ),
                    validator: (v) => _validation(
                      FormValidators.date(v, required: true),
                    ),
                  ),
                  TextFormField(
                    controller: eta,
                    keyboardType: TextInputType.datetime,
                    decoration: InputDecoration(
                      labelText: _u('도착 예정일'),
                      hintText: '2026-09-04',
                      helperText: _u('YYYY-MM-DD 또는 YYYYMMDD 형식'),
                    ),
                    validator: (v) => _validation(
                      FormValidators.date(v, required: true),
                    ),
                  ),
                  IgnorePointer(ignoring: saving, child: ContentMediaEditor(items: attachments, kind: 'schedule', language: widget.language, onBusy: (value) { if (dialogContext.mounted) setDialogState(() => mediaBusy=value); })),
                  TextFormField(
                    controller: detail,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: _u('상세 내용 또는 추가 내용'),
                      hintText: _u('예: 출항/도착 일정은 현지 사정에 따라 변경될 수 있습니다.'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _u('비어 있는 영어·라오스어는 자동 번역됩니다. 직접 입력한 번역은 우선 저장됩니다.'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('English · ${_u('직접 입력 (선택)')}'),
                    children: [
                      TextFormField(controller: routeEn, decoration: const InputDecoration(labelText: 'Route')),
                      TextFormField(controller: originEn, decoration: const InputDecoration(labelText: 'Origin')),
                      TextFormField(controller: destinationEn, decoration: const InputDecoration(labelText: 'Destination')),
                      TextFormField(controller: statusEn, decoration: const InputDecoration(labelText: 'Status')),
                      TextFormField(controller: detailEn, maxLines: 3, decoration: const InputDecoration(labelText: 'Detail')),
                    ],
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('ລາວ · ${_u('직접 입력 (선택)')}'),
                    children: [
                      TextFormField(controller: routeLo, decoration: const InputDecoration(labelText: 'ເສັ້ນທາງ')),
                      TextFormField(controller: originLo, decoration: const InputDecoration(labelText: 'ຕົ້ນທາງ')),
                      TextFormField(controller: destinationLo, decoration: const InputDecoration(labelText: 'ປາຍທາງ')),
                      TextFormField(controller: statusLo, decoration: const InputDecoration(labelText: 'ສະຖານະ')),
                      TextFormField(controller: detailLo, maxLines: 3, decoration: const InputDecoration(labelText: 'ລາຍລະອຽດ')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: mediaBusy || saving ? null : () => Navigator.pop(dialogContext),
              child: Text(_u('취소')),
            ),
            FilledButton(
              onPressed: mediaBusy || saving ? null : () async {
                if (!formKey.currentState!.validate()) return;
                final item = <String, dynamic>{
                  'attachments': attachments,
                  'route': route,
                  'year': year,
                  'voyage': voyage.text.trim(),
                  'origin': from.text.trim(),
                  'destination': to.text.trim(),
                  'booking_close_date': FormValidators.normalizeDate(close.text),
                  'estimated_arrival_date': FormValidators.normalizeDate(eta.text),
                  'detail': detail.text.trim(),
                  'route_en': routeEn.text.trim(),
                  'origin_en': originEn.text.trim(),
                  'destination_en': destinationEn.text.trim(),
                  'status_en': statusEn.text.trim(),
                  'detail_en': detailEn.text.trim(),
                  'route_lo': routeLo.text.trim(),
                  'origin_lo': originLo.text.trim(),
                  'destination_lo': destinationLo.text.trim(),
                  'status_lo': statusLo.text.trim(),
                  'detail_lo': detailLo.text.trim(),
                };
                item['status'] = existing?['status'] ?? 'scheduled';
                setDialogState(() => saving=true);
                try {
                  if (existing == null) {
                    await ContentService.createSchedule(item);
                  } else {
                    await ContentService.updateSchedule(_text(existing, 'id'), item, expectedUpdatedAt: existing['updated_at']?.toString());
                  }
                  if (dialogContext.mounted) { setDialogState(() => saving=false); Navigator.pop(dialogContext); }
                  await _load();
                } catch (e) {
                  _message(_ue(existing == null ? '작성 실패' : '저장 실패', e));
                } finally {
                  if (dialogContext.mounted) setDialogState(() => saving=false);
                }
              },
              child: Text(_u(existing == null ? '작성' : '저장')),
            ),
          ],
        )),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 250));
    from.dispose();
    to.dispose();
    voyage.dispose();
    close.dispose();
    eta.dispose();
    detail.dispose();
    routeEn.dispose();
    originEn.dispose();
    destinationEn.dispose();
    statusEn.dispose();
    detailEn.dispose();
    routeLo.dispose();
    originLo.dispose();
    destinationLo.dispose();
    statusLo.dispose();
    detailLo.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_u('선적 일정 목록 관리')),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        backgroundColor: AppColors.background,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showEditor(),
          icon: const Icon(Icons.add),
          label: Text(_u('일정 추가')),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_items.isEmpty)
                      Card(child: ListTile(title: Text(_u('등록된 선적 일정이 없습니다.')))),
                    ..._items.map((row) {
                      final pending = _text(row, 'deletion_status') == 'pending';
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              ListTile(
                                title: Text(
                                  '${RouteCatalog.localizedLabel(_text(row, 'route'), widget.language)} · '
                                  '${_yearLabel(_text(row, 'year'))} '
                                  '${_voyageLabel(_text(row, 'voyage'))}',
                                ),
                                subtitle: Text(
                                  '${_text(row, 'origin')} → ${_text(row, 'destination')}\n'
                                  '${_uf('마감: {close} · 도착예정: {arrival}', {
                                    'close': _text(row, 'booking_close_date'),
                                    'arrival': _text(row, 'estimated_arrival_date'),
                                  })}\n'
                                  '${_text(row, 'detail')}',
                                ),
                                isThreeLine: true,
                                trailing: pending
                                    ? Chip(label: Text(_u('삭제 대기중')))
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
                                        child: Text(_u('삭제 취소')),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: () => _hardDelete(row),
                                        child: Text(_u('바로 삭제')),
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
