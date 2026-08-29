import '../core/route_catalog.dart';
import 'freight_policy_service.dart';

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
  final double weightKg;
  final double lengthCm;
  final double widthCm;
  final double heightCm;
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

  final int index;
  final double actualWeightKg;
  final double volumeWeightKg;
  final double chargeableWeightKg;
  final double ratePerKg;
  final int quantity;
  final double amountUsd;
  final double movingCargoSurchargeUsd;
  final double boxPackingSurchargeUsd;
}

class QuoteFreightResult {
  const QuoteFreightResult({
    required this.route,
    required this.lines,
    required this.totalUsd,
    required this.sourceFile,
  });

  final String route;
  final List<QuoteBoxFreightResult> lines;
  final double totalUsd;
  final String sourceFile;
}

class QuoteFreightCalculator {
  QuoteFreightCalculator._();

  static bool _isLaosOrigin(String routeKey) =>
      routeKey.startsWith('la_') || routeKey.startsWith('laos_');

  static double _packingFeePerBox(double volumetricWeightKg) {
    if (volumetricWeightKg <= 0) return 0;
    if (volumetricWeightKg < 4) return 2;
    if (volumetricWeightKg < 10) return 3;
    if (volumetricWeightKg < 15) return 4;
    return 5;
  }

  static Future<QuoteFreightResult> calculate({
    required String routeLabel,
    required List<QuoteBoxInput> boxes,
    bool movingCargo = false,
  }) async {
    final routeKey = RouteCatalog.keyFor(routeLabel);
    final policy = await FreightPolicyService.instance.fetch(routeKey);

    final lines = <QuoteBoxFreightResult>[];
    for (final box in boxes) {
      final quantity = box.quantity < 1 ? 1 : box.quantity;
      final unitActual = box.weightKg < 0 ? 0.0 : box.weightKg;
      final unitVolume = box.lengthCm *
          box.widthCm *
          box.heightCm *
          policy.volumetricFactor;
      final unitChargeable =
          unitActual > unitVolume ? unitActual : unitVolume;
      final rate = policy.rateFor(unitChargeable);

      final actualTotal = unitActual * quantity;
      final volumeTotal = unitVolume * quantity;
      final chargeableTotal = unitChargeable * quantity;

      var amount = chargeableTotal * rate;
      if (amount > 0 && amount < policy.minimumCharge) {
        amount = policy.minimumCharge;
      }

      final movingCargoSurcharge =
          routeKey == 'la_kr_air_exp' && movingCargo
              ? 5.0 * quantity
              : 0.0;
      final boxPackingSurcharge =
          _isLaosOrigin(routeKey) && box.boxPacking
              ? _packingFeePerBox(unitVolume) * quantity
              : 0.0;

      amount += movingCargoSurcharge + boxPackingSurcharge;

      lines.add(
        QuoteBoxFreightResult(
          index: box.index,
          actualWeightKg: actualTotal,
          volumeWeightKg: volumeTotal,
          chargeableWeightKg: chargeableTotal,
          ratePerKg: rate,
          quantity: quantity,
          amountUsd: amount,
          movingCargoSurchargeUsd: movingCargoSurcharge,
          boxPackingSurchargeUsd: boxPackingSurcharge,
        ),
      );
    }

    return QuoteFreightResult(
      route: routeLabel,
      lines: lines,
      totalUsd: lines.fold<double>(
        0,
        (sum, line) => sum + line.amountUsd,
      ),
      sourceFile: policy.sourceNote,
    );
  }
}
