import '../config/supabase_config.dart';
import '../core/route_catalog.dart';
import 'supabase_service.dart';

class DiscountRule {
  const DiscountRule({
    required this.id,
    required this.customerName,
    required this.companyName,
    required this.phone,
    required this.routeKey,
    required this.groupName,
    required this.discountPercent,
    required this.rateOverride,
    required this.notes,
    required this.sourceDetail,
    required this.active,
    this.customerGroupId,
    this.bulkThreshold,
    this.bulkDiscountPercent,
    this.statementMode = 'separate',
  });

  final int? id;
  final String customerName;
  final String companyName;
  final String phone;
  final String routeKey;
  final String groupName;
  final double discountPercent;
  final double? rateOverride;
  final String notes;
  final String sourceDetail;
  final bool active;
  final int? customerGroupId;
  final int? bulkThreshold;
  final double? bulkDiscountPercent;
  final String statementMode;

  bool get hasBulkTier =>
      bulkThreshold != null && bulkDiscountPercent != null;

  factory DiscountRule.fromMap(Map<String, dynamic> map) => DiscountRule(
        id: (map['id'] as num?)?.toInt(),
        customerName: '${map['customer_name'] ?? ''}'.trim(),
        companyName: '${map['company_name'] ?? ''}'.trim(),
        phone: '${map['phone'] ?? ''}'.trim(),
        routeKey: '${map['route_key'] ?? 'all'}'.trim(),
        groupName: '${map['group_name'] ?? ''}'.trim(),
        discountPercent:
            double.tryParse('${map['discount_percent'] ?? 0}') ?? 0,
        rateOverride: map['rate_override'] == null
            ? null
            : double.tryParse('${map['rate_override']}'),
        notes: '${map['notes'] ?? ''}'.trim(),
        sourceDetail: '${map['source_detail'] ?? ''}'.trim(),
        active: map['active'] == true,
        customerGroupId: (map['customer_group_id'] as num?)?.toInt(),
        bulkThreshold: (map['bulk_threshold'] as num?)?.toInt(),
        bulkDiscountPercent: map['bulk_discount_percent'] == null
            ? null
            : double.tryParse('${map['bulk_discount_percent']}'),
        statementMode:
            '${map['statement_mode'] ?? 'separate'}' == 'combined'
                ? 'combined'
                : 'separate',
      );

  Map<String, dynamic> toMap() => {
        'customer_name': customerName.trim(),
        'company_name': companyName.trim(),
        'phone': CustomerBenefitService.normalizePhone(phone),
        'route_key': routeKey.trim().isEmpty ? 'all' : routeKey.trim(),
        'group_name': groupName.trim(),
        'discount_percent': discountPercent,
        'rate_override': rateOverride,
        'notes': notes.trim(),
        'source_detail': sourceDetail.trim(),
        'active': active &&
            customerName.trim().isNotEmpty &&
            CustomerBenefitService.normalizePhone(phone).isNotEmpty,
        'customer_group_id': customerGroupId,
        'bulk_threshold': bulkThreshold,
        'bulk_discount_percent': bulkDiscountPercent,
        'statement_mode':
            statementMode == 'combined' ? 'combined' : 'separate',
      };
}

class LocalDeliveryRule {
  const LocalDeliveryRule({
    required this.id,
    required this.routeKey,
    required this.sourceNo,
    required this.customerName,
    required this.alternateName,
    required this.companyName,
    required this.phone,
    required this.phoneDisplay,
    required this.deliveryType,
    required this.localCompany,
    required this.destinationAddress,
    required this.paidBy,
    required this.notes,
    required this.active,
  });

  final int? id;
  final String routeKey;
  final int? sourceNo;
  final String customerName;
  final String alternateName;
  final String companyName;
  final String phone;
  final String phoneDisplay;
  final String deliveryType;
  final String localCompany;
  final String destinationAddress;
  final String paidBy;
  final String notes;
  final bool active;

  bool get isCity => deliveryType == 'city';
  String get typeLabel => isCity ? '시내 배송' : '지방배송';

  factory LocalDeliveryRule.fromMap(Map<String, dynamic> map) =>
      LocalDeliveryRule(
        id: (map['id'] as num?)?.toInt(),
        routeKey: '${map['route_key'] ?? ''}'.trim(),
        sourceNo: (map['source_no'] as num?)?.toInt(),
        customerName: '${map['customer_name'] ?? ''}'.trim(),
        alternateName: '${map['alternate_name'] ?? ''}'.trim(),
        companyName: '${map['company_name'] ?? ''}'.trim(),
        phone: '${map['phone'] ?? ''}'.trim(),
        phoneDisplay: '${map['phone_display'] ?? ''}'.trim(),
        deliveryType: '${map['delivery_type'] ?? 'province'}'.trim(),
        localCompany: '${map['local_company'] ?? ''}'.trim(),
        destinationAddress: '${map['destination_address'] ?? ''}'.trim(),
        paidBy: '${map['paid_by'] ?? ''}'.trim(),
        notes: '${map['notes'] ?? ''}'.trim(),
        active: map['active'] == true,
      );

