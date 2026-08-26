// lib/screens/quote_request_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../core/route_catalog.dart';

// ---------------------------------------------------------------------------
// Route options for dropdown
// ---------------------------------------------------------------------------
final List<String> _transportRoutes = RouteCatalog.routes;

// ---------------------------------------------------------------------------
// Box data model (local)
// ---------------------------------------------------------------------------
class _BoxEntry {
  String weight   = '';
  String width    = '';
  String length   = '';
  String height   = '';
  String quantity = '1';

  _BoxEntry();
}

// ---------------------------------------------------------------------------
// Body-only widget
// ---------------------------------------------------------------------------
class QuoteRequestBody extends StatefulWidget {
  const QuoteRequestBody({
    super.key,
    this.language = AppLanguage.korean,
    this.onRequestLogin,
  });

  final AppLanguage language;
  /// Callback invoked when a guest presses "회원 로그인" inside the dialog.
  final VoidCallback? onRequestLogin;

  @override
  State<QuoteRequestBody> createState() => _QuoteRequestBodyState();
}

class _QuoteRequestBodyState extends State<QuoteRequestBody> {
  String _selectedRoute = _transportRoutes.first;
  final List<_BoxEntry> _boxes = [_BoxEntry()];

  // Simulated login state
  // TODO: Replace with real AuthController.isLoggedIn
  bool _isLoggedIn = false;

  void _addBox() => setState(() => _boxes.add(_BoxEntry()));
  void _removeBox(int i) {
    if (_boxes.length > 1) setState(() => _boxes.removeAt(i));
  }

  void _requestQuote() {
    // TODO: Connect to real freight rate / quote API endpoint.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('운임 확인 요청이 접수되었습니다. 곧 안내드리겠습니다.'),
        backgroundColor: AppColors.navyPrimary,
      ),
    );
  }

  void _requestSpecialQuote() {
    if (!_isLoggedIn) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('로그인 필요'),
          content: const Text(
              '대량·특수 견적 요청은 회원 로그인 후 이용하실 수 있습니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navyPrimary,
                  foregroundColor: AppColors.white),
              onPressed: () {
                Navigator.pop(context);
                widget.onRequestLogin?.call();
              },
              child: const Text('회원 로그인'),
            ),
          ],
        ),
      );
      return;
    }
    // TODO: Navigate to special / bulk quote form.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('특수 견적 요청 화면 준비 중입니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // Route selector
          _SectionLabel('운송 경로 선택'),
          const SizedBox(height: 8),
          _RouteDropdown(
            value: _selectedRoute,
            items: _transportRoutes,
            onChanged: (v) {
              if (v != null) setState(() => _selectedRoute = v);
            },
          ),
          const SizedBox(height: 18),

          // Box entries
          _SectionLabel('박스 정보 입력'),
          const SizedBox(height: 8),
          ..._boxes.asMap().entries.map(
                (e) => _BoxRow(
              index: e.key,
              entry: e.value,
              canDelete: _boxes.length > 1,
              onDelete: () => _removeBox(e.key),
            ),
          ),
          const SizedBox(height: 8),

          // Add box button
          OutlinedButton.icon(
            onPressed: _addBox,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('박스 추가',
                style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.navyPrimary,
              side: const BorderSide(color: AppColors.navyPrimary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 20),

          // Quote button
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _requestQuote,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navyPrimary,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('운임 확인',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),

          // Special quote button
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _requestSpecialQuote,
              icon: const Icon(Icons.star_outline, size: 18),
              label: const Text('대량 혹은 특수 견적 요청',
                  style: TextStyle(fontSize: 14)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.tagOrange,
                side: const BorderSide(color: AppColors.tagOrange),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),

          // Mock login toggle for testing
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: _isLoggedIn,
                activeColor: AppColors.navyPrimary,
                onChanged: (v) =>
                    setState(() => _isLoggedIn = v ?? false),
              ),
              const Text('[테스트] 로그인 상태로 전환',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Route dropdown
// ---------------------------------------------------------------------------
class _RouteDropdown extends StatelessWidget {
  const _RouteDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded,
              color: AppColors.textSecondary),
          style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500),
          items: items
              .map((r) => DropdownMenuItem(value: r, child: Text(r)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Box row (horizontally scrollable on narrow screens)
// ---------------------------------------------------------------------------
class _BoxRow extends StatelessWidget {
  const _BoxRow({
    required this.index,
    required this.entry,
    required this.canDelete,
    required this.onDelete,
  });

  final int index;
  final _BoxEntry entry;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('박스 ${index + 1}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navyPrimary)),
              const Spacer(),
              if (canDelete)
                InkWell(
                  onTap: onDelete,
                  child: const Icon(Icons.remove_circle_outline,
                      size: 18, color: AppColors.error),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Horizontally scrollable row for narrow screens
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _CompactField(
                  label: '무게(kg)',
                  initial: entry.weight,
                  onChanged: (v) => entry.weight = v,
                  width: 72,
                  inputType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(width: 6),
                _CompactField(
                  label: '가로(cm)',
                  initial: entry.width,
                  onChanged: (v) => entry.width = v,
                  width: 72,
                  inputType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(width: 6),
                _CompactField(
                  label: '세로(cm)',
                  initial: entry.length,
                  onChanged: (v) => entry.length = v,
                  width: 72,
                  inputType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(width: 6),
                _CompactField(
                  label: '높이(cm)',
                  initial: entry.height,
                  onChanged: (v) => entry.height = v,
                  width: 72,
                  inputType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(width: 6),
                _CompactField(
                  label: '수량',
                  initial: entry.quantity,
                  onChanged: (v) => entry.quantity = v,
                  width: 60,
                  inputType: TextInputType.number,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactField extends StatelessWidget {
  const _CompactField({
    required this.label,
    required this.initial,
    required this.onChanged,
    required this.width,
    required this.inputType,
  });

  final String label;
  final String initial;
  final ValueChanged<String> onChanged;
  final double width;
  final TextInputType inputType;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
          const SizedBox(height: 3),
          TextFormField(
            initialValue: initial,
            keyboardType: inputType,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
            ],
            onChanged: onChanged,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textPrimary),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.inputFill,
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(6),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(
                    color: AppColors.accent, width: 1.2),
                borderRadius: BorderRadius.circular(6),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary));
  }
}

// ---------------------------------------------------------------------------
// Legacy wrapper
// ---------------------------------------------------------------------------
class QuoteRequestScreen extends StatelessWidget {
  const QuoteRequestScreen({
    super.key,
    this.language = AppLanguage.korean,
    this.onRequestLogin,
  });

  final AppLanguage language;
  final VoidCallback? onRequestLogin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navyPrimary,
        foregroundColor: AppColors.white,
        title: Text(AppStrings.get(language, 'quote'),
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: QuoteRequestBody(
        language: language,
        onRequestLogin: onRequestLogin,
      ),
    );
  }
}



