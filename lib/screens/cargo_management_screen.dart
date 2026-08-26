import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/route_catalog.dart';
import '../models/app_user.dart';

class CargoManagementScreen extends StatefulWidget {
  const CargoManagementScreen({super.key, required this.user, this.onBack});
  final AppUser user;
  final VoidCallback? onBack;
  @override
  State<CargoManagementScreen> createState() => _CargoManagementScreenState();
}

class _CargoManagementScreenState extends State<CargoManagementScreen> {
  final _cargoNo = TextEditingController();
  final _invoiceSearch = TextEditingController();
  final _nameSearch = TextEditingController();
  final _phoneSearch = TextEditingController();
  final _boxNo = TextEditingController();
  final _invoice = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _weight = TextEditingController();
  final _width = TextEditingController();
  final _length = TextEditingController();
  final _height = TextEditingController();
  final _receipt = TextEditingController();
  final _note = TextEditingController();

  String _route = routeLabels.first;
  String _year = '2026년';
  String _voyage = '01항차';
  String? _selectedId;
  bool _searched = false;

  // TODO: 실제 운영에서는 Supabase shipments 테이블에서 조회합니다.
  final List<Map<String, String>> _shipments = [
    {'id': '1', 'cargo': 'CG-001', 'box': 'BOX-001', 'invoice': 'LK-2026-001', 'name': '김철수', 'phone': '020-1111-2222', 'weight': '120', 'width': '50', 'length': '60', 'height': '70', 'receipt': 'RC-001', 'route': '한국->라오스 해상', 'year': '2026년', 'voyage': '01항차'},
    {'id': '2', 'cargo': 'CG-002', 'box': 'BOX-002', 'invoice': 'LK-2026-002', 'name': '이영희', 'phone': '020-3333-4444', 'weight': '45', 'width': '30', 'length': '40', 'height': '35', 'receipt': 'RC-002', 'route': '한국->라오스 항공', 'year': '2026년', 'voyage': '02항차'},
    {'id': '3', 'cargo': 'CG-003', 'box': 'BOX-003', 'invoice': 'LK-2026-003', 'name': '박민수', 'phone': '020-5555-6666', 'weight': '78', 'width': '40', 'length': '45', 'height': '50', 'receipt': 'RC-003', 'route': '라오스->한국 항공 특송', 'year': '2026년', 'voyage': '01항차'},
  ];

  bool get _isMember => widget.user.role == UserRole.member;
  bool get _isStaff => widget.user.role == UserRole.staff;
  bool get _isAdmin => widget.user.role == UserRole.admin;
  bool get _needsCargoNumber => !_isMember;
  bool get _canEditDirectly => !_isMember;
  List<Map<String, String>> get _results {
    final cargo = _cargoNo.text.trim().toLowerCase();
    final invoice = _invoiceSearch.text.trim().toLowerCase();
    final name = _nameSearch.text.trim().toLowerCase();
    final phone = _phoneSearch.text.trim().toLowerCase();
    return _shipments.where((item) =>
      (_route == '전체' || item['route'] == _route) &&
      (_year.isEmpty || item['year'] == _year) &&
      (_voyage.isEmpty || item['voyage'] == _voyage) &&
      (cargo.isEmpty || (item['cargo'] ?? '').toLowerCase().contains(cargo)) &&
      (invoice.isEmpty || (item['invoice'] ?? '').toLowerCase().contains(invoice)) &&
      (name.isEmpty || (item['name'] ?? '').toLowerCase().contains(name)) &&
      (phone.isEmpty || (item['phone'] ?? '').toLowerCase().contains(phone))
    ).toList();
  }

  @override
  void dispose() {
    for (final c in [_cargoNo, _invoiceSearch, _nameSearch, _phoneSearch, _boxNo, _invoice, _name, _phone, _weight, _width, _length, _height, _receipt, _note]) { c.dispose(); }
    super.dispose();
  }

  void _search() => setState(() { _searched = true; _selectedId = null; });

