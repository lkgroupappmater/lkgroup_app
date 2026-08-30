import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../core/route_catalog.dart';
import '../core/money_format.dart';
import '../models/app_user.dart';
import '../services/freight_service.dart';
import '../services/shipment_service.dart';
import '../services/shipment_filter_options_service.dart';
import '../services/unknown_recipient_service.dart';

class ShipmentSearchBody extends StatefulWidget {
  const ShipmentSearchBody({
    super.key,
    this.language = AppLanguage.korean,
    this.isLoggedIn = false,
    this.currentUser,
    this.onRequireLogin,
    this.onEditRequest,
    this.onManageSelected,
  });

  final AppLanguage language;
  final bool isLoggedIn;
  final AppUser? currentUser;
  final VoidCallback? onRequireLogin;
  final VoidCallback? onEditRequest;
  final ValueChanged<List<String>>? onManageSelected;

  @override
  State<ShipmentSearchBody> createState() => _ShipmentSearchBodyState();
}

class _ShipmentSearchBodyState extends State<ShipmentSearchBody> {
  int _selectedRoute = -1;
  String _year = '전체';
  String _voyage = '전체';
  final _invoiceCtrl = TextEditingController();
  final _recipientCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _unknownRecipientRows = const [];
  List<ShipmentBatchOption> _filterBatches = const [];
  bool _loadingUnknownRecipients = false;
  bool _searched = false;
  final Set<String> _selectedIds = <String>{};

  bool get _canSeeAll => widget.currentUser?.role.canSeeAllShipments == true;
  bool get _showZone => widget.currentUser?.role == UserRole.admin || widget.currentUser?.role == UserRole.staff;
  String get _selectedRouteLabel => _selectedRoute < 0 ? '전체' : routeLabels[_selectedRoute];
  List<String> get _availableYears {
    final route = _selectedRouteLabel;
    final years =
        ShipmentFilterOptionsService.instance.yearsFor(_filterBatches, route);
    return <String>['전체', ...years.map((e) => '$e년')];
  }

  List<String> get _availableVoyages {
    final route = _selectedRouteLabel;
    final year =
        int.tryParse(_year.replaceAll(RegExp(r'[^0-9]'), ''));
    if (year == null) return const <String>['전체'];
    final voyages = ShipmentFilterOptionsService.instance
        .voyagesFor(_filterBatches, route, year);
    return <String>[
      '전체',
      ...voyages.map(
        (e) => e.endsWith('항차') ? e : '${e}항차',
      ),
    ];
  }

  Future<void> _loadFilterBatches() async {
    if (!widget.isLoggedIn || widget.currentUser == null) return;
    try {
      final rows = await ShipmentFilterOptionsService.instance.listBatches();
      if (!mounted) return;
      setState(() {
        _filterBatches = rows;
        if (!_availableYears.contains(_year)) _year = '전체';
        if (!_availableVoyages.contains(_voyage)) _voyage = '전체';
      });
    } catch (_) {
      // 조회 필터 목록 실패가 기존 화물 조회 자체를 막지 않도록 합니다.
    }
  }

  @override
  void initState() {
    super.initState();
    _prefillMemberFields();
    _loadUnknownRecipientCargo();
    _loadFilterBatches();
  }

