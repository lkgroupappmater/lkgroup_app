import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/route_catalog.dart';
import '../models/app_user.dart';
import 'notice_management_screen.dart';
import 'schedule_management_screen.dart';

class CargoManagementScreen extends StatefulWidget {
  const CargoManagementScreen({super.key, required this.user, this.onBack});
  final AppUser user;
  final VoidCallback? onBack;

  @override
  State<CargoManagementScreen> createState() => _CargoManagementScreenState();
}

class _CargoManagementScreenState extends State<CargoManagementScreen> {
  final _searchController = TextEditingController();
  final _invoiceController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _noteController = TextEditingController();

  String _route = routeLabels.first;
  String _year = '2026년';
  String _voyage = '01항차';
  String? _selectedId;
  bool _searched = false;

  // TODO: 실제 운영 시 이 목록은 Supabase shipments 테이블에서 조회합니다.
  final List<Map<String, String>> _shipments = [
    {'id': '1', 'invoice': 'LK-2026-001', 'name': '김철수', 'phone': '020-1111-2222', 'route': '한국->라오스 해상', 'year': '2026년', 'voyage': '01항차'},
    {'id': '2', 'invoice': 'LK-2026-002', 'name': '이영희', 'phone': '020-3333-4444', 'route': '한국->라오스 항공', 'year': '2026년', 'voyage': '02항차'},
    {'id': '3', 'invoice': 'LK-2026-003', 'name': '박민수', 'phone': '020-5555-6666', 'route': '라오스->한국 항공 특송', 'year': '2026년', 'voyage': '01항차'},
  ];

  bool get _isAdmin => widget.user.role == UserRole.admin;
  bool get _isPartner => widget.user.role == UserRole.partner;
  bool get _canSaveDirectly => _isAdmin || _isPartner;

  @override
  void dispose() {
    _searchController.dispose();
    _invoiceController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<Map<String, String>> get _results {
    final query = _searchController.text.trim().toLowerCase();
    return _shipments.where((item) {
      final routeMatches = _route == '전체' || item['route'] == _route;
      final textMatches = query.isEmpty || item.values.join(' ').toLowerCase().contains(query);
      return routeMatches && textMatches;
    }).toList();
  }

  void _search() => setState(() => _searched = true);

  void _selectShipment(Map<String, String> item) {
    setState(() {
      _selectedId = item['id'];
      _invoiceController.text = item['invoice'] ?? '';
      _nameController.text = item['name'] ?? '';
      _phoneController.text = item['phone'] ?? '';
      _route = item['route'] ?? routeLabels.first;
      _year = item['year'] ?? '2026년';
      _voyage = item['voyage'] ?? '01항차';
      _noteController.clear();
    });
  }

  void _save() {
    if (_invoiceController.text.trim().isEmpty || _nameController.text.trim().isEmpty) {
      _message('송장번호와 수령인 이름을 입력해 주세요.');
      return;
    }
    final changes = <String, String>{
      'invoice': _invoiceController.text.trim(),
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'route': _route,
      'year': _year,
      'voyage': _voyage,
    };

    if (_canSaveDirectly) {
      final index = _shipments.indexWhere((item) => item['id'] == _selectedId);
      if (index >= 0) {
        setState(() => _shipments[index].addAll(changes));
      }
      // TODO: 관리자/파트너: Supabase shipments update(...).eq('id', _selectedId)
      _message('화물 정보가 저장되어 적용되었습니다.');
    } else {
      // TODO: 일반 회원: shipment_change_requests insert 후 총괄 관리자 승인 대기
      _message('화물 정보 수정 요청이 등록되었습니다. 관리자 승인 후 반영됩니다.');
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.primary));
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      );