  void _select(Map<String, String> item) {
    setState(() {
      _selectedId = item['id'];
      _boxNo.text = item['box'] ?? '';
      _invoice.text = item['invoice'] ?? '';
      _name.text = item['name'] ?? '';
      _phone.text = item['phone'] ?? '';
      _weight.text = item['weight'] ?? '';
      _width.text = item['width'] ?? '';
      _length.text = item['length'] ?? '';
      _height.text = item['height'] ?? '';
      _receipt.text = item['receipt'] ?? '';
      _note.clear();
    });
  }

  void _checkFare() {
    if (_results.isEmpty) { _message('먼저 화물을 검색해 주세요.'); return; }
    _message('선택된 화물의 운임 확인 화면 연결 위치입니다.');
  }

  void _save() {
    if (_selectedId == null) return;
    final index = _shipments.indexWhere((item) => item['id'] == _selectedId);
    if (index < 0) return;
    final changes = <String, String>{
      'box': _boxNo.text.trim(), 'invoice': _invoice.text.trim(), 'name': _name.text.trim(), 'phone': _phone.text.trim(),
      'weight': _weight.text.trim(), 'width': _width.text.trim(), 'length': _length.text.trim(), 'height': _height.text.trim(), 'receipt': _receipt.text.trim(),
    };
    setState(() => _shipments[index].addAll(changes));
    if (_isMember) {
      // TODO: shipment_change_requests insert 후 관리자 승인 처리
      _message('화물 내용 수정 요청이 관리자에게 전송되었습니다.');
    } else {
      // TODO: Supabase shipments update(changes).eq('id', _selectedId)
      _message('화물 정보가 저장되어 적용되었습니다.');
    }
  }

