// lib/screens/shipment_search_screen.dart
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../core/route_catalog.dart';
import '../models/app_user.dart';
import '../services/freight_service.dart';
import '../services/shipment_service.dart';

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
  int _selectedRoute = 0;
  final _invoiceCtrl = TextEditingController();
  final _boxNumberCtrl = TextEditingController();
  final _recipientCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  List<Map<String, dynamic>> _results = [];
  bool _searched = false;
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _prefillMemberFields();
  }

  @override
  void didUpdateWidget(covariant ShipmentSearchBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser?.id != widget.currentUser?.id) {
      _prefillMemberFields();
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
    _boxNumberCtrl.dispose();
    _recipientCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    try {
      final dbRows = await ShipmentService.instance.searchRows(
        route: routeLabels[_selectedRoute],
        boxNumber: _boxNumberCtrl.text.trim(),
        invoice: _invoiceCtrl.text.trim(),
        recipient: _recipientCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
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
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ...result.lines.map((line) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('박스번호 ${line.boxNumber} · 송장번호 ${line.invoiceNumber}'),
                      subtitle: Text(
                          '청구중량 ${line.chargeableWeight.toStringAsFixed(2)}kg · 단가 \$${line.rate.toStringAsFixed(2)}/kg'),
                      trailing:
                          Text('\$${line.amountUsd.toStringAsFixed(2)}'),
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

    final canSeeAll = widget.currentUser?.role.canSeeAllShipments == true;
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
            decoration: InputDecoration(
              labelText: '운송 경로',
              prefixIcon: const Icon(Icons.route_outlined,
                  color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.inputFill,
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            items: List.generate(
              routeLabels.length,
              (index) =>
                  DropdownMenuItem(value: index, child: Text(routeLabels[index])),
            ),
            onChanged: (value) {
              if (value != null) setState(() => _selectedRoute = value);
            },
          ),
          const SizedBox(height: 14),
          if (canSeeAll) ...[
            _input(
              _boxNumberCtrl,
              RouteCatalog.boxExampleFor(routeLabels[_selectedRoute]).isEmpty
                  ? '박스 번호'
                  : '박스 번호 (예: ${RouteCatalog.boxExampleFor(routeLabels[_selectedRoute])})',
              Icons.inventory_2_outlined,
            ),
            const SizedBox(height: 10),
          ],
          _input(_invoiceCtrl, '송장번호', Icons.tag_rounded),
          const SizedBox(height: 10),
          _input(_recipientCtrl, '이름/라오스 수령인', Icons.person_outline,
              readOnly: !canSeeAll),
          const SizedBox(height: 10),
          _input(_phoneCtrl, '라오스 수령인 연락처', Icons.phone_outlined,
              readOnly: !canSeeAll, type: TextInputType.phone),
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
                    activeColor: AppColors.primary),
                const Text('전체 선택'),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed:
                      _selectedIds.isEmpty || widget.onManageSelected == null
                          ? null
                          : () =>
                              widget.onManageSelected!(_selectedIds.toList()),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('화물 관리'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          if (_searched && _results.isEmpty)
            const Center(child: Text('검색 결과가 없습니다.')),
          ..._results.map((r) {
            final id = '${r['id']}';
            final size =
                '${r['length_cm'] ?? ''} × ${r['width_cm'] ?? ''} × ${r['height_cm'] ?? ''} cm';
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                        value: _selectedIds.contains(id),
                        onChanged: (_) => _toggle(id)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('박스번호 ${r['box_number'] ?? ''}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.navyPrimary)),
                          const SizedBox(height: 6),
                          _row('송장번호', '${r['invoice_number'] ?? ''}'),
                          _row('이름/수령인', '${r['consignee_name'] ?? ''}'),
                          _row('연락처', '${r['consignee_phone'] ?? ''}'),
                          _row('입고 날짜', '${r['received_at'] ?? ''}'),
                          _row('무게', '${r['weight_kg'] ?? ''} kg'),
                          _row('크기', size),
                          _row('영수증 번호', '${r['receipt_number'] ?? ''}'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _input(TextEditingController controller, String hint, IconData icon,
          {bool readOnly = false, TextInputType type = TextInputType.text}) =>
      TextField(
        controller: controller,
        readOnly: readOnly,
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
          children: [
            SizedBox(
                width: 88,
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary))),
            Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600))),
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
                  label: const Text('로그인 하기')),
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
