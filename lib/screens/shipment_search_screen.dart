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
    if (user == null ||
        (user.role != UserRole.member && user.role != UserRole.admin)) {
      return;
    }
    final isAdmin = user.role == UserRole.admin;

    final name = TextEditingController(
      text: isAdmin ? '${row['consignee_name'] ?? ''}' : user.name,
    );
    final phone = TextEditingController(
      text: isAdmin ? '${row['consignee_phone'] ?? ''}' : user.phone,
    );
    final note = TextEditingController(text: '${row['notes'] ?? ''}');

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              isAdmin ? '수취인 불명 화물 정보 입력' : '본인 화물 확인 및 정정 요청',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['route'] ?? ''} / ${row['shipment_year'] ?? ''}년도 / '
                    '${_voyageLabel(row['voyage'])}\n'
                    '화물번호: ${row['box_number'] ?? ''}\n'
                    '송장번호: ${row['invoice_number'] ?? ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText: isAdmin ? '수취인 이름 / 회사명' : '본인 이름',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: isAdmin ? '연락처' : '본인 연락처',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: note,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: isAdmin ? '비고' : '확인 참고 내용 (선택)',
                      hintText: isAdmin
                          ? '필요한 경우 비고를 입력해 주세요.'
                          : '물품 내용, 발송인 등 관리자 확인에 도움이 되는 내용을 입력해 주세요.',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isAdmin
                        ? '관리자는 입력한 수취인 정보를 바로 반영하고 영수번호/구획을 다시 계산합니다.'
                        : '요청 승인 후 수취인 정보가 반영되며 영수번호는 해당 항차 기준으로 처리됩니다.',
                    style: const TextStyle(
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
                child: Text(isAdmin ? '수취인 정보 적용' : '본인 화물 확인 요청'),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmed) {
      try {
        if (isAdmin) {
          await UnknownRecipientService.instance.resolveUnknownFromSearch(
            shipmentId: '${row['id']}',
            consigneeName: name.text,
            consigneePhone: phone.text,
            notes: note.text,
          );
        } else {
          await UnknownRecipientService.instance.createClaim(
            shipmentId: '${row['id']}',
            claimantName: name.text,
            claimantPhone: phone.text,
            note: note.text,
          );
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAdmin
                  ? '수취인 정보를 반영했습니다.'
                  : '관리자에게 본인 화물 확인 및 정정 요청을 보냈습니다.',
            ),
          ),
        );
        await _loadUnknownRecipientCargo();
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAdmin
                  ? '수취인 정보 적용 실패: $error'
                  : '본인 화물 확인 요청 실패: $error',
            ),
          ),
        );
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));
    name.dispose();
    phone.dispose();
    note.dispose();
  }
  Widget _unknownRecipientSection() {
    if (!widget.isLoggedIn || widget.currentUser == null) {
      return const SizedBox.shrink();
    }
    final role = widget.currentUser!.role;
    final canOpen = role == UserRole.member || role == UserRole.admin;
    final isAdmin = role == UserRole.admin;

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
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          isAdmin
              ? '관리자는 확인이 필요한 화물을 눌러 수취인 이름과 연락처를 바로 입력·수정할 수 있습니다.'
              : '본인 화물이 확인되면 해당 화물을 눌러 이름과 연락처를 입력하고 확인 요청할 수 있습니다.',
          style: const TextStyle(
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

            final route = '${row['route'] ?? ''}'.trim();
            final year = '${row['shipment_year'] ?? ''}'.trim();
            final voyage = _voyageLabel(row['voyage']);
            final box = '${row['box_number'] ?? ''}'.trim();
            final invoice = '${row['invoice_number'] ?? ''}'.trim();
            final name = '${row['consignee_name'] ?? ''}'.trim();
            final phone = '${row['consignee_phone'] ?? ''}'.trim();

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: warningBorder ?? const Color(0xFFE1E7EF),
                  width: warningBorder == null ? 1 : 2.2,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: canOpen && (!pending || isAdmin)
                    ? () => _claimUnknownCargo(row)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$route / ${year}년도 / $voyage',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: AppColors.navyPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '화물번호: ${box.isEmpty ? '-' : box}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '송장번호: ${invoice.isEmpty ? '-' : invoice}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '이름/연락처: '
                              '${name.isEmpty ? '수취인 불명' : name} / '
                              '${phone.isEmpty ? '-' : phone}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            if (pending && !isAdmin) ...[
                              const SizedBox(height: 6),
                              const Text(
                                '확인 요청 대기',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (canOpen && (!pending || isAdmin))
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 18),
                          child: Container(
                            width: 92,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.navyPrimary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              isAdmin
                                  ? '화물을 눌러\n정보 입력/수정'
                                  : '화물을 눌러\n본인 확인 요청',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 10.5,
                                height: 1.25,
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
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

  Widget _searchFixedBottomBar() {
    final allSelected = _results.isNotEmpty &&
        _selectedIds.containsAll(_results.map((r) => '${r['id']}'));

    Widget divider() => Container(
          width: 1,
          height: 34,
          color: Colors.white.withValues(alpha: .16),
        );

    Widget action({
      required IconData icon,
      required String label,
      required bool enabled,
      required VoidCallback onTap,
    }) =>
        Expanded(
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(15),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: enabled ? AppColors.tealAccent : Colors.white38,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: enabled ? Colors.white : Colors.white38,
                  ),
                ),
              ],
            ),
          ),
        );

    return Material(
      elevation: 14,
      borderRadius: BorderRadius.circular(22),
      color: Colors.transparent,
      shadowColor: Colors.black38,
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: AppColors.navyPrimary,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              action(
                icon: allSelected
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
                label: '전체',
                enabled: _results.isNotEmpty,
                onTap: _toggleAll,
              ),
              divider(),
              action(
                icon: Icons.price_check_outlined,
                label: '운임 확인',
                enabled: _selectedIds.isNotEmpty,
                onTap: _showFreight,
              ),
              divider(),
              action(
                icon: Icons.inventory_2_outlined,
                label: '화물 관리',
                enabled:
                    _selectedIds.isNotEmpty && widget.onManageSelected != null,
                onTap: () => widget.onManageSelected!(
                  _selectedIds.toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    if (!widget.isLoggedIn) {
      return _LoginRequiredView(onLogin: widget.onRequireLogin);
    }


    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
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
          SizedBox(
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
          if (_searched)
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: _searchFixedBottomBar(),
            ),
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

  List<MapEntry<String, List<Map<String, dynamic>>>> _receiptGroups(
    List<Map<String, dynamic>> rows,
  ) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final receipt = '${row['receipt_number'] ?? ''}'.trim();
      map.putIfAbsent(receipt, () => <Map<String, dynamic>>[]).add(row);
    }
    final entries = map.entries.toList();
    int tailNumber(String value) {
      final m = RegExp(r'(\d+)\s*$').firstMatch(value);
      return m == null ? 999999 : int.tryParse(m.group(1)!) ?? 999999;
    }
    entries.sort((a, b) {
      final an = tailNumber(a.key);
      final bn = tailNumber(b.key);
      if (an != bn) return an.compareTo(bn);
      return a.key.compareTo(b.key);
    });
    return entries;
  }

  void _toggleReceiptGroup(List<Map<String, dynamic>> rows) {
    final ids = rows.map((r) => '${r['id']}').toSet();
    setState(() {
      if (ids.isNotEmpty && _selectedIds.containsAll(ids)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
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
            ..._receiptGroups(rows).map((e) => _receiptResultCard(e.value)),
          ],
        ),
      );
    }).toList();
  }

  Widget _receiptResultCard(List<Map<String, dynamic>> rows) {
    final first = rows.first;
    final ids = rows.map((r) => '${r['id']}').toSet();
    final all = ids.isNotEmpty && _selectedIds.containsAll(ids);
    final receipt = '${first['receipt_number'] ?? ''}'.trim();
    final zone = '${first['unloading_zone'] ?? ''}'.trim();
    final name = '${first['consignee_name'] ?? ''}'.trim();
    final company = _companyOf(first);
    final phone = '${first['consignee_phone'] ?? ''}'.trim();
    final totalQty = rows.fold<int>(
      0,
      (sum, r) => sum + (int.tryParse('${r['quantity'] ?? ''}') ?? 1),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD7DEE7)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: all,
                  onChanged: (_) => _toggleReceiptGroup(rows),
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '$name / ${company.isEmpty ? '-' : company}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyPrimary,
                        ),
                      ),
                      Text(
                        phone.isEmpty ? '-' : phone,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyPrimary,
                        ),
                      ),
                      Text.rich(
                        TextSpan(children: [
                          const TextSpan(
                            text: '영수번호/구획: ',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          TextSpan(
                            text: receipt.isEmpty ? '-' : receipt,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.navyPrimary,
                            ),
                          ),
                          const TextSpan(
                            text: ' / ',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          TextSpan(
                            text: _showZone ? (zone.isEmpty ? '-' : zone) : '-',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.navyPrimary,
                            ),
                          ),
                        ]),
                      ),
                      Text.rich(
                        TextSpan(children: [
                          const TextSpan(
                            text: '총 개수: ',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          TextSpan(
                            text: '$totalQty개',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.navyPrimary,
                            ),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ...rows.map(_shipmentCard),
        ],
      ),
    );
  }

  Widget _shipmentCard(Map<String, dynamic> r) {
    final id = '${r['id']}';
    final quantity = int.tryParse('${r['quantity'] ?? ''}') ?? 1;
    final receivedDate = _dateOnly(r['received_at']);
    final length = _naturalNumber(r['length_cm']);
    final height = _naturalNumber(r['height_cm']);
    final width = _naturalNumber(r['width_cm']);
    final size = '$length × $height × $width cm';

    return InkWell(
      onTap: () => _toggle(id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _selectedIds.contains(id),
              onChanged: (_) => _toggle(id),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('화물번호', '${r['box_number'] ?? ''}'),
                  _row('송장번호', '${r['invoice_number'] ?? ''}'),
                  _row('화물개수', '$quantity개'),
                  _row(
                    '무게 / 크기',
                    '${_weightOneDecimal(r['weight_kg'])} kg / $size',
                  ),
                  _row('입고날짜', receivedDate),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  String _weightOneDecimal(dynamic value) {
    final text = '${value ?? ''}'.trim();
    final number = double.tryParse(text);
    return number == null ? (text.isEmpty ? '-' : text) : number.toStringAsFixed(1);
  }

  String _naturalNumber(dynamic value) {
    final text = '${value ?? ''}'.trim();
    final number = double.tryParse(text);
    return number == null ? (text.isEmpty ? '-' : text) : number.round().toString();
  }
  String _dateOnly(dynamic value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return '-';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return text.length >= 10 ? text.substring(0, 10) : text;
    }
    final local = parsed.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  String _companyOf(Map<String, dynamic> row) {
    for (final key in const ['consignee_company', 'company_name', 'company']) {
      final value = '${row[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
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








