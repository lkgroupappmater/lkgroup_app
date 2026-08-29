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
  final _kipAdjustment = TextEditingController();
  final _thbAdjustment = TextEditingController();
  final _krwAdjustment = TextEditingController();
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
      _kipAdjustment.text = _trim(value.kipAdjustment);
      _thbAdjustment.text = _trim(value.thbAdjustment);
      _krwAdjustment.text = _trim(value.krwAdjustment);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _trim(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  double? _number(TextEditingController controller) =>
      double.tryParse(controller.text.replaceAll(',', '').trim());

  Future<void> _save() async {
    final kip = _number(_kip);
    final thb = _number(_thb);
    final krw = _number(_krw);
    final kipAdjustment = _number(_kipAdjustment);
    final thbAdjustment = _number(_thbAdjustment);
    final krwAdjustment = _number(_krwAdjustment);

    if (kip == null ||
        thb == null ||
        krw == null ||
        kipAdjustment == null ||
        thbAdjustment == null ||
        krwAdjustment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기준 환율과 운임 확인 적용 환율 보정을 모두 숫자로 입력해 주세요.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await ExchangeRateService.instance.save(
        baseKip: kip,
        baseThb: thb,
        baseKrw: krw,
        kipAdjustment: kipAdjustment,
        thbAdjustment: thbAdjustment,
        krwAdjustment: krwAdjustment,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기준 환율 및 운임 확인 적용 환율 보정을 저장했습니다.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _kip.dispose();
    _thb.dispose();
    _krw.dispose();
    _kipAdjustment.dispose();
    _thbAdjustment.dispose();
    _krwAdjustment.dispose();
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

  Widget _rateRow({
    required TextEditingController base,
    required TextEditingController adjustment,
    required String baseLabel,
    required String suffix,
  }) =>
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: base,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _decoration(baseLabel, suffix),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: adjustment,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _decoration('환율 보정', suffix),
            ),
          ),
        ],
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
              '현찰 살 때 기준 환율과 운임 확인 적용 환율 보정을 입력합니다.',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            const Text(
              '운임 확인 적용 환율 = 기준 환율 + 운임 확인 적용 환율 보정',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            _rateRow(
              base: _kip,
              adjustment: _kipAdjustment,
              baseLabel: '기준 킵',
              suffix: 'KIP',
            ),
            const SizedBox(height: 12),
            _rateRow(
              base: _thb,
              adjustment: _thbAdjustment,
              baseLabel: '기준 바트',
              suffix: 'THB',
            ),
            const SizedBox(height: 12),
            _rateRow(
              base: _krw,
              adjustment: _krwAdjustment,
              baseLabel: '기준 원화',
              suffix: 'KRW',
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
