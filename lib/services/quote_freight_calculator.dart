import '../core/route_catalog.dart';
import 'supabase_service.dart';

class QuoteBoxInput {
  const QuoteBoxInput({
    required this.index,
    required this.weightKg,
    required this.lengthCm,
    required this.widthCm,
    required this.heightCm,
    required this.quantity,
    this.boxPacking = false,
  });
  final int index;
  final double weightKg, lengthCm, widthCm, heightCm;
  final int quantity;
  final bool boxPacking;
}

class QuoteBoxFreightResult {
  const QuoteBoxFreightResult({
    required this.index,
    required this.actualWeightKg,
    required this.volumeWeightKg,
    required this.chargeableWeightKg,
    required this.ratePerKg,
    required this.quantity,
    required this.amountUsd,
    required this.movingCargoSurchargeUsd,
    required this.boxPackingSurchargeUsd,
  });
  final int index, quantity;
  final double actualWeightKg, volumeWeightKg, chargeableWeightKg, ratePerKg;
  final double amountUsd, movingCargoSurchargeUsd, boxPackingSurchargeUsd;
}

class QuoteFreightResult {
  const QuoteFreightResult({
    required this.route,
    required this.lines,
    required this.totalUsd,
    required this.sourceFile,
  });
  final String route, sourceFile;
  final List<QuoteBoxFreightResult> lines;
  final double totalUsd;
}

class QuoteFreightCalculator {
  QuoteFreightCalculator._();

  static bool _isLaosOrigin(String key) =>
      key.startsWith('la_') || key.startsWith('laos_');

  static double _packingFee(double vw) {
    if (vw <= 0) return 0;
    if (vw < 4) return 2;
    if (vw < 10) return 3;
    if (vw < 15) return 4;
    return 5;
  }

  static Future<QuoteFreightResult> calculate({
    required String routeLabel,
    required List<QuoteBoxInput> boxes,
    bool movingCargo = false,
  }) async {
    final routeKey = RouteCatalog.keyFor(routeLabel);
    final raw = await SupabaseService.client
        .from('freight_rate_tiers')
        .select('min_weight_kg,rate_per_kg,minimum_charge,volumetric_factor,source_note')
        .eq('route_key', routeKey)
        .eq('active', true)
        .order('min_weight_kg');
    final tiers = raw.map((e) => Map<String,dynamic>.from(e)).toList();
    if (tiers.isEmpty) {
      throw StateError('해당 운송 경로의 DB 기준 운임표가 없습니다.');
    }

    final lines=<QuoteBoxFreightResult>[];
    for (final box in boxes) {
      final q=box.quantity < 1 ? 1 : box.quantity;
      final actual=box.weightKg < 0 ? 0.0 : box.weightKg;
      final factor=_d(tiers.first['volumetric_factor'], .00022);
      final volume=box.lengthCm*box.widthCm*box.heightCm*factor;
      final chargeable=actual > volume ? actual : volume;
      var policy=tiers.first;
      for (final t in tiers) {
        if (chargeable >= _d(t['min_weight_kg'])) policy=t; else break;
      }
      final rate=_d(policy['rate_per_kg']);
      final minimum=_d(policy['minimum_charge']);
      final actualTotal=actual*q, volumeTotal=volume*q, chargeableTotal=chargeable*q;
      var amount=chargeableTotal*rate;
      if (amount > 0 && amount < minimum) amount=minimum;

      final moving=routeKey=='la_kr_air_exp' && movingCargo ? 5.0*q : 0.0;
      final packing=_isLaosOrigin(routeKey) && box.boxPacking ? _packingFee(volume)*q : 0.0;
      amount += moving+packing;
      lines.add(QuoteBoxFreightResult(
        index:box.index, actualWeightKg:actualTotal, volumeWeightKg:volumeTotal,
        chargeableWeightKg:chargeableTotal, ratePerKg:rate, quantity:q,
        amountUsd:amount, movingCargoSurchargeUsd:moving, boxPackingSurchargeUsd:packing,
      ));
    }
    final source='${tiers.first['source_note'] ?? ''}';
    return QuoteFreightResult(
      route:routeLabel, lines:lines,
      totalUsd:lines.fold(0.0,(s,e)=>s+e.amountUsd), sourceFile:source,
    );
  }

  static double _d(dynamic v,[double f=0])=>double.tryParse('${v??''}')??f;
}
