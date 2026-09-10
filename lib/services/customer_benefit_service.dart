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
    this.preferred = false,
    this.originalSourceNo,
  });

  final int? id;
  final String routeKey;
  final int? sourceNo;
  final int? originalSourceNo;
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
  final bool preferred;

  bool get isCity => deliveryType == 'city';
  String get typeLabel => isCity ? '시내 배송' : '지방배송';
  bool get isPrepaid {
    final key = paidBy.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    return key.contains('선결제') ||
        key.contains('선결재') ||
        key.contains('선불') ||
        key.contains('prepaid') ||
        key.contains('payinadvance');
  }

  factory LocalDeliveryRule.fromMap(Map<String, dynamic> map) =>
      LocalDeliveryRule(
        id: (map['id'] as num?)?.toInt(),
        routeKey: '${map['route_key'] ?? ''}'.trim(),
        sourceNo: (map['source_no'] as num?)?.toInt(),
        originalSourceNo: (map['original_source_no'] as num?)?.toInt(),
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
        preferred: map['preferred'] == true,
      );

  Map<String, dynamic> toMap() => {
        'route_key': routeKey,
        'source_no': sourceNo,
        'original_source_no': originalSourceNo,
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
                alternateName.trim().isNotEmpty ||
                companyName.trim().isNotEmpty ||
                CustomerBenefitService.normalizePhone(phone).isNotEmpty) &&
            (localCompany.trim().isNotEmpty ||
                destinationAddress.trim().isNotEmpty),
      };

  String toStatementText() {
    final name = alternateName.isNotEmpty ? alternateName : customerName;
    final tel = phoneDisplay.isNotEmpty ? phoneDisplay : phone;
    final displayNo = originalSourceNo ?? (sourceNo == null
        ? null
        : (sourceNo! >= 10000 ? sourceNo! - 10000 : sourceNo!));
    final no = displayNo == null ? '' : 'No. $displayNo';
    return <String>[
      no,
      name,
      tel,
      localCompany,
      destinationAddress,
    ].where((e) => e.trim().isNotEmpty).join('\n');
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

  static String _normalizeFullName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  /// Removes an explicit unknown-recipient prefix for delivery lookup only.
  /// The shipment's displayed name and receipt number are never changed.
  static String deliveryMatchName(String value) {
    final original = value.trim();
    final slash = original.indexOf('/');
    if (slash < 0) return original;
    final prefix = original
        .substring(0, slash)
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s._-]+'), '');
    const unknownPrefixes = <String>{
      '수취인불명',
      '수신인불명',
      '미확인',
      '불확실',
      'unknown',
      'unidentified',
    };
    if (!unknownPrefixes.contains(prefix)) return original;
    final trailingName = original.substring(slash + 1).trim();
    return trailingName.isEmpty ? original : trailingName;
  }

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

  static bool _exactRuleName(LocalDeliveryRule rule, String shipmentName) {
    final key = _normalizeFullName(deliveryMatchName(shipmentName));
    if (key.isEmpty) return false;
    return <String>[
      rule.customerName,
      rule.alternateName,
      rule.companyName,
    ].where((value) => value.trim().isNotEmpty).any(
          (value) => _normalizeFullName(value) == key,
        );
  }

  /// Applies the same deterministic delivery identity order as Excel/web:
  /// unique exact name+phone, then unique exact full name, then unique phone.
  /// A partial token such as `김민규` never matches `김민규/Shuana lor`.
  static LocalDeliveryRule? selectLocalDeliveryRule({
    required Iterable<LocalDeliveryRule> rules,
    required String name,
    required String phone,
  }) {
    final active = rules.where((rule) => rule.active).toList(growable: false);
    final exact = active
        .where((rule) => _exactRuleName(rule, name))
        .toList(growable: false);
    final exactWithPhone = exact
        .where((rule) => _phoneMatches(phone, rule.phone))
        .toList(growable: false);
    if (exactWithPhone.length == 1) return exactWithPhone.single;
    if (exact.length == 1) return exact.single;

    final byPhone = active
        .where((rule) => _phoneMatches(phone, rule.phone))
        .toList(growable: false);
    if (byPhone.length == 1) return byPhone.single;
    return null;
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
        (name.trim().isEmpty && phone.trim().isEmpty)) {
      return null;
    }
    final routeKey = RouteCatalog.formRouteKeyFor(routeLabel);
    if (!localDeliveryRouteKeys.contains(routeKey)) return null;
    final rawId = await SupabaseService.client.rpc(
      'lk_resolve_delivery_profile_id',
      params: {
        'p_route_key': routeKey,
        'p_shipment_name': name,
        'p_shipment_phone': phone,
      },
    );
    if (rawId == null) return null;
    final row = await SupabaseService.client
        .from('local_delivery_profiles')
        .select()
        .eq('id', rawId)
        .eq('route_key', routeKey)
        .eq('active', true)
        .maybeSingle();
    return row == null ? null : LocalDeliveryRule.fromMap(
      Map<String, dynamic>.from(row),
    );
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

