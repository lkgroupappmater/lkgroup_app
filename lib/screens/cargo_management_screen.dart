import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/route_catalog.dart';
import '../models/app_user.dart';
import '../services/shipment_service.dart';
import 'notice_management_screen.dart';
import 'schedule_management_screen.dart';
import 'excel_upload_screen.dart';
import 'exchange_rate_screen.dart';
import 'member_management_screen.dart';
import 'change_approval_screen.dart';

class CargoManagementScreen extends StatefulWidget {
  const CargoManagementScreen({
    super.key,
    required this.user,
    this.onBack,
    this.initialSelectedIds = const <String>[],
  });

  final AppUser user;
  final VoidCallback? onBack;
  final List<String> initialSelectedIds;

  @override
  State<CargoManagementScreen> createState() =>
      _CargoManagementScreenState();
}

class _CargoManagementScreenState
    extends State<CargoManagementScreen> {
  final _boxNumberController = TextEditingController();
  final _invoiceController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _noteController = TextEditingController();

  String _route = routeLabels.first;
  String _year = '2026년';
  String _voyage = '01항차';
  List<Map<String, dynamic>> _results = const [];
  final Set<String> _selectedIds = <String>{};
  bool _searched = false;
  bool _busy = false;

  bool get _isAdmin => widget.user.role == UserRole.admin;
  bool get _isStaff => widget.user.role == UserRole.staff;
  bool get _isPartner => widget.user.role == UserRole.partner;
  bool get _canSaveDirectly => _isAdmin || _isPartner;

  @override
  void initState() {
    super.initState();
    _selectedIds.addAll(widget.initialSelectedIds);
    if (widget.initialSelectedIds.isNotEmpty) _loadSelected();
  }

  @override
  void dispose() {
    _boxNumberController.dispose();
    _invoiceController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadSelected() async {
    final rows =
        await ShipmentService.instance.getRowsByIds(widget.initialSelectedIds);
    if (!mounted) return;
    setState(() {
      _results = rows;
      _searched = true;
    });
  }

  Future<void> _search() async {
    setState(() => _busy = true);
    try {
      final rows = await ShipmentService.instance.searchRows(
        route: _route,
        boxNumber: _boxNumberController.text.trim(),
        invoice: _invoiceController.text.trim(),
        recipient: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        year: _year,
        voyage: _voyage,
        currentUser: widget.user,
      );
      if (!mounted) return;
      setState(() {
        _results = rows;
        _searched = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  Future<void> _save() async {
    if (_selectedIds.isEmpty) return;
    if (!_canSaveDirectly) {
      _message('일반 회원의 수정은 기존 수정 요청/승인 정책을 사용합니다.');
      return;
    }

    for (final id in _selectedIds) {
      await ShipmentService.instance.updateRow(id, {
        if (_selectedIds.length == 1 && _boxNumberController.text.trim().isNotEmpty)
          'box_number': _boxNumberController.text.trim(),
        if (_invoiceController.text.trim().isNotEmpty)
          'invoice_number': _invoiceController.text.trim(),
        if (_nameController.text.trim().isNotEmpty)
          'consignee_name': _nameController.text.trim(),
        if (_phoneController.text.trim().isNotEmpty)
          'consignee_phone': _phoneController.text.trim(),
        if (_noteController.text.trim().isNotEmpty)
          'notes': _noteController.text.trim(),
      });
    }
    _message('선택한 화물 정보를 저장했습니다.');
    await _search();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _decoration(String label, IconData icon) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );

  Widget _managementSection() {
    final items = <Map<String, Object>>[
      {
        'label': '선적 일정 관리',
        'icon': Icons.calendar_month,
        'page': ScheduleManagementScreen(user: widget.user),
      },
      {
        'label': '공지사항 관리',
        'icon': Icons.campaign_outlined,
        'page': NoticeManagementScreen(user: widget.user),
      },
      {
        'label': '화물 종합 관리',
        'icon': Icons.inventory_2_outlined,
        'page': CargoManagementScreen(user: widget.user),
      },
    ];

    if (_isAdmin || _isStaff) {
      items.add({
        'label': '엑셀 화물 업로드',
        'icon': Icons.upload_file_outlined,
        'page': const ExcelUploadScreen(),
      });
    }

    if (_isAdmin) {
      items.addAll([
        {
          'label': '회원 종합 관리',
          'icon': Icons.people_alt_outlined,
          'page': const MemberManagementScreen(),
        },
        {
          'label': '변경 승인 관리',
          'icon': Icons.fact_check_outlined,
          'page': const ChangeApprovalScreen(),
        },
        {
          'label': '기준 환율 입력',
          'icon': Icons.currency_exchange,
          'page': const ExchangeRateScreen(),
        },
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '통합 관리',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.65,
          children: items.map((item) {
            return OutlinedButton.icon(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => item['page']! as Widget,
                ),
              ),
              icon: Icon(item['icon']! as IconData, size: 18),
              label: Text(
                item['label']! as String,
                textAlign: TextAlign.center,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('계정으로 돌아가기'),
              ),
            ),
          Card(
            color: AppColors.primary,
            child: ListTile(
              leading: CircleAvatar(
                backgroundImage: widget.user.avatarUrl != null &&
                        widget.user.avatarUrl!.trim().isNotEmpty
                    ? NetworkImage(widget.user.avatarUrl!)
                    : null,
                child: widget.user.avatarUrl == null ||
                        widget.user.avatarUrl!.trim().isEmpty
                    ? const Icon(Icons.person)
                    : null,
              ),
              title: Text(
                widget.user.name.isEmpty ? '회원' : widget.user.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                widget.user.roleLabel,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _isAdmin ? '통합 관리' : '화물 관리',
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _route,
            decoration: _decoration('운송 경로', Icons.route),
            items: routeLabels
                .map((route) =>
                    DropdownMenuItem(value: route, child: Text(route)))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _route = value);
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _boxNumberController,
            decoration: _decoration(
              RouteCatalog.boxExampleFor(_route).isEmpty
                  ? '박스번호'
                  : '박스번호 (예: ${RouteCatalog.boxExampleFor(_route)})',
              Icons.inventory_2_outlined,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _year,
                  decoration:
                      _decoration('년도', Icons.calendar_today),
                  items: const ['2026년', '2027년', '2028년']
                      .map((v) =>
                          DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _year = v);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _voyage,
                  decoration: _decoration(
                      '항차', Icons.confirmation_number_outlined),
                  items: List.generate(
                    30,
                    (i) =>
                        '${(i + 1).toString().padLeft(2, '0')}항차',
                  )
                      .map((v) =>
                          DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _voyage = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _invoiceController,
            decoration:
                _decoration('송장번호', Icons.receipt_long_outlined),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameController,
            decoration:
                _decoration('이름/라오스 수령인', Icons.person_outline),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: _decoration('연락처', Icons.phone_outlined),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _search,
              icon: const Icon(Icons.search),
              label: Text(_busy ? '검색 중...' : '화물 검색'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          if (_searched) ...[
            const SizedBox(height: 16),
            Text(
              '화물 정보 (${_results.length}건)',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            ..._results.map((item) {
              final id = '${item['id']}';
              return Card(
                child: ListTile(
                  onTap: () => _toggle(id),
                  leading: Checkbox(
                    value: _selectedIds.contains(id),
                    onChanged: (_) => _toggle(id),
                  ),
                  title: Text(
                      '${item['box_number'] ?? ''} · ${item['invoice_number'] ?? ''}'),
                  subtitle: Text(
                      '${item['consignee_name'] ?? ''} · ${item['consignee_phone'] ?? ''}\n'
                      '${item['route'] ?? ''} · ${item['shipment_year'] ?? ''} · ${item['voyage'] ?? ''}항차'),
                  isThreeLine: true,
                ),
              );
            }),
          ],
          if (_selectedIds.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              '선택한 화물 정보 수정',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration:
                  _decoration('수정 내용 메모', Icons.edit_note_outlined),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(
                  _canSaveDirectly ? '화물 정보 저장' : '화물 정보 수정 요청'),
            ),
          ],
          if (_isAdmin || _isStaff) ...[
            const SizedBox(height: 22),
            _managementSection(),
          ],
        ],
      );
}
