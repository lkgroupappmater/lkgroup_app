import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/route_catalog.dart';
import '../models/app_user.dart';
import 'notice_management_screen.dart';
import 'schedule_management_screen.dart';
import 'member_management_screen.dart';
import 'change_approval_screen.dart';

class CargoManagementScreen extends StatefulWidget {
  const CargoManagementScreen({super.key, required this.user, this.onBack, this.initialShipments = const []});
  final AppUser user;
  final VoidCallback? onBack;
  final List<Map<String, dynamic>> initialShipments;
  @override
  State<CargoManagementScreen> createState() => _CargoManagementScreenState();
}

class _CargoManagementScreenState extends State<CargoManagementScreen> {
  // Search and edit controllers are separate so cancel/save never changes the search results.
  final _searchInvoice = TextEditingController();
  final _searchName = TextEditingController();
  final _searchPhone = TextEditingController();
  final _invoice = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _receiptNo = TextEditingController();
  final _note = TextEditingController();
  final _weight = TextEditingController();
  final _width = TextEditingController();
  final _length = TextEditingController();
  final _height = TextEditingController();
  String _route = routeLabels.first;
  String _year = '2026년';
  String _voyage = '01항차';
  String? _selectedId;
  final Set<String> _selectedIds = <String>{};
  bool _searched = false;

  final List<Map<String, String>> _shipments = [
    {'id':'1','invoice':'LK-2026-001','receiptNo':'RC-2026-001','name':'김철수','phone':'020-1111-2222','route':'한국->라오스 해상','year':'2026년','voyage':'01항차','weight':'120','width':'40','length':'60','height':'35'},
    {'id':'2','invoice':'LK-2026-002','name':'이영희','phone':'020-3333-4444','route':'한국->라오스 항공','year':'2026년','voyage':'02항차','weight':'45','width':'30','length':'45','height':'25'},
    {'id':'3','invoice':'LK-2026-003','name':'박민수','phone':'020-5555-6666','route':'라오스->한국 항공 특송','year':'2026년','voyage':'01항차','weight':'78','width':'35','length':'50','height':'30'},
  ];

  bool get _isAdmin => widget.user.role == UserRole.admin;
  bool get _isStaff => widget.user.role == UserRole.staff;
  bool get _isPartner => widget.user.role == UserRole.partner;
  bool get _canSaveDirectly => _isAdmin || _isStaff || _isPartner;

  @override
  void initState() {
    super.initState();
    for (final raw in widget.initialShipments) {
      final item = _normalize(raw);
      final id = item['id'];
      if (id != null && _shipments.every((row) => row['id'] != id)) _shipments.add(item);
      if (id != null) _selectedIds.add(id);
    }
    if (_selectedIds.isNotEmpty) {
      _selectedId = _selectedIds.first;
      _load(_selectedId!);
      _searched = true;
    }
  }

  Map<String, String> _normalize(Map<String, dynamic> raw) => {
    'id': (raw['id'] ?? raw['boxNo'] ?? '').toString(),
    'invoice': (raw['invoice'] ?? raw['invoiceNo'] ?? '').toString(),
    'receiptNo': (raw['receiptNo'] ?? raw['receiptNumber'] ?? raw['receipt_no'] ?? '').toString(),
    'name': (raw['name'] ?? raw['consigneeName'] ?? '').toString(),
    'phone': (raw['phone'] ?? raw['contact'] ?? '').toString(),
    'route': (raw['route'] ?? routeLabels.first).toString(),
    'year': (raw['year'] ?? '2026년').toString(),
    'voyage': (raw['voyage'] ?? '01항차').toString(),
    'weight': (raw['weight'] ?? raw['weightKg'] ?? '').toString(),
    'width': (raw['width'] ?? raw['widthCm'] ?? '').toString(),
    'length': (raw['length'] ?? raw['lengthCm'] ?? '').toString(),
    'height': (raw['height'] ?? raw['heightCm'] ?? '').toString(),
  };

  @override
  void dispose() {
    for (final controller in [_searchInvoice,_searchName,_searchPhone,_invoice,_name,_phone,_receiptNo,_note,_weight,_width,_length,_height]) controller.dispose();
    super.dispose();
  }