  Map<String, dynamic> toMap() => {
        'route_key': routeKey,
        'source_no': sourceNo,
        'customer_name': customerName.trim(),
        'alternate_name': alternateName.trim(),
        'company_name': companyName.trim(),
        'phone': CustomerBenefitService.normalizePhone(phone),
        'phone_display':
            phoneDisplay.trim().isEmpty ? phone.trim() : phoneDisplay.trim(),
        'delivery_type': deliveryType == 'city' ? 'city' : 'province',
        'local_company': localCompany.trim(),
        'destination_address': destinationAddress.trim(),
        'paid_by': paidBy.trim(),
        'notes': notes.trim(),
        'active': active &&
            (customerName.trim().isNotEmpty ||
                companyName.trim().isNotEmpty) &&
            CustomerBenefitService.normalizePhone(phone).isNotEmpty,
      };

  String toStatementText() {
    final name = alternateName.isNotEmpty ? alternateName : customerName;
    final tel = phoneDisplay.isNotEmpty ? phoneDisplay : phone;
    final displayNo = sourceNo == null
        ? null
        : (sourceNo! >= 10000 ? sourceNo! - 10000 : sourceNo!);
    final no = displayNo == null ? '' : '($displayNo) ';
    return <String>[
      '$no$name'.trim(),
      tel,
      localCompany,
      destinationAddress,
    ].where((e) => e.trim().isNotEmpty).join(', ');
  }
}

class CustomerBenefitService {
  CustomerBenefitService._();
  static final CustomerBenefitService instance = CustomerBenefitService._();

  static const localDeliveryRouteKeys = <String>[
    'kr_la_sea',
    'kr_la_air',
    'th_la_land',
  ];

