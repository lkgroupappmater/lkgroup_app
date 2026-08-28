import '../config/supabase_config.dart';
import 'supabase_service.dart';

class ExchangeRateSettings {
  const ExchangeRateSettings({
    required this.baseKip,
    required this.baseThb,
    required this.baseKrw,
    this.kipAdjustment = 2000,
    this.thbAdjustment = 1.5,
    this.krwAdjustment = 40,
  });

  final double baseKip;
  final double baseThb;
  final double baseKrw;
  final double kipAdjustment;
  final double thbAdjustment;
  final double krwAdjustment;

  double get appliedKip => baseKip + kipAdjustment;
  double get appliedThb => baseThb + thbAdjustment;
  double get appliedKrw => baseKrw + krwAdjustment;

  factory ExchangeRateSettings.fromMap(Map<String, dynamic> map) =>
      ExchangeRateSettings(
        baseKip: _d(map['base_kip']),
        baseThb: _d(map['base_thb']),
        baseKrw: _d(map['base_krw']),
        kipAdjustment: _d(map['kip_adjustment'], 2000),
        thbAdjustment: _d(map['thb_adjustment'], 1.5),
        krwAdjustment: _d(map['krw_adjustment'], 40),
      );

  static double _d(dynamic value, [double fallback = 0]) =>
      double.tryParse('${value ?? ''}') ?? fallback;
}

class ExchangeRateService {
  ExchangeRateService._();
  static final ExchangeRateService instance = ExchangeRateService._();

  Future<ExchangeRateSettings> fetch() async {
    if (!SupabaseConfig.isConfigured) {
      return const ExchangeRateSettings(baseKip: 0, baseThb: 0, baseKrw: 0);
    }
    final rows = await SupabaseService.client
        .from('exchange_rate_settings')
        .select()
        .eq('id', 1)
        .limit(1);
    if (rows.isEmpty) {
      return const ExchangeRateSettings(baseKip: 0, baseThb: 0, baseKrw: 0);
    }
    return ExchangeRateSettings.fromMap(Map<String, dynamic>.from(rows.first));
  }

  Future<void> save({
    required double baseKip,
    required double baseThb,
    required double baseKrw,
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client.from('exchange_rate_settings').upsert({
      'id': 1,
      'base_kip': baseKip,
      'base_thb': baseThb,
      'base_krw': baseKrw,
      'kip_adjustment': 2000,
      'thb_adjustment': 1.5,
      'krw_adjustment': 40,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}
