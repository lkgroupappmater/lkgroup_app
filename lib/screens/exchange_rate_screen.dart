import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../services/exchange_rate_service.dart';

class ExchangeRateScreen extends StatefulWidget {
  const ExchangeRateScreen({super.key});

  @override
  State<ExchangeRateScreen> createState() => _ExchangeRateScreenState();
}

class _ExchangeRateScreenState extends State<ExchangeRateScreen> {
  final _kip = TextEditingController();
  final _thb = TextEditingController();
  final _krw = TextEditingController();
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await ExchangeRateService.instance.fetch();
      _kip.text = value.baseKip == 0 ? '' : value.baseKip.toStringAsFixed(0);
      _thb.text = value.baseThb == 0 ? '' : _trim(value.baseThb);
      _krw.text = value.baseKrw == 0 ? '' : _trim(value.baseKrw);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _trim(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  Future<void> _save() async {
    final kip = double.tryParse(_kip.text.replaceAll(',', '').trim());
    final thb = double.tryParse(_thb.text.replaceAll(',', '').trim());
    final krw = double.tryParse(_krw.text.replaceAll(',', '').trim());
    if (kip == null || thb == null || krw == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기준 환율 3개를 모두 숫자로 입력해 주세요.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ExchangeRateService.instance
          .save(baseKip: kip, baseThb: thb, baseKrw: krw);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('기준 환율을 저장했습니다.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _kip.dispose();
    _thb.dispose();
    _krw.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, String suffix) => InputDecoration(
        labelText: label,
        suffixText: suffix,
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('기준 환율 입력'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        backgroundColor: AppColors.background,
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '현찰 살 때 기준 환율을 입력합니다.',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            const Text(
              '운임 확인 적용환율: USD-KIP = 기준 + 2,000 / USD-THB = 기준 + 1.5 / USD-KRW = 기준 + 40',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _kip,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _decoration('기준 킵', 'KIP'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _thb,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _decoration('기준 바트', 'THB'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _krw,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _decoration('기준 원화', 'KRW'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_busy ? '처리 중...' : '기준 환율 저장'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
}
