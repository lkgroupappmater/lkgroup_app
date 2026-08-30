import 'package:flutter/material.dart';

import '../core/route_catalog.dart';
import '../services/customer_benefit_service.dart';

class DiscountManagementScreen extends StatefulWidget {
  const DiscountManagementScreen({super.key});

  @override
  State<DiscountManagementScreen> createState() =>
      _DiscountManagementScreenState();
}

class _DiscountManagementScreenState
    extends State<DiscountManagementScreen> {
  List<DiscountRule> _rules = const [];
  String _route = 'all';
  String _query = '';
  bool _loading = true;

  List<DiscountRule> get _visible => _rules.where((r) {
        if (_route != 'all' && r.routeKey != _route) return false;
        if (_query.trim().isEmpty) return true;
        final q = _query.trim().toLowerCase();
        return <String>[
          r.customerName,
          r.companyName,
          r.phone,
          r.groupName,
        ].any((v) => v.toLowerCase().contains(q));
      }).toList(growable: false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rules =
          await CustomerBenefitService.instance.listDiscountRules();
      if (mounted) setState(() => _rules = rules);
    } catch (e) {
      if (mounted) _msg('할인 목록 조회 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _msg(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  String _routeLabel(String key) =>
      key == 'all' ? '전체 운송 경로' : RouteCatalog.labelForKey(key);

  Future<void> _edit([DiscountRule? rule]) async {
    final name =
        TextEditingController(text: rule?.customerName ?? '');
    final company =
        TextEditingController(text: rule?.companyName ?? '');
    final phone =
        TextEditingController(text: rule?.phone ?? '');
    final group =
        TextEditingController(text: rule?.groupName ?? '');
    final discount = TextEditingController(
      text: rule == null
          ? ''
          : (rule.discountPercent * 100).toStringAsFixed(
              rule.discountPercent * 100 % 1 == 0 ? 0 : 2,
            ),
    );
    final bulkThreshold = TextEditingController(
      text: rule?.bulkThreshold?.toString() ?? '',
    );
    final bulkDiscount = TextEditingController(
      text: rule?.bulkDiscountPercent == null
          ? ''
          : (rule!.bulkDiscountPercent! * 100).toStringAsFixed(
              rule.bulkDiscountPercent! * 100 % 1 == 0 ? 0 : 2,
            ),
    );
    final rate = TextEditingController(
      text: rule?.rateOverride?.toString() ?? '',
    );
    final notes =
        TextEditingController(text: rule?.notes ?? '');

    var routeKey = rule?.routeKey ??
        (_route == 'all'
            ? RouteCatalog.keyFor(RouteCatalog.routes.first)
            : _route);
    var active = rule?.active ?? true;
    var statementMode = rule?.statementMode ?? 'separate';

    final saved = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
              title: Text(
                rule == null ? '할인 고객 추가' : '할인 고객 편집',
              ),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: routeKey,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: '운송 경로'),
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('전체 운송 경로'),
                          ),
                          ...RouteCatalog.routes.map(
                            (e) => DropdownMenuItem(
                              value: RouteCatalog.keyFor(e),
                              child: Text(e),
                            ),
                          ),
                        ],
                        onChanged: (v) => setLocal(
                          () => routeKey = v ?? routeKey,
                        ),
                      ),
                      TextField(
                        controller: group,
                        decoration:
                            const InputDecoration(labelText: '소속/단체명'),
                      ),
                      TextField(
                        controller: name,
                        decoration:
                            const InputDecoration(labelText: '고객 개인 이름'),
                      ),
                      TextField(
                        controller: company,
                        decoration: const InputDecoration(
                          labelText: '회사명 (회원가입 회사명과 자동 묶음)',
                        ),
                      ),
                      TextField(
                        controller: phone,
                        keyboardType: TextInputType.phone,
                        decoration:
                            const InputDecoration(labelText: '전화번호'),
                      ),
                      const SizedBox(height: 10),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '할인율',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextField(
                        controller: discount,
                        keyboardType:
                            const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '기본/소량 할인율 (%)',
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: bulkThreshold,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '대량 기준 수량 (선택)',
                                hintText: '예: 50',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: bulkDiscount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: '대량 할인율 (%)',
                                hintText: '예: 10',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '대량 기준은 개인 이름 + 회사명으로 입고된 수량을 같은 항차에서 합산하여 판단합니다.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ),
                      TextField(
                        controller: rate,
                        keyboardType:
                            const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '고정 단가 Override (선택)',
                        ),
                      ),
                      TextField(
                        controller: notes,
                        maxLines: 2,
                        decoration:
                            const InputDecoration(labelText: '비고'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: statementMode,
                        decoration: const InputDecoration(
                          labelText: '개인/회사 명세서 방식',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'separate',
                            child: Text(
                              '분리 - 개인 이름 / 회사명 명세서 각각',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'combined',
                            child: Text(
                              '통합 - 개인 이름 + 회사명 한 명세서',
                            ),
                          ),
                        ],
                        onChanged: (v) => setLocal(
                          () => statementMode = v ?? 'separate',
                        ),
                      ),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '※ 명세서 분리 여부와 관계없이 할인 대량 기준 수량은 개인+회사 물량을 합산합니다.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('할인 적용'),
                        subtitle: Text(
                          phone.text.trim().isEmpty
                              ? '전화번호가 없으면 자동 적용되지 않습니다.'
                              : '개인 이름/회사명 + 전화번호 + 운송경로가 일치할 때 적용',
                        ),
                        value: active,
                        onChanged: (v) =>
                            setLocal(() => active = v),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('저장'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (!saved) return;

    final pct =
        double.tryParse(discount.text.replaceAll('%', '').trim());
    final thresholdText = bulkThreshold.text.trim();
    final bulkPctText =
        bulkDiscount.text.replaceAll('%', '').trim();
    final threshold = thresholdText.isEmpty
        ? null
        : int.tryParse(thresholdText);
    final bulkPct = bulkPctText.isEmpty
        ? null
        : double.tryParse(bulkPctText);

    if (name.text.trim().isEmpty ||
        pct == null ||
        pct < 0 ||
        pct > 100) {
      _msg('고객 이름과 0~100 사이 기본 할인율을 확인해 주세요.');
      return;
    }
    if ((threshold == null) != (bulkPct == null) ||
        (threshold != null && threshold <= 0) ||
        (bulkPct != null && (bulkPct < 0 || bulkPct > 100))) {
      _msg('대량 할인은 기준 수량과 할인율을 모두 입력해 주세요.');
      return;
    }

    try {
      await CustomerBenefitService.instance.saveDiscountRule(
        DiscountRule(
          id: rule?.id,
          customerName: name.text.trim(),
          companyName: company.text.trim(),
          phone: phone.text.trim(),
          routeKey: routeKey,
          groupName: group.text.trim(),
          discountPercent: pct / 100,
          rateOverride: double.tryParse(rate.text.trim()),
          notes: notes.text.trim(),
          sourceDetail: rule?.sourceDetail ?? '',
          active: active,
          customerGroupId: rule?.customerGroupId,
          bulkThreshold: threshold,
          bulkDiscountPercent:
              bulkPct == null ? null : bulkPct / 100,
          statementMode: statementMode,
        ),
      );
      _msg('고객 묶음/할인 적용 정보를 저장했습니다.');
      await _load();
    } catch (e) {
      _msg('할인 정보 저장 실패: $e');
    }
  }

  Future<void> _delete(DiscountRule rule) async {
    if (rule.id == null) return;
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('할인 고객 삭제'),
            content: Text(
              '${rule.customerName} 할인 적용 정보를 삭제하시겠습니까?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await CustomerBenefitService.instance
          .deleteDiscountRule(rule.id!);
      _msg('삭제했습니다.');
      await _load();
    } catch (e) {
      _msg('삭제 실패: $e');
    }
  }

  String _discountLabel(DiscountRule r) {
    final base =
        '${(r.discountPercent * 100).toStringAsFixed(0)}%';
    if (!r.hasBulkTier) return base;
    return '$base → ${r.bulkThreshold}+ '
        '${(r.bulkDiscountPercent! * 100).toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('할인 적용 관리')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add),
          label: const Text('할인 고객 추가'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _route,
                          decoration: const InputDecoration(
                            labelText: '운송 경로',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: 'all',
                              child: Text('전체'),
                            ),
                            ...RouteCatalog.routes.map(
                              (e) => DropdownMenuItem(
                                value: RouteCatalog.keyFor(e),
                                child: Text(e),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(
                            () => _route = v ?? 'all',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText:
                                '이름 / 회사명 / 전화번호 / 단체 검색',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) =>
                              setState(() => _query = v),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _visible.isEmpty
                        ? const Center(
                            child: Text('등록된 할인 고객이 없습니다.'),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                              10,
                              0,
                              10,
                              90,
                            ),
                            itemCount: _visible.length,
                            itemBuilder: (_, i) {
                              final r = _visible[i];
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    child: Text(
                                      '${(r.discountPercent * 100).toStringAsFixed(0)}%',
                                    ),
                                  ),
                                  title: Text(
                                    '${r.customerName}'
                                    '${r.companyName.isEmpty ? '' : ' / ${r.companyName}'}',
                                  ),
                                  subtitle: Text(
                                    '${_routeLabel(r.routeKey)} · '
                                    '${r.groupName.isEmpty ? '소속 미지정' : r.groupName}\n'
                                    '${r.phone.isEmpty ? '전화번호 입력 필요 · 적용 대기' : r.phone}'
                                    '${r.sourceDetail.isEmpty ? '' : ' · ${r.sourceDetail}'}\n'
                                    '할인: ${_discountLabel(r)} · '
                                    '명세서: ${r.statementMode == 'combined' ? '개인+회사 통합' : '개인/회사 분리'}',
                                  ),
                                  isThreeLine: true,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        r.active
                                            ? Icons.check_circle
                                            : Icons
                                                .pause_circle_outline,
                                        color: r.active
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                      IconButton(
                                        onPressed: () => _edit(r),
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => _delete(r),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      );
}
