import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  State<CargoManagementScreen> createState() => _CargoManagementScreenState();
}

class _CargoManagementScreenState extends State<CargoManagementScreen> {
  final _boxNumberController = TextEditingController();
  final _invoiceController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  final _editNameController = TextEditingController();
  final _editPhoneController = TextEditingController();
  final _editNoteController = TextEditingController();
  final _weightController = TextEditingController();
  final _lengthController = TextEditingController();
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();

  String _route = routeLabels.first;
  String _year = '전체';
  String _voyage = '전체';
  List<Map<String, dynamic>> _results = const [];
  final Set<String> _selectedIds = <String>{};
  bool _searched = false;
  bool _busy = false;

  bool _showBoxSearch = true;
  bool _showInvoiceSearch = true;
  bool _showNameSearch = true;
  bool _showPhoneSearch = true;

  bool get _isAdmin => widget.user.role == UserRole.admin;
  bool get _isStaff => widget.user.role == UserRole.staff;
  bool get _isPartner => widget.user.role == UserRole.partner;
  bool get _isManager => _isAdmin || _isStaff || _isPartner;
  bool get _canSaveDirectly => _isManager;

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
    _editNameController.dispose();
    _editPhoneController.dispose();
    _editNoteController.dispose();
    _weightController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  Future<void> _loadSelected() async {
    final rows = await ShipmentService.instance.getRowsByIds(widget.initialSelectedIds);
    if (!mounted) return;
    setState(() {
      _results = rows;
      _searched = true;
    });
    _syncEditControllers();
  }

  String _boxNumberForRequest() {
    final raw = _boxNumberController.text.trim();
    if (raw.isEmpty) return '';
    final prefix = RouteCatalog.boxPrefixFor(_route);
    if (prefix.isEmpty) return raw;
    return '$prefix$raw';
  }

