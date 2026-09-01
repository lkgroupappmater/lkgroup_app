import '../config/supabase_config.dart';
import '../core/route_catalog.dart';
import 'exchange_rate_service.dart';
import 'freight_policy_service.dart';
import 'supabase_service.dart';

class FreightLineResult {
  const FreightLineResult({
    required this.shipmentId,
    required this.boxNumber,
    required this.invoiceNumber,
    required this.route,
    required this.actualWeight,
    required this.volumeWeight,
    required this.chargeableWeight,
    required this.rate,
    required this.amountUsd,
    this.grossAmountUsd = 0,
    this.discountPercent = 0,
    this.discountAmountUsd = 0,
    this.autoDiscountPercent = 0,
    this.additionalDiscountPercent = 0,
    this.autoDiscountAmountUsd = 0,
    this.additionalDiscountAmountUsd = 0,
    this.additionalDiscountName = '',
    this.discountGroup = '',
    this.discountCustomer = '',
    this.discountCombinedQuantity = 0,
  });

  final String shipmentId;
  final String boxNumber;
  final String invoiceNumber;
  final String route;
  final double actualWeight;
  final double volumeWeight;
  final double chargeableWeight;
  final double rate;
  final double amountUsd;
  final double grossAmountUsd;
  /// Total additive discount = automatic BASE/DB + manual additional.
  final double discountPercent;
  final double discountAmountUsd;
  final double autoDiscountPercent;
  final double additionalDiscountPercent;
  final double autoDiscountAmountUsd;
  final double additionalDiscountAmountUsd;
  final String additionalDiscountName;
  final String discountGroup;
  final String discountCustomer;
  final int discountCombinedQuantity;
}

class FreightCalculation {
  const FreightCalculation({
    required this.lines,
    required this.totalUsd,
    required this.totalKip,
    required this.totalThb,
    required this.totalKrw,
    required this.rates,
    this.grossTotalUsd = 0,
    this.discountTotalUsd = 0,
    this.discountByGroup = const <String, double>{},
  });

  final List<FreightLineResult> lines;
  final double totalUsd;
  final double totalKip;
  final double totalThb;
  final double totalKrw;
  final ExchangeRateSettings rates;
  final double grossTotalUsd;
  final double discountTotalUsd;
  final Map<String, double> discountByGroup;
}

class FreightService {
  FreightService._();
  static final FreightService instance = FreightService._();