  @override
  void didUpdateWidget(covariant ShipmentSearchBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser?.id != widget.currentUser?.id) {
      _prefillMemberFields();
    _loadUnknownRecipientCargo();
      _loadFilterBatches();
    }
  }

  void _prefillMemberFields() {
    final user = widget.currentUser;
    if (user == null || user.role != UserRole.member) return;
    _recipientCtrl.text = user.name;
    _phoneCtrl.text = user.phone;
  }

  @override
  void dispose() {
    _invoiceCtrl.dispose();
    _recipientCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUnknownRecipientCargo() async {
    final user = widget.currentUser;
    if (!widget.isLoggedIn || user == null) {
      if (mounted) {
        setState(() => _unknownRecipientRows = const []);
      }
      return;
    }

    if (mounted) setState(() => _loadingUnknownRecipients = true);
    try {
      final rows =
          await UnknownRecipientService.instance.listVisibleUnknownCargo();
      if (!mounted) return;
      setState(() => _unknownRecipientRows = rows);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('수취인 불명 화물 조회 실패: $error')),
      );
    } finally {
      if (mounted) setState(() => _loadingUnknownRecipients = false);
    }
  }

  void _showUnknownCargoGuide() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '수취인 불명 화물 보관·처분 상세 안내',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: const Text(
          '• 물품 도착 및 출고 후 특별한 사유 없이 장기 미수취 물품의 경우 '
          '보관료등 기타 추가 비용이 발생 할 수 있습니다.\n\n'
          '• 물품 출고 후 1주 후부터 보관료(최소 3불/CBM/day)가 발생하며, '
          '특별한 사유 없이 2달 이상 보관 물품들은 임의로 폐기/처분 될 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
  Future<void> _claimUnknownCargo(Map<String, dynamic> row) async {
    final user = widget.currentUser;
    if (user == null || user.role != UserRole.member) return;

    final name = TextEditingController(text: user.name);
    final phone = TextEditingController(text: user.phone);
    final note = TextEditingController();

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('본인 화물 확인 및 정정 요청'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['route'] ?? ''} · ${row['shipment_year'] ?? ''}년 · '
                    '${_voyageLabel(row['voyage'])}\n'
                    '박스번호 ${row['box_number'] ?? ''}\n'
                    '송장번호 ${row['invoice_number'] ?? ''}',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: '본인 이름',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: '본인 연락처',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: note,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '확인 참고 내용 (선택)',
                      hintText: '물품 내용, 발송인 등 관리자 확인에 도움이 되는 내용을 입력해 주세요.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '요청 승인 후 이름은 "수취인 불명 / 고객 이름" 형태로 기록되며, '
                    '영수번호는 해당 항차의 마지막 영수번호 다음 번호로 자동 부여됩니다.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
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
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('본인 화물 확인 및 정정 요청'),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmed) {
      try {
        await UnknownRecipientService.instance.createClaim(
          shipmentId: '${row['id']}',
          claimantName: name.text,
          claimantPhone: phone.text,
          note: note.text,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('관리자에게 본인 화물 확인 및 정정 요청을 보냈습니다.'),
          ),
        );
        await _loadUnknownRecipientCargo();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('본인 화물 확인 요청 실패: $error')),
        );
      }
    }

    name.dispose();
    phone.dispose();
    note.dispose();
  }

  Widget _unknownRecipientSection() {
    if (!widget.isLoggedIn || widget.currentUser == null) {
      return const SizedBox.shrink();
    }
    final canClaim = widget.currentUser?.role == UserRole.member;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.help_outline, color: AppColors.navyPrimary),
            const SizedBox(width: 7),
            const Expanded(
              child: Text(
                '수취인 불명 / 데이터 불문명 화물',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navyPrimary,
                ),
              ),
            ),
            TextButton(
              onPressed: _showUnknownCargoGuide,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: const Text(
                '상세 안내',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '수취인을 특정할 수 없는 화물은 로그인한 가입자에게 제한된 정보로 표시됩니다. '
          '일반 회원은 본인 화물이 확인되면 해당 카드를 눌러 정정 요청할 수 있습니다.',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        if (_loadingUnknownRecipients)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_unknownRecipientRows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '현재 확인이 필요한 수취인 불명 화물이 없습니다.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          ..._unknownRecipientRows.map((row) {
            final pending = row['claim_pending'] == true;
            final createdAt =
                DateTime.tryParse('${row['created_at'] ?? ''}')?.toLocal();
            final ageDays = createdAt == null
                ? 0
                : DateTime.now().difference(createdAt).inDays;
            final Color? warningBorder = ageDays >= 30
                ? Colors.red
                : ageDays >= 14
                    ? Colors.orange
                    : null;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: warningBorder == null
                  ? null
                  : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: warningBorder,
                        width: 2.2,
                      ),
                    ),
              child: InkWell(
                onTap: canClaim && !pending
                    ? () => _claimUnknownCargo(row)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '박스번호 ${row['box_number'] ?? ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.navyPrimary,
                              ),
                            ),
                          ),
                          if (pending)
                            const Text(
                              '확인 요청 대기',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _row('운송 경로', '${row['route'] ?? ''}'),
                      _row('년도', '${row['shipment_year'] ?? ''}'),
                      _row('항차', _voyageLabel(row['voyage'])),
                      _row('송장번호', '${row['invoice_number'] ?? ''}'),
                      _row(
                        '수취인',
                        '${row['consignee_name'] ?? '수취인 불명'}',
                      ),
                      _row(
                        '연락처',
                        '${row['consignee_phone'] ?? ''}',
                      ),
                      if (canClaim && !pending) ...[
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '카드를 눌러 본인 화물 확인 요청',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.accent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
  Future<void> _search() async {
    try {
      final dbRows = await ShipmentService.instance.searchRows(
        route: _selectedRouteLabel,
        invoice: _invoiceCtrl.text.trim(),
        recipient: _recipientCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        year: _year,
        voyage: _voyage,
        currentUser: widget.currentUser,
      );
      if (!mounted) return;
      setState(() {
        _results = dbRows;
        _searched = true;
        _selectedIds.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searched = true;
        _selectedIds.clear();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('화물 조회 실패: $error')));
    }
  }

  void _toggle(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  void _toggleAll() {
    setState(() {
      final ids = _results.map((r) => '${r['id']}').toSet();
      if (ids.isNotEmpty && _selectedIds.containsAll(ids)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  Future<void> _showFreight() async {
    final selected =
        _results.where((r) => _selectedIds.contains('${r['id']}')).toList();
    if (selected.isEmpty) return;

    try {
      final result = await FreightService.instance.calculate(selected);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text('운임 확인',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ...result.lines.map((line) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          '박스번호 ${line.boxNumber} · 송장번호 ${line.invoiceNumber}'),
                      subtitle: Text(
                          '청구중량 ${line.chargeableWeight.toStringAsFixed(2)}kg · 단가 \$${line.rate.toStringAsFixed(2)}/kg'),
                      trailing: Text('\$${line.amountUsd.toStringAsFixed(2)}'),
                    )),
                const Divider(),
                Text('USD  \$${result.totalUsd.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('KIP  ${result.totalKip.toStringAsFixed(0)}'),
                Text('THB  ${result.totalThb.toStringAsFixed(1)}'),
                Text('KRW  ${result.totalKrw.toStringAsFixed(0)}'),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('운임 계산 실패: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoggedIn) {
      return _LoginRequiredView(onLogin: widget.onRequireLogin);
    }

    final allSelected = _results.isNotEmpty &&
        _selectedIds.containsAll(_results.map((r) => '${r['id']}'));

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        children: [
          DropdownButtonFormField<int>(
            value: _selectedRoute,
            isExpanded: true,
            decoration: _dropDecoration('운송 경로', Icons.route_outlined),
            items: <DropdownMenuItem<int>>[
              const DropdownMenuItem(value: -1, child: Text('전체')),
              ...List.generate(
                routeLabels.length,
                (index) => DropdownMenuItem(
                  value: index,
                  child: Text(routeLabels[index]),
                ),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedRoute = value;
                  _year = '전체';
                  _voyage = '전체';
                });
              }
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _year,
                  decoration: _dropDecoration('년도', Icons.calendar_today),
                  items: _availableYears
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _year = v;
                        _voyage = '전체';
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _voyage,
                  decoration: _dropDecoration(
                      '항차', Icons.confirmation_number_outlined),
                  items: _availableVoyages
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _voyage = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _input(_invoiceCtrl, '송장번호', Icons.tag_rounded),
          const SizedBox(height: 10),
          _input(_recipientCtrl, '이름/라오스 수령인', Icons.person_outline),
          const SizedBox(height: 10),
          _input(_phoneCtrl, '연락처', Icons.phone_outlined,
              type: TextInputType.phone),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _search,
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('화물 검색'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navyPrimary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _selectedIds.isEmpty ? null : _showFreight,
                    icon: const Icon(Icons.price_check_outlined),
                    label: const Text('운임 확인'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_searched && _results.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(
                  value: allSelected,
                  onChanged: (_) => _toggleAll(),
                  activeColor: AppColors.primary,
                ),
                const Text('전체 선택'),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _selectedIds.isEmpty || widget.onManageSelected == null
                      ? null
                      : () => widget.onManageSelected!(_selectedIds.toList()),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('화물 관리'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          if (_searched && _results.isEmpty)
            const Center(child: Text('검색 결과가 없습니다.')),
          ..._groupedResultWidgets(),
          if (!_canSeeAll && _searched)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '일반 회원은 송장번호 뒤 4자리 이상, 정확한 이름 또는 연락처 뒤 8자리 기준으로 조회됩니다.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ),          _unknownRecipientSection(),
        ],
      ),
    );
  }

  String _groupKey(Map<String, dynamic> r) =>
      '${r['route'] ?? ''}|${r['shipment_year'] ?? ''}|${r['voyage'] ?? ''}';

  List<MapEntry<String, List<Map<String, dynamic>>>> _resultGroups() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final row in _results) {
      map.putIfAbsent(_groupKey(row), () => <Map<String, dynamic>>[]).add(row);
    }
    return map.entries.toList();
  }

  void _toggleGroup(List<Map<String, dynamic>> rows) {
    final ids = rows.map((r) => '${r['id']}').toSet();
    setState(() {
      if (ids.isNotEmpty && _selectedIds.containsAll(ids)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  bool _isOwnShipment(Map<String, dynamic> r) {
    final user = widget.currentUser;
    if (user == null) return false;
    if ('${r['customer_id'] ?? ''}' == user.id) return true;
    final n1 = '${r['consignee_name'] ?? ''}'.trim().toLowerCase();
    final n2 = user.name.trim().toLowerCase();
    if (n1.isNotEmpty && n2.isNotEmpty && n1 == n2) return true;
    String digits(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');
    final p1 = digits('${r['consignee_phone'] ?? ''}');
    final p2 = digits(user.phone);
    return p1.length >= 8 && p2.length >= 8 &&
        p1.substring(p1.length - 8) == p2.substring(p2.length - 8);
  }

  Future<void> _showGroupFreight(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    try {
      final result = await FreightService.instance.calculate(rows);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  '${rows.first['route']} · ${rows.first['shipment_year']}년 · ${_voyageLabel(rows.first['voyage'])}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text('그룹 전체 운임'),
                const Divider(),
                ...result.lines.map((line) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('박스번호 ${line.boxNumber} · 송장번호 ${line.invoiceNumber}'),
                      subtitle: Text(
                        '청구중량 ${line.chargeableWeight.toStringAsFixed(2)}kg · 단가 \$${line.rate.toStringAsFixed(2)}/kg',
                      ),
                      trailing: Text('\$${line.amountUsd.toStringAsFixed(2)}'),
                    )),
                const Divider(),
                Text('USD  \$${result.totalUsd.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('KIP  ${result.totalKip.toStringAsFixed(0)}'),
                Text('THB  ${result.totalThb.toStringAsFixed(1)}'),
                Text('KRW  ${result.totalKrw.toStringAsFixed(0)}'),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('그룹 운임 계산 실패: $error')));
      }
    }
  }

  List<Widget> _groupedResultWidgets() {
    return _resultGroups().map((entry) {
      final rows = entry.value;
      final first = rows.first;
      final ids = rows.map((r) => '${r['id']}').toSet();
      final all = ids.isNotEmpty && _selectedIds.containsAll(ids);
      return Card(
        margin: const EdgeInsets.only(bottom: 14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              color: AppColors.inputFill,
              child: Row(
                children: [
                  Checkbox(
                    value: all,
                    onChanged: (_) => _toggleGroup(rows),
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      '${first['route']} · ${first['shipment_year']}년도 · ${_voyageLabel(first['voyage'])}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.navyPrimary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showGroupFreight(rows),
                    icon: const Icon(Icons.price_check_outlined, size: 17),
                    label: const Text('운임'),
                  ),
                ],
              ),
            ),
            ...rows.map(_shipmentCard),
          ],
        ),
      );
    }).toList();
  }
  Widget _shipmentCard(Map<String, dynamic> r) {
    final id = '${r['id']}';
    final size =
        '${r['length_cm'] ?? ''} × ${r['width_cm'] ?? ''} × ${r['height_cm'] ?? ''} cm';
    return Card(
      child: InkWell(
        onTap: () => _toggle(id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _selectedIds.contains(id),
              onChanged: (_) => _toggle(id),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('박스번호 ${r['box_number'] ?? ''}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.navyPrimary)),
                  const SizedBox(height: 6),
                  _row('운송 경로', '${r['route'] ?? ''}'),
                  _row('년도', '${r['shipment_year'] ?? ''}'),
                  _row('항차', _voyageLabel(r['voyage'])),
                  _row('송장번호', '${r['invoice_number'] ?? ''}'),
                  _row('이름/수령인', '${r['consignee_name'] ?? ''}'),
                  _row('연락처', '${r['consignee_phone'] ?? ''}'),
                  _row('입고 날짜', '${r['received_at'] ?? ''}'),
                  _row('무게', '${r['weight_kg'] ?? ''} kg'),
                  _row('크기', size),
                  _row('영수증 번호', '${r['receipt_number'] ?? ''}'),
                  if (_showZone) _row('구획 (Zone)', '${r['unloading_zone'] ?? ''}'),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  String _voyageLabel(dynamic value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return '';
    return text.endsWith('항차') ? text : '$text항차';
  }

  InputDecoration _dropDecoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(10),
        ),
      );

  Widget _input(TextEditingController controller, String hint, IconData icon,
          {TextInputType type = TextInputType.text}) =>
      TextField(
        controller: controller,
        keyboardType: type,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon),
          filled: true,
          fillColor: AppColors.inputFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

class _LoginRequiredView extends StatelessWidget {
  const _LoginRequiredView({this.onLogin});
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline,
                  size: 58, color: AppColors.navyPrimary),
              const SizedBox(height: 14),
              const Text('로그인 후 화물 조회가 가능합니다.',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navyPrimary)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login),
                label: const Text('로그인 하기'),
              ),
            ],
          ),
        ),
      );
}

class ShipmentSearchScreen extends StatelessWidget {
  const ShipmentSearchScreen({
    super.key,
    this.language = AppLanguage.korean,
    this.currentUser,
  });
  final AppLanguage language;
  final AppUser? currentUser;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: ShipmentSearchBody(
          language: language,
          isLoggedIn: currentUser != null,
          currentUser: currentUser,
        ),
      );
}






