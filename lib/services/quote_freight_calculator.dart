import '../core/route_catalog.dart';

class QuoteBoxInput {
  const QuoteBoxInput({
    required this.index,
    required this.weightKg,
    required this.lengthCm,
    required this.widthCm,
    required this.heightCm,
    required this.quantity,
  });

  final int index;
  final double weightKg;
  final double lengthCm;
  final double widthCm;
  final double heightCm;
  final int quantity;
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
  });

  final int index;
  final double actualWeightKg;
  final double volumeWeightKg;
  final double chargeableWeightKg;
  final double ratePerKg;
  final int quantity;
  final double amountUsd;
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

  static const double _volumetricFactor = 0.00022;

  static final Map<String, _RouteTariff> _tariffs = {
    'kr_la_sea': const _RouteTariff(
      sourceFile: 'KR_LA_SEA_2026_V00_SHIPMENTS.xlsx',
      minimumCharge: 1.5,
      tiers: [_RateTier(0, 1.5)],
    ),
    'kr_la_air': const _RouteTariff(
      sourceFile: 'KR_LA_AIR_2026_V00_SHIPMENTS.xlsx',
      minimumCharge: 14,
      tiers: [_RateTier(0, 14)],
    ),
    'la_kr_air_exp': const _RouteTariff(
      sourceFile: 'LA_KR_AIR_EXP_2026_V00_SHIPMENTS.xlsx',
      minimumCharge: 18,
      tiers: [
        _RateTier(0, 18),
        _RateTier(2, 16),
        _RateTier(6, 14),
        _RateTier(10, 12),
        _RateTier(15, 10),
      ],
    ),
    'th_la_land': const _RouteTariff(
      sourceFile: 'TH_LA_LAND_2026_V00_SHIPMENTS.xlsx',
      minimumCharge: 4,
      tiers: [
        _RateTier(0, 4),
        _RateTier(2, 2.5),
        _RateTier(6, 1.5),
        _RateTier(10, 1.25),
        _RateTier(15, 1.15),
        _RateTier(18, 1.13),
        _RateTier(21, 1.1),
      ],
    ),
    'la_th_land': const _RouteTariff(
      sourceFile: 'LA_TH_LAND_2026_V00_SHIPMENTS.xlsx',
      minimumCharge: 12.4,
      tiers: [
        _RateTier(0, 12.4),
        _RateTier(2, 5.3),
        _RateTier(6, 3.6),
        _RateTier(10, 3.6),
        _RateTier(15, 3.3),
        _RateTier(18, 3.4),
        _RateTier(21, 3.5),
        _RateTier(25, 3.7),
        _RateTier(30, 3.8),
        _RateTier(35, 3.9),
        _RateTier(40, 4),
        _RateTier(45, 4),
      ],
    ),
    'la_vn_land': const _RouteTariff(
      sourceFile: 'LA_VN_LAND_2026_V00_SHIPMENTS.xlsx',
      minimumCharge: 13.6,
      tiers: [
        _RateTier(0, 13.6),
        _RateTier(2, 8.7),
        _RateTier(3, 7.1),
        _RateTier(4, 6.3),
        _RateTier(6, 5.4),
        _RateTier(10, 4.8),
        _RateTier(15, 4.5),
        _RateTier(20, 4.3),
      ],
    ),
    'vn_la_land': const _RouteTariff(
      sourceFile: 'VN_LA_LAND_2026_V00_SHIPMENTS.xlsx',
      minimumCharge: 13.6,
      tiers: [
        _RateTier(0, 13.6),
        _RateTier(2, 8.7),
        _RateTier(3, 7.1),
        _RateTier(4, 6.3),
        _RateTier(6, 5.4),
        _RateTier(10, 4.8),
        _RateTier(15, 4.5),
        _RateTier(20, 4.3),
      ],
    ),
    'la_ch_land': const _RouteTariff(
      sourceFile: 'LA_CH_LAND_2026_V00_SHIPMENTS.xlsx',
      minimumCharge: 13.4,
      tiers: [
        _RateTier(0, 13.4),
        _RateTier(2, 10.6),
        _RateTier(5, 9),
        _RateTier(9, 8.5),
        _RateTier(13, 8.3),
        _RateTier(17, 8.2),
        _RateTier(20, 8.1),
      ],
    ),
    'ch_la_land': const _RouteTariff(
      sourceFile: 'CH_LA_LAND_2026_V00_SHIPMENTS.xlsx',
      minimumCharge: 1.2,
      tiers: [_RateTier(0, 1.2)],
    ),
    'la_kh_land': const _RouteTariff(
      sourceFile: 'LA_KH_LAND_2026_V00_SHIPMENTS.xlsx',
      minimumCharge: 22.5,
      tiers: [
        _RateTier(0, 22.5),
        _RateTier(2, 14.3),
        _RateTier(3, 11.5),
        _RateTier(4, 10.2),
        _RateTier(6, 8.8),
        _RateTier(10, 7.7),
        _RateTier(15, 7.1),
        _RateTier(20, 6.9),
      ],
    ),
  };

  static bool supportsRoute(String routeLabel) =>
      _tariffs.containsKey(RouteCatalog.keyFor(routeLabel));

  static QuoteFreightResult calculate({
    required String routeLabel,
    required List<QuoteBoxInput> boxes,
  }) {
    final routeKey = RouteCatalog.keyFor(routeLabel);
    final tariff = _tariffs[routeKey];
    if (tariff == null) {
      throw StateError('해당 운송 경로는 기준 샘플 Excel 운임표가 없어 자동 운임 계산을 지원하지 않습니다.');
    }

    final lines = <QuoteBoxFreightResult>[];
    for (final box in boxes) {
      final quantity = box.quantity < 1 ? 1 : box.quantity;
      final unitActual = box.weightKg < 0 ? 0.0 : box.weightKg;
      final unitVolume = box.lengthCm *
          box.widthCm *
          box.heightCm *
          _volumetricFactor;
      final unitChargeable = unitActual > unitVolume ? unitActual : unitVolume;
      final rate = tariff.rateFor(unitChargeable);

      final actualTotal = unitActual * quantity;
      final volumeTotal = unitVolume * quantity;
      final chargeableTotal = unitChargeable * quantity;

      var amount = chargeableTotal * rate;
      if (amount > 0 && amount < tariff.minimumCharge) {
        amount = tariff.minimumCharge;
      }

      lines.add(QuoteBoxFreightResult(
        index: box.index,
        actualWeightKg: actualTotal,
        volumeWeightKg: volumeTotal,
        chargeableWeightKg: chargeableTotal,
        ratePerKg: rate,
        quantity: quantity,
        amountUsd: amount,
      ));
    }

    return QuoteFreightResult(
      route: routeLabel,
      lines: lines,
      totalUsd: lines.fold<double>(0, (sum, line) => sum + line.amountUsd),
      sourceFile: tariff.sourceFile,
    );
  }
}

class _RouteTariff {
  const _RouteTariff({
    required this.sourceFile,
    required this.minimumCharge,
    required this.tiers,
  });

  final String sourceFile;
  final double minimumCharge;
  final List<_RateTier> tiers;

  double rateFor(double chargeableWeight) {
    var result = tiers.first.rate;
    for (final tier in tiers) {
      if (chargeableWeight >= tier.minWeightKg) {
        result = tier.rate;
      } else {
        break;
      }
    }
    return result;
  }
}

class _RateTier {
  const _RateTier(this.minWeightKg, this.rate);
  final double minWeightKg;
  final double rate;
}