  List<Map<String, String>> get _results {
    final invoice = _searchInvoice.text.trim().toLowerCase();
    final name = _searchName.text.trim().toLowerCase();
    final phone = _searchPhone.text.trim().toLowerCase();
    return _shipments.where((item) {
      return (_route == '전체' || item['route'] == _route) &&
          (_year == '전체' || item['year'] == _year) &&
          (_voyage == '전체' || item['voyage'] == _voyage) &&
          (invoice.isEmpty || (item['invoice'] ?? '').toLowerCase().contains(invoice)) &&
          (name.isEmpty || (item['name'] ?? '').toLowerCase().contains(name)) &&
          (phone.isEmpty || (item['phone'] ?? '').toLowerCase().contains(phone));
    }).toList();
  }

  void _search() => setState(() => _searched = true);

  void _toggle(Map<String, String> item) {
    final id = item['id']!;
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedId == id) _selectedId = _selectedIds.isEmpty ? null : _selectedIds.first;
      } else {
        _selectedIds.add(id);
        _selectedId = id;
      }
      if (_selectedId != null) _load(_selectedId!); else _clearEdit();
    });
  }

  void _load(String id) {
    final item = _shipments.firstWhere((row) => row['id'] == id, orElse: () => <String, String>{});
    if (item.isEmpty) return;
    _invoice.text = item['invoice'] ?? '';
    _name.text = item['name'] ?? '';
    _phone.text = item['phone'] ?? '';
    _receiptNo.text = item['receiptNo'] ?? '';
    _note.text = item['note'] ?? '';
    _route = item['route'] ?? routeLabels.first;
    _year = item['year'] ?? '2026년';
    _voyage = item['voyage'] ?? '01항차';
    _weight.text = item['weight'] ?? '';
    _width.text = item['width'] ?? '';
    _length.text = item['length'] ?? '';
    _height.text = item['height'] ?? '';
  }

  void _clearEdit() {
    _invoice.clear(); _name.clear(); _phone.clear(); _receiptNo.clear(); _note.clear(); _weight.clear(); _width.clear(); _length.clear(); _height.clear();
  }

  void _save() {
    if (_selectedId == null) return _message('먼저 수정할 화물을 선택해 주세요.');
    if (_name.text.trim().isEmpty) return _message('수령인 이름을 입력해 주세요.');
    // 송장번호와 영수번호는 직원·총괄 관리자 모두 수정하지 못하도록
    // 저장 payload에서도 제외합니다. 검색·상세 표시만 허용합니다.
    final changes = <String, String>{
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'note': _note.text.trim(),
      'route': _route,
      'year': _year,
      'voyage': _voyage,
      'weight': _weight.text.trim(),
      'width': _width.text.trim(),
      'length': _length.text.trim(),
      'height': _height.text.trim(),
    };
    if (_canSaveDirectly) {
      final index = _shipments.indexWhere((row) => row['id'] == _selectedId);
      if (index >= 0) setState(() => _shipments[index].addAll(changes));
      // TODO: Supabase update for staff/admin/partner.
      _message('화물 정보가 저장되어 적용되었습니다.');
    } else {
      // TODO: Insert a shipment_change_requests row for admin approval.
      _message('화물 정보 수정 요청이 등록되었습니다. 관리자 승인 후 반영됩니다.');
    }
  }

  // Keep search controls/results; only close the selected detail editor.
  void _cancel() => setState(() { _selectedIds.clear(); _selectedId = null; _clearEdit(); });
  void _message(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: AppColors.primary)); }
  InputDecoration _dec(String label, IconData icon) => InputDecoration(labelText: label, prefixIcon: Icon(icon), filled: true, fillColor: AppColors.inputFill, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none));

  Widget _managementSection() {
    final items = <Map<String, Object>>[
      {
        'label': '선적 일정 관리',
        'icon': Icons.calendar_month,
        'page': const ScheduleManagementScreen(),
      },
      {
        'label': '공지사항 관리',
        'icon': Icons.campaign_outlined,
        'page': const NoticeManagementScreen(),
      },
      {
        'label': '화물 종합 관리',
        'icon': Icons.inventory_2_outlined,
        'page': CargoManagementScreen(user: widget.user),
      },
    ];
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
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('통합 관리', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
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
              onPressed: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => item['page']! as Widget)),
              icon: Icon(item['icon']! as IconData, size: 18),
              label: Text(item['label']! as String, textAlign: TextAlign.center),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _number(TextEditingController controller, String label) => SizedBox(width: 105, child: TextField(controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _dec(label, Icons.straighten)));

  @override
  Widget build(BuildContext context) {
    final results = _searched ? _results : <Map<String, String>>[];
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (widget.onBack != null) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back), label: const Text('계정으로 돌아가기'))),
      Card(color: AppColors.primary, child: ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text(widget.user.name.isEmpty ? '회원' : widget.user.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), subtitle: Text(widget.user.roleLabel, style: const TextStyle(color: Colors.white70)))),
      const SizedBox(height: 16),
      Text((_isAdmin || _isStaff) ? '통합 관리' : '화물 관리', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppColors.primary)),
      const SizedBox(height: 6),
      Text(_canSaveDirectly ? '선택한 화물 정보를 수정하고 바로 저장할 수 있습니다.' : '화물을 검색한 뒤 수정 요청을 등록할 수 있습니다.', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(value: _route, decoration: _dec('운송 경로', Icons.route), items: routeLabels.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(), onChanged: (v) { if (v != null) setState(() => _route = v); }),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: DropdownButtonFormField<String>(value: _year, decoration: _dec('년도', Icons.calendar_today), items: const ['전체','2026년','2027년','2028년'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) { if (v != null) setState(() => _year = v); })), const SizedBox(width: 10), Expanded(child: DropdownButtonFormField<String>(value: _voyage, decoration: _dec('항차', Icons.confirmation_number_outlined), items: const ['전체','01항차','02항차','03항차','04항차','05항차'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) { if (v != null) setState(() => _voyage = v); }))]),
      const SizedBox(height: 10),
      TextField(controller: _searchInvoice, onSubmitted: (_) => _search(), decoration: _dec('송장번호', Icons.receipt_long_outlined)), const SizedBox(height: 10),
      TextField(controller: _searchName, onSubmitted: (_) => _search(), decoration: _dec('이름/라오스 수령인', Icons.person_outline)), const SizedBox(height: 10),
      TextField(controller: _searchPhone, keyboardType: TextInputType.phone, onSubmitted: (_) => _search(), decoration: _dec('전화번호', Icons.phone_outlined)), const SizedBox(height: 10),
      SizedBox(height: 46, child: ElevatedButton.icon(onPressed: _search, icon: const Icon(Icons.search), label: const Text('화물 검색'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white))),
      if (_searched) ...[const SizedBox(height: 16), Text('화물 정보 (${results.length}건)', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)), const SizedBox(height: 8), if (results.isEmpty) const Text('검색 결과가 없습니다.', style: TextStyle(color: AppColors.textSecondary)), ...results.map((item) => Card(child: ListTile(selected: _selectedIds.contains(item['id']), onTap: () => _toggle(item), leading: Checkbox(value: _selectedIds.contains(item['id']), onChanged: (_) => _toggle(item)), title: Text(item['invoice'] ?? ''), subtitle: Text('${item['name']}  ·  ${item['phone']}\n${item['route']}  ·  ${item['year']}  ·  ${item['voyage']}'), isThreeLine: true)))],
      const SizedBox(height: 16),
      if (_selectedIds.isNotEmpty) ...[
        const Text('선택한 화물 정보 수정', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)), const SizedBox(height: 8),
        TextField(controller: _invoice, readOnly: true, decoration: _dec('송장번호 (수정 불가)', Icons.receipt_long_outlined)), const SizedBox(height: 10),
        TextField(controller: _name, decoration: _dec('이름/라오스 수령인', Icons.person_outline)), const SizedBox(height: 10),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: _dec('연락처', Icons.phone_outlined)), const SizedBox(height: 10),
        TextField(controller: _receiptNo, readOnly: true, decoration: _dec('영수번호 (수정 불가)', Icons.confirmation_number_outlined)), const SizedBox(height: 10),
        const Text('화물 규격 수정', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)), const SizedBox(height: 8),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [_number(_weight,'무게(kg)'), const SizedBox(width: 8), _number(_width,'가로(cm)'), const SizedBox(width: 8), _number(_length,'세로(cm)'), const SizedBox(width: 8), _number(_height,'높이(cm)')])),
        const SizedBox(height: 10), TextField(controller: _note, maxLines: 3, decoration: _dec('기타 추가 내용', Icons.edit_note_outlined)), const SizedBox(height: 14),
        Row(children: [Expanded(child: SizedBox(height: 48, child: ElevatedButton.icon(onPressed: _save, icon: Icon(_canSaveDirectly ? Icons.save : Icons.send), label: Text(_canSaveDirectly ? '화물 정보 저장' : '화물 정보 수정 요청'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white)))), const SizedBox(width: 10), Expanded(child: SizedBox(height: 48, child: OutlinedButton(onPressed: _cancel, child: const Text('취소'))))]),
      ],
      if (_isAdmin || _isStaff) ...[const SizedBox(height: 22), _managementSection()],
    ]);
  }
}
