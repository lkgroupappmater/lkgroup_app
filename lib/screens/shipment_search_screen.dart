// lib/screens/shipment_search_screen.dart
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../config/supabase_config.dart';
import '../services/shipment_service.dart';

// ---------------------------------------------------------------------------
// Route categories
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Mock shipment data
// TODO: Replace with real data from admin Excel upload / DB API.
// ---------------------------------------------------------------------------
final List<Map<String, dynamic>> _mockShipments = [
  {
    'boxNo': 'BX-0012',
    'invoice': 'INV-2025-0701',
    'name': 'Somsak Khamvongsa',
    'phone': '020-5551-2345',
    'arrival': '2025-07-05',
    'route': '한국->라오스 해상',
  },
  {
    'boxNo': 'BX-0013',
    'invoice': 'INV-2025-0702',
    'name': 'Phonevilay Nanthavong',
    'phone': '020-5551-6789',
    'arrival': '2025-07-06',
    'route': '한국->라오스 항공',
  },
  {
    'boxNo': 'BX-0014',
    'invoice': 'INV-2025-0703',
    'name': 'Bounmy Phommasack',
    'phone': '021-3334-5678',
    'arrival': '2025-07-07',
    'route': '라오스->한국 항공 특송',
  },
  {
    'boxNo': 'BX-0015',
    'invoice': 'INV-2025-0704',
    'name': 'Khamla Vongsay',
    'phone': '020-7778-9012',
    'arrival': '2025-07-08',
    'route': '라오스->태국 육로',
  },
];

// ---------------------------------------------------------------------------
// Body-only widget
// ---------------------------------------------------------------------------
class ShipmentSearchBody extends StatefulWidget {
  const ShipmentSearchBody({
    super.key,
    this.language = AppLanguage.korean,
    this.isLoggedIn = false,
    this.onRequireLogin,
    this.onEditRequest,
    this.onManageSelected,
  });

  final AppLanguage language;
  final bool isLoggedIn;
  final VoidCallback? onRequireLogin;
  final VoidCallback? onEditRequest;
  final ValueChanged<List<String>>? onManageSelected;

  @override
  State<ShipmentSearchBody> createState() => _ShipmentSearchBodyState();
}

class _ShipmentSearchBodyState extends State<ShipmentSearchBody> {
  int _selectedRoute = 0;
  final _invoiceCtrl = TextEditingController();
  final _recipientCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  List<Map<String, dynamic>> _results = [];
  bool _searched = false;
  final Set<String> _selectedInvoices = <String>{};