  Future<void> _openManagementMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.calendar_month), title: const Text('선적 일정 관리'), onTap: () => Navigator.pop(sheetContext, 'schedule')),
          ListTile(leading: const Icon(Icons.campaign_outlined), title: const Text('공지사항 관리'), onTap: () => Navigator.pop(sheetContext, 'notice')),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    Navigator.push<void>(context, MaterialPageRoute(builder: (_) => choice == 'schedule' ? const ScheduleManagementScreen() : const NoticeManagementScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final results = _searched ? _results : <Map<String, String>>[];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.onBack != null) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back), label: const Text('계정으로 돌아가기'))),
        Card(color: AppColors.primary, child: ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text(widget.user.name.isEmpty ? '회원' : widget.user.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), subtitle: Text(widget.user.roleLabel, style: const TextStyle(color: Colors.white70)))),
        const SizedBox(height: 16),
        Text(_isAdmin ? '통합 관리' : '화물 관리', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppColors.primary)),
        const SizedBox(height: 6),
        Text(_canSaveDirectly ? '선택한 화물 정보를 수정하고 바로 저장할 수 있습니다.' : '화물을 검색한 뒤 수정 요청을 등록할 수 있습니다.', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(value: _route, decoration: _decoration('운송 경로', Icons.route), items: routeLabels.map((route) => DropdownMenuItem(value: route, child: Text(route))).toList(), onChanged: (value) => setState(() => _route = value ?? _route)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(value: _year, decoration: _decoration('년도', Icons.calendar_today), items: const ['2026년', '2027년', '2028년'].map((year) => DropdownMenuItem(value: year, child: Text(year))).toList(), onChanged: (value) => setState(() => _year = value ?? _year))),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonFormField<String>(value: _voyage, decoration: _decoration('항차', Icons.confirmation_number_outlined), items: const ['01항차', '02항차', '03항차', '04항차', '05항차'].map((voyage) => DropdownMenuItem(value: voyage, child: Text(voyage))).toList(), onChanged: (value) => setState(() => _voyage = value ?? _voyage))),
        ]),
        const SizedBox(height: 10),
        TextField(controller: _searchController, onSubmitted: (_) => _search(), decoration: _decoration('화물 검색(송장번호·이름·연락처)', Icons.search)),
        const SizedBox(height: 10),
        SizedBox(height: 46, child: ElevatedButton.icon(onPressed: _search, icon: const Icon(Icons.search), label: const Text('화물 검색'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white))),
        if (_searched) ...[
          const SizedBox(height: 16),
          Text('화물 정보 (${results.length}건)', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 8),
          if (results.isEmpty) const Text('검색 결과가 없습니다.', style: TextStyle(color: AppColors.textSecondary)),
          ...results.map((item) => Card(child: ListTile(selected: item['id'] == _selectedId, onTap: () => _selectShipment(item), leading: Radio<String>(value: item['id']!, groupValue: _selectedId, onChanged: (_) => _selectShipment(item)), title: Text(item['invoice'] ?? ''), subtitle: Text('${item['name']}  ·  ${item['phone']}\n${item['route']}  ·  ${item['year']}  ·  ${item['voyage']}'), isThreeLine: true))),
        ],
        const SizedBox(height: 16),
        if (_selectedId != null) ...[
          const Text('선택한 화물 정보 수정', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 8),
          TextField(controller: _invoiceController, decoration: _decoration('송장번호', Icons.receipt_long_outlined)),
          const SizedBox(height: 10),
          TextField(controller: _nameController, decoration: _decoration('이름/라오스 수령인', Icons.person_outline)),
          const SizedBox(height: 10),
          TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: _decoration('연락처', Icons.phone_outlined)),
          const SizedBox(height: 10),
          TextField(controller: _noteController, maxLines: 3, decoration: _decoration('수정 내용 메모', Icons.edit_note_outlined)),
          const SizedBox(height: 14),
          SizedBox(height: 48, child: ElevatedButton.icon(onPressed: _save, icon: Icon(_canSaveDirectly ? Icons.save : Icons.send), label: Text(_canSaveDirectly ? '화물 정보 저장' : '화물 정보 수정 요청'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white))),
        ],
        if (_isAdmin) ...[
          const SizedBox(height: 22),
          OutlinedButton.icon(onPressed: _openManagementMenu, icon: const Icon(Icons.settings), label: const Text('일정·공지 관리')),
        ],
      ],
    );
  }
}

