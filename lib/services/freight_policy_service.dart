import '../config/supabase_config.dart';
import 'supabase_service.dart';

class FreightRateTier {
  const FreightRateTier({
    required this.minWeightKg,
    required this.ratePerKg,
  });

  final double minWeightKg;
  final double ratePerKg;
}

class FreightPolicy {
  const FreightPolicy({
    required this.routeKey,
    required this.minimumCharge,
    required this.volumetricFactor,
    required this.tiers,
    required this.sourceNote,
  });

  final String routeKey;
  final double minimumCharge;
  final double volumetricFactor;
  final List<FreightRateTier> tiers;
  final String sourceNote;

  double rateFor(double chargeableWeight) {
    if (tiers.isEmpty) return 0;
    var result = tiers.first.ratePerKg;
    for (final tier in tiers) {
      if (chargeableWeight >= tier.minWeightKg) {
        result = tier.ratePerKg;
      } else {
        break;
      }
    }
    return result;
  }
}

class FreightPolicyService {
  FreightPolicyService._();
  static final instance = FreightPolicyService._();

  Future<FreightPolicy> fetch(String routeKey) async {
    if (!SupabaseConfig.isConfigured) {
      throw StateError('Supabase 운임 정책을 불러올 수 없습니다.');
    }

    final raw = await SupabaseService.client
        .from('freight_rate_tiers')
        .select(
          'min_weight_kg,rate_per_kg,minimum_charge,volumetric_factor,source_note',
        )
        .eq('route_key', routeKey)
        .eq('active', true)
        .order('min_weight_kg');

    final rows = raw.map(Map<String, dynamic>.from).toList(growable: false);
    if (rows.isEmpty) {
      throw StateError('해당 운송 경로의 DB 기준 운임 정책이 없습니다.');
    }

    final first = rows.first;
    return FreightPolicy(
      routeKey: routeKey,
      minimumCharge: _d(first['minimum_charge']),
      volumetricFactor: _d(first['volumetric_factor'], 0.00022),
      sourceNote: '${first['source_note'] ?? ''}',
      tiers: rows
          .map(
            (row) => FreightRateTier(
              minWeightKg: _d(row['min_weight_kg']),
              ratePerKg: _d(row['rate_per_kg']),
            ),
          )
          .toList(growable: false),
    );
  }

  static double _d(dynamic value, [double fallback = 0]) =>
      double.tryParse('${value ?? ''}'.trim()) ?? fallback;
}
