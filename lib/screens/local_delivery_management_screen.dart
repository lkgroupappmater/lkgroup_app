import '../core/app_language.dart';
import '../services/shared_ui_text_service.dart';
import 'package:flutter/material.dart';

import '../core/route_catalog.dart';
import '../services/customer_benefit_service.dart';
import '../widgets/management_field_search.dart';
import '../widgets/auto_refresh_state.dart';
import '../services/customer_identity_service.dart';

class LocalDeliveryManagementScreen extends StatefulWidget {
  const LocalDeliveryManagementScreen({super.key, this.language = AppLanguage.korean});
  final AppLanguage language;

  @override
  State<LocalDeliveryManagementScreen> createState() => _LocalDeliveryManagementScreenState();
}

class _LocalDeliveryManagementScreenState extends State<LocalDeliveryManagementScreen> with SharedUiTextState, AutoRefreshState {
  @override
  Set<String> get autoRefreshTopics => {'customers', 'local_delivery_profiles'};
  @override
  Future<void> refreshAutomatically() => _load(silent: true);
  final _fieldFilter = ManagementFieldFilter();
  Map<int, String> _customerCodes = {};
  String _typeFilter = '', _companyFilter = '';
  List<String> get _companies => _rules.map((r) => r.localCompany).where((v) => v.isNotEmpty).toSet().toList()..sort();
  List<LocalDeliveryRule> _rules = const [];
  String _route = 'kr_la_sea';
  bool _loading = true;

