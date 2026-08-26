// lib/screens/shipment_search_screen.dart
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';

const List<String> _routeCategories = [
  '전체',
  '한국->라오스 해상',
  '한국->라오스 항공',
  '라오스->한국 항공 특송',
  '라오스->태국 육로',
  '라오스->베트남 육로',
  '라오스->중국 육로',
  '라오스->캄보디아 육로',
];

final List<Map<String, dynamic>> _mockShipments = [
  {
    'boxNo': 'BX-0012',
    'invoice': 'INV-2025-0701',
    'name': 'Somsak Khamvongsa',
    'phone': '020-5551-2345',
    'arrival': '2025-07-05',
    'route': '한국->라오스 해상',
    'year': '2025년',
    'voyage': '01항차',
  },
  {
    'boxNo': 'BX-0013',
    'invoice': 'INV-2025-0702',
    'name': 'Phonevilay Nanthavong',
    'phone': '020-5551-6789',
    'arrival': '2025-07-06',
    'route': '한국->라오스 항공',
    'year': '2025년',
    'voyage': '02항차',
  },
  {
    'boxNo': 'BX-0014',
    'invoice': 'INV-2025-0703',
    'name': 'Bounmy Phommasack',
    'phone': '021-3334-5678',
    'arrival': '2025-07-07',
    'route': '라오스->한국 항공 특송',
    'year': '2025년',
    'voyage': '01항차',
  },
  {
    'boxNo': 'BX-0015',
    'invoice': 'INV-2025-0704',
    'name': 'Khamla Vongsay',
    'phone': '020-7778-9012',
    'arrival': '2025-07-08',
    'route': '라오스->태국 육로',
    'year': '2025년',
    'voyage': '03항차',
  },
];

class ShipmentSearchBody extends StatefulWidget {
  const ShipmentSearchBody({
    super.key,
    this.language = AppLanguage.korean,
    this.isLoggedIn = false,
    this.onRequireLogin,
    this.onCargoManagement,
  });
  final AppLanguage language;
  final bool isLoggedIn;
  final VoidCallback? onRequireLogin;
  final ValueChanged<List<Map<String, dynamic>>>? onCargoManagement;

  @override
  State<ShipmentSearchBody> createState() => _ShipmentSearchBodyState();
}

class _ShipmentSearchBodyState extends State<ShipmentSearchBody> {
  int _selectedRoute = 0;
  String _selectedYear = '전체';
  String _selectedVoyage = '전체';
  final _invoiceCtrl = TextEditingController();
  final _recipientCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final Set<String> _selectedBoxNos = <String>{};
  List<Map<String, dynamic>> _results = [];
  bool _searched = false;

  @override
  void dispose() {
    _invoiceCtrl.dispose();
    _recipientCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _search() {
    // TODO: Replace with real Supabase / Excel-upload API search.
    final invoice = _invoiceCtrl.text.trim().toLowerCase();
    final recipient = _recipientCtrl.text.trim().toLowerCase();
    final phone = _phoneCtrl.text.trim();
    final route = _routeCategories[_selectedRoute];
    final results = _mockShipments.where((s) {
      final routeMatch = route == '전체' || s['route'] == route;
      final yearMatch = _selectedYear == '전체' || s['year'] == _selectedYear;
      final voyageMatch = _selectedVoyage == '전체' || s['voyage'] == _selectedVoyage;
      final invoiceMatch = invoice.isEmpty || (s['invoice'] as String).toLowerCase().contains(invoice);
      final recipientMatch = recipient.isEmpty || (s['name'] as String).toLowerCase().contains(recipient);
      final phoneMatch = phone.isEmpty || (s['phone'] as String).contains(phone);
      return routeMatch && yearMatch && voyageMatch && invoiceMatch && recipientMatch && phoneMatch;
    }).toList();
    setState(() {
      _results = results;
      _searched = true;
      _selectedBoxNos.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoggedIn) return _LoginRequiredView(onLogin: widget.onRequireLogin);
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
              prefixIcon: const Icon(Icons.route_outlined, color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.inputFill,
              border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppColors.accent, width: 1.5), borderRadius: BorderRadius.circular(10)),
            ),
            items: List.generate(_routeCategories.length, (index) => DropdownMenuItem<int>(value: index, child: Text(_routeCategories[index]))),
            onChanged: (value) { if (value != null) setState(() => _selectedRoute = value); },
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _filterDropdown('년도', _selectedYear, const ['전체', '2025년', '2026년', '2027년', '2028년'], (v) => setState(() => _selectedYear = v))),
            const SizedBox(width: 10),
            Expanded(child: _filterDropdown('항차', _selectedVoyage, const ['전체', '01항차', '02항차', '03항차', '04항차', '05항차'], (v) => setState(() => _selectedVoyage = v))),
          ]),
          const SizedBox(height: 14),
          _buildInput(_invoiceCtrl, '송장번호', Icons.tag_rounded),
          const SizedBox(height: 10),
          _buildInput(_recipientCtrl, '라오스 수령인', Icons.person_outline),
          const SizedBox(height: 10),
          _buildInput(_phoneCtrl, '라오스 전화번호', Icons.phone_outlined, keyboardType: TextInputType.phone),
          const SizedBox(height: 16),
          SizedBox(height: 48, child: ElevatedButton.icon(onPressed: _search, icon: const Icon(Icons.search_rounded, size: 20), label: const Text('검색', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)), style: ElevatedButton.styleFrom(backgroundColor: AppColors.navyPrimary, foregroundColor: AppColors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
          const SizedBox(height: 20),
          if (_searched) _ResultsList(results: _results, selectedBoxNos: _selectedBoxNos, onToggle: (boxNo) => setState(() => _selectedBoxNos.contains(boxNo) ? _selectedBoxNos.remove(boxNo) : _selectedBoxNos.add(boxNo)), onCargoManagement: widget.onCargoManagement),
        ],
      ),
    );
  }

  Widget _filterDropdown(String label, String value, List<String> values, ValueChanged<String> onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, filled: true, fillColor: AppColors.inputFill, border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(10))),
      items: values.map((item) => DropdownMenuItem<String>(value: item, child: Text(item))).toList(),
      onChanged: (item) { if (item != null) onChanged(item); },
    );
  }

  Widget _buildInput(TextEditingController ctrl, String hint, IconData icon, {TextInputType keyboardType = TextInputType.text}) {
    return TextField(controller: ctrl, keyboardType: keyboardType, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary), decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 13), prefixIcon: Icon(icon, size: 20, color: AppColors.textSecondary), filled: true, fillColor: AppColors.inputFill, border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(10)), focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppColors.accent, width: 1.5), borderRadius: BorderRadius.circular(10)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)));
  }
}