  Future<FreightCalculation> calculate(
    List<Map<String, dynamic>> shipments,
  ) async {
    final exchange = await ExchangeRateService.instance.fetch();
    final lines = <FreightLineResult>[];
    final policyCache = <String, FreightPolicy>{};
    final overrideCache = <String, Map<String, dynamic>?>{};
    final manualDiscountCache = <String, Map<String, dynamic>?>{};

    for (final row in shipments) {
      final routeLabel = '${row['route'] ?? ''}';
      final routeKey = RouteCatalog.formRouteKeyFor(routeLabel);
      final policy = policyCache[routeKey] ??=
          await FreightPolicyService.instance.fetch(routeKey);

      final quantity =
          _d(row['quantity'], 1).clamp(1, 999999).toDouble();
      final actual = _d(row['weight_kg']) * quantity;
      final volume = _d(row['length_cm']) *
          _d(row['width_cm']) *
          _d(row['height_cm']) *
          policy.volumetricFactor *
          quantity;
      final chargeable = actual > volume ? actual : volume;

      double rate = policy.rateFor(chargeable);
      final minimum = policy.minimumCharge;
      double grossAmount = chargeable * rate;
      if (grossAmount > 0 && grossAmount < minimum) {
        grossAmount = minimum;
      }

      final name = '${row['consignee_name'] ?? ''}';
      final phone = '${row['consignee_phone'] ?? ''}';
      final year = _intOrNull(row['shipment_year'] ?? row['year']);
      final voyage = '${row['voyage'] ?? ''}';
      final receiptNumber = '${row['receipt_number'] ?? ''}'.trim();

      final cacheKey =
          '$routeKey|${year ?? ''}|$voyage|$receiptNumber|${_digits(phone)}|${name.trim().toLowerCase()}';
      final override = overrideCache.containsKey(cacheKey)
          ? overrideCache[cacheKey]
          : await _customerOverride(
              routeKey: routeKey,
              year: year,
              voyage: voyage,
              receiptNumber: receiptNumber,
              name: name,
              phone: phone,
            );
      overrideCache[cacheKey] = override;

      final manualKey = '$routeKey|${year ?? ''}|$voyage|$receiptNumber';
      final manualAdditional = manualDiscountCache.containsKey(manualKey)
          ? manualDiscountCache[manualKey]
          : await _receiptAdditionalDiscount(
              routeKey: routeKey,
              year: year,
              voyage: voyage,
              receiptNumber: receiptNumber,
            );
      manualDiscountCache[manualKey] = manualAdditional;

      final overrideRate = _nullableD(override?['rate_override']);
      if (overrideRate != null) {
        rate = overrideRate;
        grossAmount = chargeable * rate;
        if (grossAmount > 0 && grossAmount < minimum) {
          grossAmount = minimum;
        }
      }

      final autoDiscount =
          _d(override?['discount_percent']).clamp(0, 1).toDouble();
      final additionalDiscount =
          _d(manualAdditional?['discount_percent']).clamp(0, 1).toDouble();
      // Additive against the same original eligible amount: 20% + 10% = 30%.
      final discount =
          (autoDiscount + additionalDiscount).clamp(0, 1).toDouble();
      final autoDiscountAmount = grossAmount * autoDiscount;
      final additionalDiscountAmount = grossAmount * additionalDiscount;
      final discountAmount = autoDiscountAmount + additionalDiscountAmount;
      final amount = grossAmount - discountAmount;
      final group = '${override?['group_name'] ?? ''}'.trim();
      final additionalDiscountName =
          '${manualAdditional?['discount_name'] ?? ''}'.trim();
      final matchedCustomer =
          '${override?['customer_name'] ?? ''}'.trim();
      final combinedQuantity =
          (override?['combined_quantity'] as num?)?.toInt() ?? 0;

      lines.add(
        FreightLineResult(
          shipmentId: '${row['id'] ?? ''}',
          boxNumber: '${row['box_number'] ?? ''}',
          invoiceNumber: '${row['invoice_number'] ?? ''}',
          route: routeLabel,
          actualWeight: actual,
          volumeWeight: volume,
          chargeableWeight: chargeable,
          rate: rate,
          amountUsd: amount,
          grossAmountUsd: grossAmount,
          discountPercent: discount,
          discountAmountUsd: discountAmount,
          autoDiscountPercent: autoDiscount,
          additionalDiscountPercent: additionalDiscount,
          autoDiscountAmountUsd: autoDiscountAmount,
          additionalDiscountAmountUsd: additionalDiscountAmount,
          additionalDiscountName: additionalDiscountName,
          discountGroup: group,
          discountCustomer: matchedCustomer,
          discountCombinedQuantity: combinedQuantity,
        ),
      );
    }

    final grossTotal =
        lines.fold<double>(0, (sum, line) => sum + line.grossAmountUsd);
    final discountTotal =
        lines.fold<double>(0, (sum, line) => sum + line.discountAmountUsd);
    final totalUsd =
        lines.fold<double>(0, (sum, line) => sum + line.amountUsd);
    final byGroup = <String, double>{};
    for (final line in lines) {
      if (line.autoDiscountAmountUsd > 0) {
        final key =
            line.discountGroup.isEmpty ? '기타 할인' : line.discountGroup;
        byGroup[key] = (byGroup[key] ?? 0) + line.autoDiscountAmountUsd;
      }
      if (line.additionalDiscountAmountUsd > 0) {
        final key = line.additionalDiscountName.isEmpty
            ? '추가 할인'
            : line.additionalDiscountName;
        byGroup[key] =
            (byGroup[key] ?? 0) + line.additionalDiscountAmountUsd;
      }
    }

    return FreightCalculation(
      lines: lines,
      grossTotalUsd: grossTotal,
      discountTotalUsd: discountTotal,
      discountByGroup: Map<String, double>.unmodifiable(byGroup),
      totalUsd: totalUsd,
      totalKip: totalUsd * exchange.appliedKip,
      totalThb: totalUsd * exchange.appliedThb,
      totalKrw: totalUsd * exchange.appliedKrw,
      rates: exchange,
    );
  }