  Future<void> _search() async {
    setState(() => _busy = true);
    try {
      final rows = await ShipmentService.instance.searchRows(
        route: _route,
        boxNumber: _showBoxSearch ? _boxNumberForRequest() : '',
        invoice: _showInvoiceSearch ? _invoiceController.text.trim() : '',
        recipient: _showNameSearch ? _nameController.text.trim() : '',
        phone: _showPhoneSearch ? _phoneController.text.trim() : '',
        year: _year,
        voyage: _voyage,
        currentUser: widget.user,
      );
      if (!mounted) return;
      setState(() {
        _results = rows;
        _searched = true;
        if (widget.initialSelectedIds.isEmpty) _selectedIds.clear();
      });
      _syncEditControllers();
    } catch (error) {
      _message('화물 검색 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
    _syncEditControllers();
  }

  void _syncEditControllers() {
    if (_selectedIds.length != 1) {
      _editNameController.clear();
      _editPhoneController.clear();
      _editNoteController.clear();
      _weightController.clear();
      _lengthController.clear();
      _widthController.clear();
      _heightController.clear();
      return;
    }
    final id = _selectedIds.first;
    Map<String, dynamic>? row;
    for (final item in _results) {
      if ('${item['id']}' == id) {
        row = item;
        break;
      }
    }
    if (row == null) return;
    _editNameController.text = '${row['consignee_name'] ?? ''}';
    _editPhoneController.text = '${row['consignee_phone'] ?? ''}';
    _editNoteController.text = '${row['notes'] ?? ''}';
    _weightController.text = '${row['weight_kg'] ?? ''}';
    _lengthController.text = '${row['length_cm'] ?? ''}';
    _widthController.text = '${row['width_cm'] ?? ''}';
    _heightController.text = '${row['height_cm'] ?? ''}';
  }

  Map<String, dynamic> _memberChanges() {
    final changes = <String, dynamic>{};
    if (_editNameController.text.trim().isNotEmpty) {
      changes['consignee_name'] = _editNameController.text.trim();
    }
    if (_editPhoneController.text.trim().isNotEmpty) {
      changes['consignee_phone'] = _editPhoneController.text.trim();
    }
    if (_editNoteController.text.trim().isNotEmpty) {
      changes['notes'] = _editNoteController.text.trim();
    }
    return changes;
  }

  Map<String, dynamic> _managerChanges() {
    final changes = _memberChanges();
    final weight = num.tryParse(_weightController.text.trim());
    final length = num.tryParse(_lengthController.text.trim());
    final width = num.tryParse(_widthController.text.trim());
    final height = num.tryParse(_heightController.text.trim());
    if (_weightController.text.trim().isNotEmpty && weight != null) {
      changes['weight_kg'] = weight;
    }
    if (_lengthController.text.trim().isNotEmpty && length != null) {
      changes['length_cm'] = length;
    }
    if (_widthController.text.trim().isNotEmpty && width != null) {
      changes['width_cm'] = width;
    }
    if (_heightController.text.trim().isNotEmpty && height != null) {
      changes['height_cm'] = height;
    }
    return changes;
  }

  Future<void> _save() async {
    if (_selectedIds.isEmpty) return;
    final changes = _canSaveDirectly ? _managerChanges() : _memberChanges();
    if (changes.isEmpty) {
      _message('수정할 내용을 입력해 주세요.');
      return;
    }

    setState(() => _busy = true);
    try {
      if (_canSaveDirectly) {
        for (final id in _selectedIds) {
          await ShipmentService.instance.updateRow(id, changes);
        }
        _message('선택한 화물 정보를 저장했습니다.');
        await _reloadCurrentRows();
      } else {
        await ShipmentService.instance.requestChanges(
          shipmentIds: _selectedIds.toList(),
          changes: changes,
        );
        _message('관리자에게 화물 정보 수정 요청을 보냈습니다.');
      }
    } catch (error) {
      _message('화물 정보 처리 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reloadCurrentRows() async {
    if (_selectedIds.isEmpty) return;
    final rows = await ShipmentService.instance.getRowsByIds(_selectedIds.toList());
    if (!mounted) return;
    final replacements = {for (final row in rows) '${row['id']}': row};
    setState(() {
      _results = _results
          .map((row) => replacements['${row['id']}'] ?? row)
          .toList(growable: false);
    });
    _syncEditControllers();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
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
                MaterialPageRoute(builder: (_) => item['page']! as Widget),
              ),
              icon: Icon(item['icon']! as IconData, size: 18),
              label: Text(item['label']! as String, textAlign: TextAlign.center),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _filterToggles() => Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _filterChip('박스번호', _showBoxSearch,
              (v) => setState(() => _showBoxSearch = v)),
          _filterChip('송장번호', _showInvoiceSearch,
              (v) => setState(() => _showInvoiceSearch = v)),
          _filterChip('이름', _showNameSearch,
              (v) => setState(() => _showNameSearch = v)),
          _filterChip('연락처', _showPhoneSearch,
              (v) => setState(() => _showPhoneSearch = v)),
        ],
      );

  Widget _filterChip(String label, bool selected, ValueChanged<bool> onSelected) =>
      FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: onSelected,
        visualDensity: VisualDensity.compact,
      );

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: ListView(
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isAdmin ? '통합 관리' : '화물 관리',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                if (_isManager) ...[
                  const SizedBox(width: 10),
                  Expanded(child: _filterToggles()),
                ],
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _route,
              decoration: _decoration('운송 경로', Icons.route),
              items: routeLabels
                  .map((route) => DropdownMenuItem(value: route, child: Text(route)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _route = value;
                    _boxNumberController.clear();
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
                    decoration: _decoration('년도', Icons.calendar_today),
                    items: const ['전체', '2026년', '2027년', '2028년']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
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
                    decoration: _decoration('항차', Icons.confirmation_number_outlined),
                    items: <String>[
                      '전체',
                      ...List.generate(
                        30,
                        (i) => '${(i + 1).toString().padLeft(2, '0')}항차',
                      ),
                    ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _voyage = v);
                    },
                  ),
                ),
              ],
            ),
            if (_isManager && _showBoxSearch) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _boxNumberController,
                keyboardType: RouteCatalog.boxPrefixFor(_route).isEmpty
                    ? TextInputType.text
                    : TextInputType.number,
                inputFormatters: RouteCatalog.boxPrefixFor(_route).isEmpty
                    ? null
                    : <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                      ],
                decoration: _decoration(
                  RouteCatalog.boxExampleFor(_route).isEmpty
                      ? '박스번호'
                      : '박스번호 (예: ${RouteCatalog.boxExampleFor(_route)})',
                  Icons.inventory_2_outlined,
                ).copyWith(
                  prefixText: RouteCatalog.boxPrefixFor(_route).isEmpty
                      ? null
                      : RouteCatalog.boxPrefixFor(_route),
                  prefixStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
            if (!_isManager || _showInvoiceSearch) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _invoiceController,
                decoration: _decoration('송장번호', Icons.receipt_long_outlined),
              ),
            ],
            if (!_isManager || _showNameSearch) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                decoration: _decoration('이름/라오스 수령인', Icons.person_outline),
              ),
            ],
            if (!_isManager || _showPhoneSearch) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: _decoration('연락처', Icons.phone_outlined),
              ),
            ],
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
              ..._results.map(_shipmentCard),
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
                controller: _editNameController,
                decoration: _decoration('이름/라오스 수령인', Icons.person_outline),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _editPhoneController,
                keyboardType: TextInputType.phone,
                decoration: _decoration('연락처', Icons.phone_outlined),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _editNoteController,
                maxLines: 3,
                decoration: _decoration('기타 내용', Icons.edit_note_outlined),
              ),
              if (_isManager) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _numberField(_weightController, '무게(kg)')),
                    const SizedBox(width: 8),
                    Expanded(child: _numberField(_lengthController, '가로(cm)')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _numberField(_widthController, '세로(cm)')),
                    const SizedBox(width: 8),
                    Expanded(child: _numberField(_heightController, '높이(cm)')),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save),
                label: Text(_canSaveDirectly ? '화물 정보 저장' : '화물 정보 수정 요청'),
              ),
            ],
            if (_isAdmin || _isStaff) ...[
              const SizedBox(height: 22),
              _managementSection(),
            ],
          ],
        ),
      );

  Widget _numberField(TextEditingController controller, String label) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: _decoration(label, Icons.straighten_outlined),
      );

  Widget _shipmentCard(Map<String, dynamic> item) {
    final id = '${item['id']}';
    final size =
        '${item['length_cm'] ?? ''} × ${item['width_cm'] ?? ''} × ${item['height_cm'] ?? ''} cm';
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
                    Text('박스번호 ${item['box_number'] ?? ''}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.navyPrimary)),
                    const SizedBox(height: 6),
                    _infoRow('운송 경로', '${item['route'] ?? ''}'),
                    _infoRow('년도', '${item['shipment_year'] ?? ''}'),
                    _infoRow('항차', _voyageLabel(item['voyage'])),
                    _infoRow('송장번호', '${item['invoice_number'] ?? ''}'),
                    _infoRow('이름/수령인', '${item['consignee_name'] ?? ''}'),
                    _infoRow('연락처', '${item['consignee_phone'] ?? ''}'),
                    _infoRow('입고 날짜', '${item['received_at'] ?? ''}'),
                    _infoRow('무게', '${item['weight_kg'] ?? ''} kg'),
                    _infoRow('크기', size),
                    _infoRow('영수증 번호', '${item['receipt_number'] ?? ''}'),
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

  Widget _infoRow(String label, String value) => Padding(
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