class _LoginRequiredView extends StatelessWidget {
  const _LoginRequiredView({this.onLogin});
  final VoidCallback? onLogin;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.lock_outline, size: 58, color: AppColors.navyPrimary), const SizedBox(height: 14), const Text('로그인 후 화물 조회가 가능합니다.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.navyPrimary)), const SizedBox(height: 8), const Text('다른 회원의 화물 정보 보호를 위해 로그인 후 검색해 주세요.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.45)), const SizedBox(height: 20), ElevatedButton.icon(onPressed: onLogin, icon: const Icon(Icons.login), label: const Text('로그인 하기'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.navyPrimary, foregroundColor: AppColors.white))])));
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.results, required this.selectedBoxNos, required this.onToggle, this.onCargoManagement});
  final List<Map<String, dynamic>> results;
  final Set<String> selectedBoxNos;
  final ValueChanged<String> onToggle;
  final ValueChanged<List<Map<String, dynamic>>>? onCargoManagement;
  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const Center(child: Text('검색 결과가 없습니다.', style: TextStyle(color: AppColors.textSecondary)));
    final selectedItems = results.where((item) => selectedBoxNos.contains(item['boxNo'])).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('검색 결과 ${results.length}건', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)), const SizedBox(height: 8), ...results.map((r) => _ResultCard(data: r, selected: selectedBoxNos.contains(r['boxNo']), onToggle: onToggle)), if (onCargoManagement != null) Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(onPressed: selectedItems.isEmpty ? null : () => onCargoManagement!(selectedItems), icon: const Icon(Icons.inventory_2_outlined, size: 18), label: const Text('화물 관리'), style: OutlinedButton.styleFrom(foregroundColor: AppColors.navyPrimary, side: const BorderSide(color: AppColors.navyPrimary))))]);
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.data, required this.selected, required this.onToggle});
  final Map<String, dynamic> data;
  final bool selected;
  final ValueChanged<String> onToggle;
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Checkbox(value: selected, onChanged: (_) => onToggle(data['boxNo'] as String)), const Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.accent), const SizedBox(width: 6), Text(data['boxNo'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.navyPrimary)), const Spacer(), Text(data['route'] as String, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))]), const Divider(height: 14, color: AppColors.divider), _Row('송장번호', data['invoice'] as String), _Row('이름', data['name'] as String), _Row('연락처', data['phone'] as String), _Row('입고 날짜', data['arrival'] as String)]));
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [SizedBox(width: 72, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))), Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)))]));
}

class ShipmentSearchScreen extends StatelessWidget {
  const ShipmentSearchScreen({super.key, this.language = AppLanguage.korean});
  final AppLanguage language;
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.background, appBar: AppBar(backgroundColor: AppColors.navyPrimary, foregroundColor: AppColors.white, title: Text(AppStrings.get(language, 'tracking'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)), elevation: 0), body: ShipmentSearchBody(language: language));
}