  Future<Map<String, dynamic>?> _receiptAdditionalDiscount({
    required String routeKey,
    required int? year,
    required String voyage,
    required String receiptNumber,
  }) async {
    if (!SupabaseConfig.isConfigured || year == null || receiptNumber.isEmpty) {
      return null;
    }
    try {
      final raw = await SupabaseService.client.rpc(
        'get_receipt_discount_override',
        params: {
          'p_route_key': routeKey,
          'p_year': year,
          'p_voyage': voyage,
          'p_receipt_number': receiptNumber,
        },
      );
      if (raw is Map) {
        final row = Map<String, dynamic>.from(raw);
        if (row['id'] != null) return row;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _customerOverride({
    required String routeKey,
    required int? year,
    required String voyage,
    required String receiptNumber,
    required String name,
    required String phone,
  }) async {
    if (!SupabaseConfig.isConfigured || name.trim().isEmpty) {
      return null;
    }

    // Patch123+: Customer Group의 개인명+회사명 물량을 같은 항차에서 합산해
    // bulk tier를 결정합니다.
    try {
      final raw = await SupabaseService.client.rpc(
        'resolve_customer_discount_context',
        params: {
          'p_route_key': routeKey,
          'p_year': year,
          'p_voyage': voyage,
          'p_name': name.trim(),
          'p_phone': phone.trim(),
        },
      );
      if (raw is Map) {
        final mapped = Map<String, dynamic>.from(raw);
        if (mapped['id'] != null ||
            mapped['customer_group_id'] != null) {
          return mapped;
        }
      }
    } catch (_) {
      // 068 SQL 적용 전에는 기존 할인 매칭으로 안전하게 fallback.
    }

    final rows = await SupabaseService.client
        .from('customer_rate_overrides')
        .select()
        .eq('active', true)
        .limit(500);

    Map<String, dynamic>? bestRouteMatch;
    Map<String, dynamic>? bestAllMatch;
    var bestRouteRank = 9999;
    var bestAllRank = 9999;

    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final ruleRoute = '${row['route_key'] ?? ''}'.trim();
      if (ruleRoute != 'all' && ruleRoute != routeKey) continue;
      if (!_phoneMatches(phone, '${row['phone'] ?? ''}')) {
        continue;
      }

      final candidates = [
        '${row['customer_name'] ?? ''}',
        '${row['company_name'] ?? ''}',
      ];
      var rank = 9999;
      for (final candidate in candidates) {
        if (candidate.trim().isEmpty) continue;
        final candidateRank = _nameMatchRank(name, candidate);
        if (candidateRank < rank) rank = candidateRank;
      }
      if (rank >= 9999) continue;

      if (ruleRoute == routeKey) {
        if (rank < bestRouteRank) {
          bestRouteRank = rank;
          bestRouteMatch = row;
        }
      } else if (rank < bestAllRank) {
        bestAllRank = rank;
        bestAllMatch = row;
      }
    }
    return bestRouteMatch ?? bestAllMatch;
  }

  static List<String> _nameTokens(String value) => value
      .replaceAll(RegExp(r'[\?\*]+'), '/')
      .split(RegExp(r'[/,;|()]+'))
      .map((e) => e.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '))
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList(growable: false);

  static int _nameMatchRank(String value, String candidate) {
    final a = _nameTokens(value).toSet();
    final b = _nameTokens(candidate).toSet();
    if (a.isEmpty || b.isEmpty) return 9999;

    final overlap = a.intersection(b);
    if (overlap.isEmpty) return 9999;

    if (a.length == b.length && a.containsAll(b) && b.containsAll(a)) {
      return 0;
    }
    if (a.containsAll(b)) return 10 + (a.length - b.length);
    if (b.containsAll(a)) return 30 - b.length.clamp(0, 20);
    return 50 - overlap.length.clamp(0, 20);
  }

  static bool _nameMatches(
    String value,
    Iterable<String> candidates,
  ) =>
      candidates.any(
        (candidate) =>
            candidate.trim().isNotEmpty &&
            _nameMatchRank(value, candidate) < 9999,
      );

  static bool _phoneMatches(String a, String b) {
    final aa = _digits(a);
    final bb = _digits(b);
    if (aa.isNotEmpty && bb.isNotEmpty) {
      if (aa == bb) return true;
      if (aa.length >= 8 && bb.length >= 8) {
        return aa.substring(aa.length - 8) ==
            bb.substring(bb.length - 8);
      }
      return false;
    }

    // Some confirmed BASE identities use a non-numeric token such as CEO.
    // This is still a strong phone/identity match: exact token on both sides.
    final rawA = a.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final rawB = b.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    return rawA.isNotEmpty && rawA == rawB;
  }

  static String _digits(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

  static int? _intOrNull(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(
      '${value ?? ''}'.replaceAll(RegExp(r'[^0-9]'), ''),
    );
  }

  static double _d(dynamic value, [double fallback = 0]) =>
      double.tryParse('${value ?? ''}'.trim()) ?? fallback;

  static double? _nullableD(dynamic value) =>
      value == null ? null : double.tryParse('$value');
}
