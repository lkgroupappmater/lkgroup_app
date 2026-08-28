import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../core/route_catalog.dart';
import '../services/quote_freight_calculator.dart';
import '../services/quote_service.dart';

final List<String> _transportRoutes = RouteCatalog.routes;

class _BoxEntry {
  String weight = '';
  String width = '';
  String length = '';
  String height = '';
  String quantity = '1';
  bool selected = true;
}

class QuoteRequestBody extends StatefulWidget {
  const QuoteRequestBody({
    super.key,
    this.language = AppLanguage.korean,
    this.onRequestLogin,
    this.onNotificationsChanged,
  });

  final AppLanguage language;
  final VoidCallback? onRequestLogin;
  final VoidCallback? onNotificationsChanged;

  @override
  State<QuoteRequestBody> createState() => _QuoteRequestBodyState();
}

class _QuoteRequestBodyState extends State<QuoteRequestBody> {
  String _selectedRoute = _transportRoutes.first;
  final List<_BoxEntry> _boxes = [_BoxEntry()];
  QuoteFreightResult? _calculation;
  List<Map<String, dynamic>> _specialQuotes = const [];
  bool _loadingQuotes = false;
  bool _movingCargo = false;

  bool get _isLoggedIn => !SupabaseConfig.isConfigured ||
      Supabase.instance.client.auth.currentUser != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSpecialQuotes());
  }

  void _addBox() => setState(() {
        _boxes.add(_BoxEntry());
        _calculation = null;
      });

  void _removeBox(int i) {
    if (_boxes.length <= 1) return;
    setState(() {
      _boxes.removeAt(i);
      _calculation = null;
    });
  }

  void _setAllBoxes(bool selected) {
    setState(() {
      for (final box in _boxes) {
        box.selected = selected;
      }
      _calculation = null;
    });
  }

  void _requireLoginMessage() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('로그인 필요'),
        content: const Text('운임 확인 및 견적 요청은 회원 로그인 후 이용하실 수 있습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.navyPrimary,
              foregroundColor: AppColors.white,
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              widget.onRequestLogin?.call();
            },
            child: const Text('회원 로그인'),
          ),
        ],
      ),
    );
  }

  Future<void> _calculateFreight() async {
    if (!_isLoggedIn) {
      _requireLoginMessage();
      return;
    }
    final selected = <QuoteBoxInput>[];
    for (var i = 0; i < _boxes.length; i++) {
      final box = _boxes[i];
      if (!box.selected) continue;
      final weight = double.tryParse(box.weight);
      final width = double.tryParse(box.width);
      final length = double.tryParse(box.length);
      final height = double.tryParse(box.height);
      final quantity = int.tryParse(box.quantity) ?? 1;
      if (weight == null || width == null || length == null || height == null) {
        _message('선택한 박스의 무게와 가로·세로·높이를 모두 입력해 주세요.');
        return;
      }
      selected.add(QuoteBoxInput(
        index: i + 1,
        weightKg: weight,
        lengthCm: length,
        widthCm: width,
        heightCm: height,
        quantity: quantity,
      ));
    }
    if (selected.isEmpty) {
      _message('운임을 확인할 박스를 하나 이상 선택해 주세요.');
      return;
    }

    try {
      final result = QuoteFreightCalculator.calculate(
        routeLabel: _selectedRoute,
        boxes: selected,
        movingCargo: _movingCargo,
      );
      setState(() => _calculation = result);
    } catch (error) {
      _message('$error\n대량 혹은 특수 견적 요청을 이용해 주세요.');
    }
  }

  Future<void> _loadSpecialQuotes() async {
    if (!_isLoggedIn || !SupabaseConfig.isConfigured) {
      if (mounted) setState(() => _specialQuotes = const []);
      return;
    }
    setState(() => _loadingQuotes = true);
    try {
      final rows = await QuoteService.instance.listMySpecialQuotes();
      if (!mounted) return;
      setState(() => _specialQuotes = rows);
      widget.onNotificationsChanged?.call();
    } catch (error) {
      if (mounted) _message('견적 요청 조회 실패: $error');
    } finally {
      if (mounted) setState(() => _loadingQuotes = false);
    }
  }

  Future<void> _openSpecialQuoteForm({Map<String, dynamic>? existing}) async {
    if (!_isLoggedIn) {
      _requireLoginMessage();
      return;
    }

    var route = '${existing?['route'] ?? _selectedRoute}';
    if (!_transportRoutes.contains(route)) route = _transportRoutes.first;
    final titleCtrl = TextEditingController(text: '${existing?['subject'] ?? ''}');
    final contentCtrl = TextEditingController(text: '${existing?['content'] ?? ''}');
    final contactCtrl = TextEditingController(text: '${existing?['other_contact'] ?? ''}');

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '대량 혹은 특수 견적 요청' : '견적 요청 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: route,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '운송 경로',
                    border: OutlineInputBorder(),
                  ),
                  items: _transportRoutes
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => route = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: '제목',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: contentCtrl,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: '내용',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: contactCtrl,
                  decoration: const InputDecoration(
                    labelText: '기타 연락처',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty || contentCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('제목과 내용을 입력해 주세요.')),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(existing == null ? '견적 요청' : '수정 저장'),
            ),
          ],
        ),
      ),
    );

    if (submitted == true) {
      try {
        if (existing == null) {
          await QuoteService.instance.createSpecialQuote(
            route: route,
            subject: titleCtrl.text.trim(),
            content: contentCtrl.text.trim(),
            otherContact: contactCtrl.text.trim(),
          );
          _message('견적 요청을 보냈습니다.');
        } else {
          await QuoteService.instance.updateSpecialQuote(
            quoteId: _int(existing['id']),
            route: route,
            subject: titleCtrl.text.trim(),
            content: contentCtrl.text.trim(),
            otherContact: contactCtrl.text.trim(),
          );
          _message('견적 요청을 수정했습니다.');
        }
        await _loadSpecialQuotes();
      } catch (error) {
        _message('견적 요청 처리 실패: $error');
      }
    }
    titleCtrl.dispose();
    contentCtrl.dispose();
    contactCtrl.dispose();
  }

  Future<void> _addReply(Map<String, dynamic> quote) async {
    final ctrl = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('추가 회신'),
        content: TextField(
          controller: ctrl,
          minLines: 3,
          maxLines: 7,
          decoration: const InputDecoration(
            labelText: '추가 내용',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('송부'),
          ),
        ],
      ),
    );
    if (send == true && ctrl.text.trim().isNotEmpty) {
      try {
        await QuoteService.instance.addSpecialQuoteMessage(
          quoteId: _int(quote['id']),
          message: ctrl.text.trim(),
        );
        await _loadSpecialQuotes();
      } catch (error) {
        _message('추가 회신 실패: $error');
      }
    }
    ctrl.dispose();
  }

  Future<void> _requestDelete(Map<String, dynamic> quote) async {
    final ok = await _confirm('견적 요청을 삭제하시겠습니까?');
    if (!ok) return;
    try {
      await QuoteService.instance.requestDelete(_int(quote['id']));
      await _loadSpecialQuotes();
    } catch (error) {
      _message('삭제 처리 실패: $error');
    }
  }

  Future<void> _cancelDelete(Map<String, dynamic> quote) async {
    try {
      await QuoteService.instance.cancelDelete(_int(quote['id']));
      await _loadSpecialQuotes();
    } catch (error) {
      _message('삭제 취소 실패: $error');
    }
  }

  Future<void> _deleteNow(Map<String, dynamic> quote) async {
    final ok = await _confirm('지금 목록에서 삭제하시겠습니까?');
    if (!ok) return;
    try {
      await QuoteService.instance.deleteNow(_int(quote['id']));
      await _loadSpecialQuotes();
    } catch (error) {
      _message('바로 삭제 실패: $error');
    }
  }

  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('확인'),
            ),
          ],
        ),
      ) ??
      false;

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final allSelected = _boxes.isNotEmpty && _boxes.every((box) => box.selected);
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const _SectionLabel('운송 경로 선택'),
          const SizedBox(height: 8),
          _RouteDropdown(
            value: _selectedRoute,
            items: _transportRoutes,
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  _selectedRoute = v;
                  if (RouteCatalog.keyFor(v) != 'la_kr_air_exp') {
                    _movingCargo = false;
                  }
                  _calculation = null;
                });
              }
            },
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(child: _SectionLabel('박스 정보 입력')),
              if (RouteCatalog.keyFor(_selectedRoute) == 'la_kr_air_exp') ...[
                Checkbox(
                  value: _movingCargo,
                  onChanged: (v) => setState(() {
                    _movingCargo = v ?? false;
                    _calculation = null;
                  }),
                  visualDensity: VisualDensity.compact,
                ),
                const Text('이삿짐', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 4),
              ],
              Checkbox(
                value: allSelected,
                onChanged: (v) => _setAllBoxes(v ?? false),
                visualDensity: VisualDensity.compact,
              ),
              const Text('전체 박스 선택', style: TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          ..._boxes.asMap().entries.map(
                (e) => _BoxRow(
                  index: e.key,
                  entry: e.value,
                  canDelete: _boxes.length > 1,
                  onDelete: () => _removeBox(e.key),
                  onSelected: (v) => setState(() {
                    e.value.selected = v;
                    _calculation = null;
                  }),
                  onChanged: () => setState(() => _calculation = null),
                ),
              ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _addBox,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('박스 추가', style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.navyPrimary,
              side: const BorderSide(color: AppColors.navyPrimary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _calculateFreight,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navyPrimary,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                '운임 확인',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (_calculation != null) ...[
            const SizedBox(height: 10),
            _freightResultCard(_calculation!),
          ],
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => _openSpecialQuoteForm(),
              icon: const Icon(Icons.star_outline, size: 18),
              label: const Text('대량 혹은 특수 견적 요청', style: TextStyle(fontSize: 14)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.tagOrange,
                side: const BorderSide(color: AppColors.tagOrange),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          if (_loadingQuotes) ...[
            const SizedBox(height: 18),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_specialQuotes.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionLabel('견적 요청 내역'),
            const SizedBox(height: 8),
            ..._specialQuotes.map(_specialQuoteCard),
          ],
        ],
      ),
    );
  }

  Widget _freightResultCard(QuoteFreightResult result) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.route,
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navyPrimary),
              ),
              const SizedBox(height: 8),
              ...result.lines.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '박스 ${line.index} · 청구중량 ${line.chargeableWeightKg.toStringAsFixed(2)}kg · 단가 \$${line.ratePerKg.toStringAsFixed(2)}${line.movingCargoSurchargeUsd > 0 ? ' · 이삿짐 통관 +\$${line.movingCargoSurchargeUsd.toStringAsFixed(2)}' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        '\$${line.amountUsd.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '총 운임  USD \$${result.totalUsd.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _specialQuoteCard(Map<String, dynamic> quote) {
    final messages = _messages(quote);
    final adminReplies = messages.where((m) => '${m['sender_role']}' == 'admin').toList();
    final adminViewed = quote['admin_viewed_at'] != null;
    final hasReply = adminReplies.isNotEmpty;
    final deletePending = quote['deletion_requested_at'] != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${quote['subject'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navyPrimary),
                  ),
                ),
                Text(
                  deletePending
                      ? '삭제 대기'
                      : hasReply
                          ? '회신 완료'
                          : adminViewed
                              ? '관리자 확인'
                              : '확인 전',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${quote['route'] ?? ''}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Text('${quote['content'] ?? ''}'),
            if ('${quote['other_contact'] ?? ''}'.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('기타 연락처: ${quote['other_contact']}', style: const TextStyle(fontSize: 12)),
            ],
            if (messages.isNotEmpty) ...[
              const Divider(height: 22),
              ...messages.map(_messageBubble),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (deletePending) ...[
                    OutlinedButton(
                      onPressed: () => _cancelDelete(quote),
                      child: const Text('삭제 취소'),
                    ),
                    ElevatedButton(
                      onPressed: () => _deleteNow(quote),
                      child: const Text('바로 삭제'),
                    ),
                  ] else if (!adminViewed) ...[
                    TextButton(
                      onPressed: () => _openSpecialQuoteForm(existing: quote),
                      child: const Text('수정'),
                    ),
                    TextButton(
                      onPressed: () => _requestDelete(quote),
                      child: const Text('삭제'),
                    ),
                  ] else if (hasReply) ...[
                    OutlinedButton(
                      onPressed: () => _addReply(quote),
                      child: const Text('추가 회신'),
                    ),
                    TextButton(
                      onPressed: () => _requestDelete(quote),
                      child: const Text('삭제'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageBubble(Map<String, dynamic> message) {
    final admin = '${message['sender_role']}' == 'admin';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: admin ? AppColors.inputFill : AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(admin ? '관리자 회신' : '추가 회신',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text('${message['message'] ?? ''}', style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _messages(Map<String, dynamic> quote) {
    final raw = quote['messages'];
    if (raw is! List) return const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static int _int(dynamic value) => int.tryParse('$value') ?? 0;
}

class _RouteDropdown extends StatelessWidget {
  const _RouteDropdown({required this.value, required this.items, required this.onChanged});
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(10),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            icon: const Icon(Icons.expand_more_rounded, color: AppColors.textSecondary),
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
            items: items.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
            onChanged: onChanged,
          ),
        ),
      );
}

class _BoxRow extends StatelessWidget {
  const _BoxRow({
    required this.index,
    required this.entry,
    required this.canDelete,
    required this.onDelete,
    required this.onSelected,
    required this.onChanged,
  });

  final int index;
  final _BoxEntry entry;
  final bool canDelete;
  final VoidCallback onDelete;
  final ValueChanged<bool> onSelected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: entry.selected,
                  onChanged: (v) => onSelected(v ?? false),
                  visualDensity: VisualDensity.compact,
                ),
                Text(
                  '박스 ${index + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navyPrimary,
                  ),
                ),
                const Spacer(),
                if (canDelete)
                  InkWell(
                    onTap: onDelete,
                    child: const Icon(Icons.remove_circle_outline, size: 18, color: AppColors.error),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _CompactField(
                    label: '무게(kg)',
                    initial: entry.weight,
                    onChanged: (v) {
                      entry.weight = v;
                      onChanged();
                    },
                    width: 72,
                    inputType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(width: 6),
                  _CompactField(
                    label: '가로(cm)',
                    initial: entry.width,
                    onChanged: (v) {
                      entry.width = v;
                      onChanged();
                    },
                    width: 72,
                    inputType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(width: 6),
                  _CompactField(
                    label: '세로(cm)',
                    initial: entry.length,
                    onChanged: (v) {
                      entry.length = v;
                      onChanged();
                    },
                    width: 72,
                    inputType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(width: 6),
                  _CompactField(
                    label: '높이(cm)',
                    initial: entry.height,
                    onChanged: (v) {
                      entry.height = v;
                      onChanged();
                    },
                    width: 72,
                    inputType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(width: 6),
                  _CompactField(
                    label: '수량',
                    initial: entry.quantity,
                    onChanged: (v) {
                      entry.quantity = v;
                      onChanged();
                    },
                    width: 60,
                    inputType: TextInputType.number,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _CompactField extends StatelessWidget {
  const _CompactField({
    required this.label,
    required this.initial,
    required this.onChanged,
    required this.width,
    required this.inputType,
  });

  final String label;
  final String initial;
  final ValueChanged<String> onChanged;
  final double width;
  final TextInputType inputType;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
            const SizedBox(height: 3),
            TextFormField(
              initialValue: initial,
              keyboardType: inputType,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
              onChanged: onChanged,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.inputFill,
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(6),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              ),
            ),
          ],
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      );
}

class QuoteRequestScreen extends StatelessWidget {
  const QuoteRequestScreen({
    super.key,
    this.language = AppLanguage.korean,
    this.onRequestLogin,
  });
  final AppLanguage language;
  final VoidCallback? onRequestLogin;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.navyPrimary,
          foregroundColor: AppColors.white,
          title: const Text(
            '운임 확인 및 견적 요청',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          elevation: 0,
        ),
        body: QuoteRequestBody(language: language, onRequestLogin: onRequestLogin),
      );
}