  static String normalizePhone(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

  static String _normalizeName(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');

  static bool _phoneMatches(String a, String b) {
    final aa = normalizePhone(a);
    final bb = normalizePhone(b);
    if (aa.isEmpty || bb.isEmpty) return false;
    if (aa == bb) return true;
    if (aa.length >= 8 && bb.length >= 8) {
      if (aa.substring(aa.length - 8) == bb.substring(bb.length - 8)) {
        return true;
      }
      // BASE 배송표 한 셀에 전화번호가 2개 이상 들어간 경우도 허용.
      if (aa.contains(bb) || bb.contains(aa)) return true;
    }
    return false;
  }

  static Iterable<String> _nameTokens(String value) sync* {
    final normalized = _normalizeName(value);
    if (normalized.isEmpty) return;
    yield normalized;

    // 실무 BASE 표기: 이경화/이경희, 이름,이름, 이름(보조명) 등.
    for (final part in normalized.split(RegExp(r'[/,;|()\\]+'))) {
      final token = _normalizeName(part);
      if (token.isNotEmpty) yield token;
    }
  }

  static int _nameMatchRank(String shipmentName, String candidateName) {
    final a = _nameTokens(shipmentName).toSet();
    final b = _nameTokens(candidateName).toSet();
    if (a.isEmpty || b.isEmpty) return 9999;
    final overlap = a.intersection(b);
    if (overlap.isEmpty) return 9999;
    if (a.length == b.length && a.containsAll(b) && b.containsAll(a)) return 0;
    if (a.containsAll(b)) return 10 + (a.length - b.length);
    if (b.containsAll(a)) return 30 - b.length.clamp(0, 20);
    return 50 - overlap.length.clamp(0, 20);
  }

  static int _bestNameRank(
    String shipmentName,
    Iterable<String> candidates,
  ) {
    var best = 9999;
    for (final value in candidates) {
      if (value.trim().isEmpty) continue;
      final rank = _nameMatchRank(shipmentName, value);
      if (rank < best) best = rank;
    }
    return best;
  }

  Future<List<DiscountRule>> listDiscountRules() async {
    if (!SupabaseConfig.isConfigured) return const [];
    try {
      final raw = await SupabaseService.client
          .rpc('admin_list_discount_rules_with_identity') as List;
      return raw
          .map((e) => DiscountRule.fromMap(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList(growable: false);
    } catch (_) {
      final rows = await SupabaseService.client
          .from('customer_rate_overrides')
          .select()
          .order('route_key')
          .order('group_name')
          .order('customer_name');
      return List<Map<String, dynamic>>.from(rows)
          .map(DiscountRule.fromMap)
          .toList(growable: false);
    }
  }

  Future<void> saveDiscountRule(DiscountRule rule) async {
    if (!SupabaseConfig.isConfigured) return;

    int? customerGroupId = rule.customerGroupId;
    try {
      final rawGroup = await SupabaseService.client.rpc(
        'admin_set_customer_statement_mode',
        params: {
          'p_name': rule.customerName.trim(),
          'p_company': rule.companyName.trim(),
          'p_phone': rule.phone.trim(),
          'p_mode':
              rule.statementMode == 'combined' ? 'combined' : 'separate',
        },
      );
      customerGroupId = (rawGroup as num?)?.toInt() ?? customerGroupId;
    } catch (_) {
      // Migration 068 적용 전 DB에서도 기존 저장 흐름은 유지합니다.
    }

    final data = DiscountRule(
      id: rule.id,
      customerName: rule.customerName,
      companyName: rule.companyName,
      phone: rule.phone,
      routeKey: rule.routeKey,
      groupName: rule.groupName,
      discountPercent: rule.discountPercent,
      rateOverride: rule.rateOverride,
      notes: rule.notes,
      sourceDetail: rule.sourceDetail,
      active: rule.active,
      customerGroupId: customerGroupId,
      bulkThreshold: rule.bulkThreshold,
      bulkDiscountPercent: rule.bulkDiscountPercent,
      statementMode: rule.statementMode,
    ).toMap();

    if (rule.id == null) {
      await SupabaseService.client
          .from('customer_rate_overrides')
          .insert(data);
    } else {
      await SupabaseService.client
          .from('customer_rate_overrides')
          .update(data)
          .eq('id', rule.id!);
    }
    await _refreshSpecialNotes();
  }

  Future<void> deleteDiscountRule(int id) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client
        .from('customer_rate_overrides')
        .delete()
        .eq('id', id);
    await _refreshSpecialNotes();
  }

  Future<List<LocalDeliveryRule>> listLocalDeliveryRules() async {
    if (!SupabaseConfig.isConfigured) return const [];
    final rows = await SupabaseService.client
        .from('local_delivery_profiles')
        .select()
        .order('route_key')
        .order('source_no');
    return List<Map<String, dynamic>>.from(rows)
        .map(LocalDeliveryRule.fromMap)
        .toList(growable: false);
  }

  Future<void> saveLocalDeliveryRule(LocalDeliveryRule rule) async {
    if (!SupabaseConfig.isConfigured) return;
    final data = rule.toMap();
    if (rule.id == null) {
      await SupabaseService.client
          .from('local_delivery_profiles')
          .insert(data);
    } else {
      await SupabaseService.client
          .from('local_delivery_profiles')
          .update(data)
          .eq('id', rule.id!);
    }
    await _refreshSpecialNotes();
  }

  Future<void> deleteLocalDeliveryRule(int id) async {
    if (!SupabaseConfig.isConfigured) return;
    await SupabaseService.client
        .from('local_delivery_profiles')
        .delete()
        .eq('id', id);
    await _refreshSpecialNotes();
  }

  Future<LocalDeliveryRule?> matchLocalDelivery({
    required String routeLabel,
    required String name,
    required String phone,
  }) async {
    if (!SupabaseConfig.isConfigured ||
        name.trim().isEmpty ||
        phone.trim().isEmpty) {
      return null;
    }
    final routeKey = RouteCatalog.formRouteKeyFor(routeLabel);
    if (!localDeliveryRouteKeys.contains(routeKey)) return null;
    final rows = await SupabaseService.client
        .from('local_delivery_profiles')
        .select()
        .eq('route_key', routeKey)
        .eq('active', true)
        .order('preferred', ascending: false)
        .order('source_no')
        .limit(500);
    LocalDeliveryRule? bestRule;
    var bestRank = 9999;
    var bestSource = 1 << 30;
    for (final raw in rows) {
      final rule =
          LocalDeliveryRule.fromMap(Map<String, dynamic>.from(raw));
      if (!_phoneMatches(phone, rule.phone)) continue;
      final rank = _bestNameRank(
        name,
        [rule.customerName, rule.alternateName, rule.companyName],
      );
      if (rank >= 9999) continue;
      final source = rule.sourceNo ?? (1 << 30);
      if (rank < bestRank || (rank == bestRank && source < bestSource)) {
        bestRule = rule;
        bestRank = rank;
        bestSource = source;
      }
    }
    return bestRule;
  }

  Future<String> inlandTextForRows(
    String routeLabel,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final row in rows) {
      final rule = await matchLocalDelivery(
        routeLabel: routeLabel,
        name: '${row['consignee_name'] ?? ''}',
        phone: '${row['consignee_phone'] ?? ''}',
      );
      if (rule != null) return rule.toStatementText();
    }
    return '';
  }

  Future<void> _refreshSpecialNotes() async {
    try {
      await SupabaseService.client.rpc('admin_refresh_shipment_special_notes');
    } catch (_) {
      // 관리 정보 자체 저장을 특이사항 재계산 실패가 막지 않음.
    }
  }
}