  List<LocalDeliveryRule> get _visible => _rules.where((r) =>
    (_route.isEmpty || r.routeKey == _route) && (_typeFilter.isEmpty || r.deliveryType == _typeFilter) && (_companyFilter.isEmpty || r.localCompany == _companyFilter) &&
    _fieldFilter.matches({'customer_name': '${r.customerName} / ${r.alternateName}', 'customer_code': _customerCodes[r.id], 'phone': r.phoneDisplay.isEmpty ? r.phone : r.phoneDisplay, 'route': RouteCatalog.labelForKey(r.routeKey), 'local_company': r.localCompany, 'delivery_type': '${r.deliveryType} ${r.typeLabel}', 'address': r.destinationAddress, 'paid_by': r.paidBy, 'notes': r.notes})).toList(growable: false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final rows = await CustomerBenefitService.instance.listLocalDeliveryRules();
      final codes = await CustomerIdentityService.deliveryCodes(rows.where((r) => r.id != null).map((r) => r.id!).toList());
      if (mounted && (!silent || canApplyAutoRefresh)) setState(() { _rules = rows; _customerCodes = codes; if (!_rules.any((r) => r.localCompany == _companyFilter)) _companyFilter = ''; });
    } catch (e) {
      if (mounted) _msg('시내·지방 배송 목록 조회 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _msg(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  Future<void> _edit([LocalDeliveryRule? rule]) async {
    final sourceNo = TextEditingController(text: (rule?.originalSourceNo ?? rule?.sourceNo)?.toString() ?? '');
    final name = TextEditingController(text: rule?.customerName ?? '');
    final alt = TextEditingController(text: rule?.alternateName ?? '');
    final company = TextEditingController(text: rule?.companyName ?? '');
    final phone = TextEditingController(text: rule?.phoneDisplay.isNotEmpty == true ? rule!.phoneDisplay : (rule?.phone ?? ''));
    final localCompany = TextEditingController(text: rule?.localCompany ?? '');
    final destination = TextEditingController(text: rule?.destinationAddress ?? '');
    final paidBy = TextEditingController(text: rule?.paidBy ?? '');
    final notes = TextEditingController(text: rule?.notes ?? '');
    var routeKey = rule?.routeKey ?? _route;
    var type = rule?.deliveryType ?? 'province';
    var active = rule?.active ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(rule == null ? '시내·지방 배송 고객 추가' : '시내·지방 배송 고객 편집'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: routeKey,
                    decoration: const InputDecoration(labelText: '운송 경로'),
                    items: CustomerBenefitService.localDeliveryRouteKeys
                        .map((e) => DropdownMenuItem(value: e, child: Text(RouteCatalog.labelForKey(e))))
                        .toList(),
                    onChanged: (v) => setLocal(() => routeKey = v ?? routeKey),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: '배송 종류'),
                    items: const [
                      DropdownMenuItem(value: 'province', child: Text('지방배송 (원본 흰색)')),
                      DropdownMenuItem(value: 'city', child: Text('시내 배송 (원본 녹색)')),
                    ],
                    onChanged: (v) => setLocal(() => type = v ?? type),
                  ),
                  TextField(controller: sourceNo, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'No.')),
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                  TextField(controller: alt, decoration: const InputDecoration(labelText: 'Name(2)')),
                  TextField(controller: company, decoration: const InputDecoration(labelText: '회사명 매칭용 (선택)')),
                  TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Tel')),
                  TextField(controller: localCompany, decoration: const InputDecoration(labelText: 'Local Company')),
                  TextField(controller: destination, maxLines: 3, decoration: const InputDecoration(labelText: 'Destination Address')),
                  TextField(controller: paidBy, decoration: const InputDecoration(labelText: 'Paid by')),
                  TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: '비고')),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('적용'), value: active, onChanged: (v) => setLocal(() => active = v)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
          ],
        ),
      ),
    ) ?? false;
    if (!saved) return;
    if (name.text.trim().isEmpty && company.text.trim().isEmpty) {
      _msg('고객 이름 또는 회사명을 입력해 주세요.');
      return;
    }
    try {
      await CustomerBenefitService.instance.saveLocalDeliveryRule(
        LocalDeliveryRule(
          id: rule?.id,
          routeKey: routeKey,
          sourceNo: rule?.originalSourceNo != null ? rule?.sourceNo : int.tryParse(sourceNo.text.trim()),
          originalSourceNo: rule?.originalSourceNo != null ? int.tryParse(sourceNo.text.trim()) : null,
          customerName: name.text.trim(),
          alternateName: alt.text.trim(),
          companyName: company.text.trim(),
          phone: phone.text.trim(),
          phoneDisplay: phone.text.trim(),
          deliveryType: type,
          localCompany: localCompany.text.trim(),
          destinationAddress: destination.text.trim(),
          paidBy: paidBy.text.trim(),
          notes: notes.text.trim(),
          active: active,
          preferred: rule?.preferred ?? false,
        ),
      );
      _msg('배송 정보를 저장했습니다.');
      await _load();
    } catch (e) {
      _msg('배송 정보 저장 실패: $e');
    }
  }

  Future<void> _delete(LocalDeliveryRule rule) async {
    if (rule.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('배송 고객 삭제'),
        content: Text('${rule.customerName} 배송 정보를 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
        ],
      ),
    ) ?? false;
    if (!ok) return;
    try {
      await CustomerBenefitService.instance.deleteLocalDeliveryRule(rule.id!);
      _msg('삭제했습니다.');
      await _load();
    } catch (e) {
      _msg('삭제 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(actions: [IconButton(onPressed: _loading ? null : () => _load(), icon: const Icon(Icons.refresh))], title: Text(SharedUiTextService.instance.text('localDeliveries', widget.language.code, '시내.지방 배송 list 관리'))),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('배송 고객 추가'),
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
                          decoration: const InputDecoration(labelText: '운송 경로', border: OutlineInputBorder()),
                          items: ['', ...CustomerBenefitService.localDeliveryRouteKeys]
                              .map((e) => DropdownMenuItem(value: e, child: Text(e.isEmpty ? '전체 경로' : RouteCatalog.labelForKey(e))))
                              .toList(),
                          onChanged: (v) => setState(() => _route = v ?? _route),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: DropdownButtonFormField<String>(initialValue: _typeFilter, decoration: const InputDecoration(labelText: 'Type'), items: const [DropdownMenuItem(value: '', child: Text('전체 유형')), DropdownMenuItem(value: 'city', child: Text('시내 배송')), DropdownMenuItem(value: 'province', child: Text('지방배송'))], onChanged: (v) => setState(() => _typeFilter = v ?? ''))),
                          const SizedBox(width: 8),
                          Expanded(child: DropdownButtonFormField<String>(key: ValueKey(_companyFilter), initialValue: _companyFilter, isExpanded: true, decoration: const InputDecoration(labelText: '현지 업체'), items: ['', ..._companies].map((v) => DropdownMenuItem(value: v, child: Text(v.isEmpty ? '전체 업체' : v, overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setState(() => _companyFilter = v ?? ''))),
                        ]),
                        ManagementFieldSearch(filter: _fieldFilter, fields: const {'customer_name':'고객명', 'customer_code':'고객 ID', 'phone':'연락처', 'route':'운송 경로', 'local_company':'현지 업체', 'delivery_type':'Type', 'address':'배송 주소', 'paid_by':'결제 구분', 'notes':'비고'}, onChanged: () => setState(() {})),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _visible.isEmpty
                        ? const Center(child: Text('등록된 배송 고객이 없습니다.'))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 90),
                            itemCount: _visible.length,
                            itemBuilder: (_, i) {
                              final r = _visible[i];
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: r.isCity ? Colors.green.shade100 : Colors.grey.shade200,
                                    child: Icon(r.isCity ? Icons.location_city : Icons.local_shipping_outlined, color: r.isCity ? Colors.green.shade800 : Colors.grey.shade800),
                                  ),
                                  title: Text('${_customerCodes[r.id] == null ? '' : 'ID ${_customerCodes[r.id]} · '}${r.sourceNo == null ? '' : '(${r.originalSourceNo ?? r.sourceNo}) '}${r.customerName}${r.alternateName.isEmpty ? '' : ' / ${r.alternateName}'}'),
                                  subtitle: Text('${r.typeLabel} · ${r.phoneDisplay.isEmpty ? r.phone : r.phoneDisplay}\n${r.localCompany}${r.destinationAddress.isEmpty ? '' : ' · ${r.destinationAddress}'}'),
                                  isThreeLine: true,
                                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                    IconButton(onPressed: () => _edit(r), icon: const Icon(Icons.edit_outlined)),
                                    IconButton(onPressed: () => _delete(r), icon: const Icon(Icons.delete_outline)),
                                  ]),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      );
}