  void _message(String text) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: AppColors.primary)); }
  InputDecoration _decoration(String label, IconData icon) => InputDecoration(labelText: label, prefixIcon: Icon(icon), filled: true, fillColor: AppColors.inputFill, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none));

  @override
  Widget build(BuildContext context) {
    final results = _searched ? _results : <Map<String, String>>[];
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (widget.onBack != null) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back), label: const Text('계정으로 돌아가기'))),
      Card(color: AppColors.primary, child: ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text(widget.user.name.isEmpty ? '회원' : widget.user.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), subtitle: Text(widget.user.roleLabel, style: const TextStyle(color: Colors.white70)))),
      const SizedBox(height: 16),
      Text(_isAdmin ? '통합 관리' : '화물 관리', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppColors.primary)),
      const SizedBox(height: 6),
      Text(_isMember ? '운송 경로·년도·항차와 세 가지 검색값을 입력해 화물을 찾습니다.' : '운송 경로·년도·항차와 화물 번호 또는 개별 검색값을 입력해 화물을 찾습니다.', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(value: _route, decoration: _decoration('운송 경로', Icons.route), items: routeLabels.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(), onChanged: (v) => setState(() => _route = v ?? _route)),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: DropdownButtonFormField<String>(value: _year, decoration: _decoration('년도', Icons.calendar_today), items: const ['2026년', '2027년', '2028년'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => _year = v ?? _year))), const SizedBox(width: 10), Expanded(child: DropdownButtonFormField<String>(value: _voyage, decoration: _decoration('항차', Icons.confirmation_number_outlined), items: const ['01항차', '02항차', '03항차', '04항차', '05항차'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => _voyage = v ?? _voyage)))]),
      const SizedBox(height: 10),
      if (_needsCargoNumber) ...[TextField(controller: _cargoNo, decoration: _decoration('화물 번호', Icons.inventory_2_outlined)), const SizedBox(height: 10)],
      Row(children: [Expanded(child: TextField(controller: _invoiceSearch, decoration: _decoration('송장번호', Icons.receipt_long_outlined))), const SizedBox(width: 8), Expanded(child: TextField(controller: _nameSearch, decoration: _decoration('이름', Icons.person_outline))), const SizedBox(width: 8), Expanded(child: TextField(controller: _phoneSearch, keyboardType: TextInputType.phone, decoration: _decoration('연락처', Icons.phone_outlined)))]),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: SizedBox(height: 46, child: ElevatedButton.icon(onPressed: _search, icon: const Icon(Icons.search), label: const Text('화물 검색'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white)))), const SizedBox(width: 10), Expanded(child: SizedBox(height: 46, child: ElevatedButton.icon(onPressed: _searched && results.isNotEmpty ? _checkFare : null, icon: const Icon(Icons.request_quote_outlined), label: const Text('운임 확인'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white))))]),
      if (_searched) ...[
        const SizedBox(height: 16),
        Text('검색된 화물 (${results.length}건)', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
        if (results.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('검색 결과가 없습니다.', style: TextStyle(color: AppColors.textSecondary))),
        ...results.map(_resultCard),
      ],
      if (_selectedId != null) ...[const SizedBox(height: 16), _editor()],
    ]);
  }

  Widget _resultCard(Map<String, String> item) => Card(child: InkWell(onTap: () => _select(item), child: Padding(padding: const EdgeInsets.all(12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Radio<String>(value: item['id']!, groupValue: _selectedId, onChanged: (_) => _select(item)), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('박스번호: ${item['box']}  ·  송장번호: ${item['invoice']}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)), const SizedBox(height: 5), Text('이름: ${item['name']}  ·  연락처: ${item['phone']}'), Text('중량: ${item['weight']}kg  ·  크기: ${item['width']} × ${item['length']} × ${item['height']}cm'), Text('영수증 번호: ${item['receipt']}', style: const TextStyle(color: AppColors.textSecondary))]))])));

  Widget _editor() {
    final editableBasic = _isMember || _canEditDirectly;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_isMember ? '선택한 화물 상세 및 수정 요청' : '선택한 화물 내용 수정', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
      const SizedBox(height: 8),
      if (!_isMember) TextField(controller: _boxNo, decoration: _decoration('박스번호', Icons.inventory_2_outlined)),
      if (!_isMember) const SizedBox(height: 10),
      if (_isAdmin || widget.user.role == UserRole.partner) TextField(controller: _invoice, decoration: _decoration('송장번호', Icons.receipt_long_outlined)),
      if (_isAdmin || widget.user.role == UserRole.partner) const SizedBox(height: 10),
      TextField(controller: _name, readOnly: !editableBasic, decoration: _decoration('이름', Icons.person_outline)),
      const SizedBox(height: 10),
      TextField(controller: _phone, readOnly: !editableBasic, keyboardType: TextInputType.phone, decoration: _decoration('연락처', Icons.phone_outlined)),
      const SizedBox(height: 10),
      if (!_isMember) ...[
        Row(children: [Expanded(child: TextField(controller: _weight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _decoration('중량(kg)', Icons.monitor_weight_outlined))), const SizedBox(width: 8), Expanded(child: TextField(controller: _width, keyboardType: TextInputType.number, decoration: _decoration('가로(cm)', Icons.straighten))),]),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: TextField(controller: _length, keyboardType: TextInputType.number, decoration: _decoration('세로(cm)', Icons.straighten))), const SizedBox(width: 8), Expanded(child: TextField(controller: _height, keyboardType: TextInputType.number, decoration: _decoration('높이(cm)', Icons.height))),]),
        const SizedBox(height: 10),
      ],
      if (_isMember) TextField(controller: _note, maxLines: 3, decoration: _decoration('기타 추가 상세 내용', Icons.edit_note_outlined)),
      if (_isAdmin) TextField(controller: _receipt, decoration: _decoration('영수증 번호', Icons.receipt_outlined)),
      const SizedBox(height: 14),
      SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(onPressed: _save, icon: Icon(_isMember ? Icons.send : Icons.save), label: Text(_isMember ? '화물 내용 수정 요청' : _isStaff ? '화물 내용 수정 및 데이타 입력' : '화물 내용 수정'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white))),
    ]);
  }
}