  @override
  void dispose() {
    _invoiceCtrl.dispose();
    _recipientCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final invoice = _invoiceCtrl.text.trim();
    final recipient = _recipientCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final route = _routeCategories[_selectedRoute];
    try {
      final dbRows = await ShipmentService.instance.searchRows(
        route: route, invoice: invoice, recipient: recipient, phone: phone,
      );
      final results = dbRows.isEmpty && !SupabaseConfig.isConfigured
          ? _mockShipments
          : dbRows.map((row) => <String, dynamic>{
              'boxNo': row['box_number'] ?? '',
              'invoice': row['invoice_number'] ?? row['shipment_no'] ?? '',
              'name': row['consignee_name'] ?? '',
              'phone': row['consignee_phone'] ?? '',
              'arrival': row['received_at'] ?? '',
              'route': row['route'] ?? '',
            }).toList();
      setState(() { _results = results; _searched = true; _selectedInvoices.clear(); });
    } catch (error) {
      setState(() { _results = _mockShipments; _searched = true; _selectedInvoices.clear(); });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('화물 조회 실패: $error')));
    }
  }

  void _toggleSelected(String invoice) {
    setState(() {
      if (!_selectedInvoices.remove(invoice)) _selectedInvoices.add(invoice);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoggedIn) {
      return _LoginRequiredView(onLogin: widget.onRequireLogin);
    }
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        children: [
          // Route category dropdown (견적 화면의 운송 경로 선택 방식과 동일한 풀다운 메뉴)
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
              focusedBorder: OutlineInputBorder(
                borderSide:
                    const BorderSide(color: AppColors.accent, width: 1.5),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            items: List.generate(
              _routeCategories.length,
              (index) => DropdownMenuItem<int>(
                value: index,
                child: Text(_routeCategories[index]),
              ),
            ),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedRoute = value);
              }
            },
          ),
          const SizedBox(height: 14),

          // Search inputs
          _buildInput(_invoiceCtrl, '송장번호', Icons.tag_rounded),
          const SizedBox(height: 10),
          _buildInput(_recipientCtrl, '라오스 수령인', Icons.person_outline),
          const SizedBox(height: 10),
          _buildInput(_phoneCtrl, '라오스 전화번호', Icons.phone_outlined,
              keyboardType: TextInputType.phone),
          const SizedBox(height: 16),

          // Search button
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _search,
              icon: const Icon(Icons.search_rounded, size: 20),
              label: const Text('검색',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navyPrimary,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          if (_searched && _results.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _selectedInvoices.isEmpty || widget.onManageSelected == null
                    ? null
                    : () => widget.onManageSelected!(_selectedInvoices.toList()),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('화물 관리'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('운임 확인 화면 연결 위치입니다.'))),
                icon: const Icon(Icons.price_check_outlined),
                label: const Text('운임 확인'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.white),
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Results
          if (_searched)
            _ResultsList(
                results: _results,
                selectedInvoices: _selectedInvoices,
                onToggle: _toggleSelected,
                onEditRequest: widget.onEditRequest),
        ],
      ),
    );
  }

  Widget _buildInput(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 13),
        prefixIcon: Icon(icon, size: 20, color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Route chips
// ---------------------------------------------------------------------------
class _RouteChips extends StatelessWidget {
  const _RouteChips({required this.selected, required this.onSelected});
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(_routeCategories.length, (i) {
          final active = selected == i;
          return Padding(
            padding: EdgeInsets.only(right: 8, left: i == 0 ? 0 : 0),
            child: ChoiceChip(
              label: Text(_routeCategories[i]),
              selected: active,
              onSelected: (_) => onSelected(i),
              selectedColor: AppColors.navyPrimary,
              backgroundColor: AppColors.inputFill,
              labelStyle: TextStyle(
                color: active ? AppColors.white : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              ),
              side: BorderSide(
                color: active ? AppColors.navyPrimary : AppColors.cardBorder,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        }),
      ),
    );
  }
}

class _LoginRequiredView extends StatelessWidget {
  const _LoginRequiredView({this.onLogin});
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline,
                size: 58, color: AppColors.navyPrimary),
            const SizedBox(height: 14),
            const Text('로그인 후 화물 조회가 가능합니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navyPrimary)),
            const SizedBox(height: 8),
            const Text('다른 회원의 화물 정보 보호를 위해 로그인 후 검색해 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.45)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login),
              label: const Text('로그인 하기'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navyPrimary,
                  foregroundColor: AppColors.white),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Results list
// ---------------------------------------------------------------------------
class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.results, required this.selectedInvoices, required this.onToggle, this.onEditRequest});
  final List<Map<String, dynamic>> results;
  final Set<String> selectedInvoices;
  final ValueChanged<String> onToggle;
  final VoidCallback? onEditRequest;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Center(
        child: Column(
          children: [
            const Icon(Icons.inbox_outlined,
                size: 48, color: AppColors.textHint),
            const SizedBox(height: 8),
            const Text('검색 결과가 없습니다.',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            const Text('송장번호, 수령인, 전화번호를 확인해 주세요.',
                style: TextStyle(fontSize: 12, color: AppColors.textHint)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('검색 결과 ${results.length}건',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        ...results.map((r) => _ResultCard(
              data: r,
              selected: selectedInvoices.contains(r['invoice']),
              onToggle: () => onToggle(r['invoice'] as String),
              onEditRequest: onEditRequest,
            )),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.data, required this.selected, required this.onToggle, this.onEditRequest});
  final Map<String, dynamic> data;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback? onEditRequest;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(value: selected, onChanged: (_) => onToggle(), activeColor: AppColors.primary),
              const Icon(Icons.inventory_2_outlined,
                  size: 16, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(data['boxNo'] as String,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navyPrimary)),
              const Spacer(),
              Text(data['route'] as String,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
          const Divider(height: 14, color: AppColors.divider),
          _Row('송장번호', data['invoice'] as String),
          _Row('이름', data['name'] as String),
          _Row('연락처', data['phone'] as String),
          _Row('입고 날짜', data['arrival'] as String),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Legacy wrapper
// ---------------------------------------------------------------------------
class ShipmentSearchScreen extends StatelessWidget {
  const ShipmentSearchScreen({super.key, this.language = AppLanguage.korean});
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navyPrimary,
        foregroundColor: AppColors.white,
        title: Text(AppStrings.get(language, 'tracking'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: ShipmentSearchBody(language: language),
    );
  }
}
