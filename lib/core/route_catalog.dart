// lib/core/route_catalog.dart
/// 앱 전체 공통 운송 경로.
/// 기존 내장 경로는 안전한 fallback으로 유지하고,
/// Supabase route_definitions가 준비되면 런타임 목록/Prefix/BASE 상속 정보를 사용합니다.
List<String> get routeLabels => RouteCatalog.all;

class RouteDefinition {
  const RouteDefinition({
    required this.routeKey,
    required this.displayName,
    required this.filePrefix,
    required this.boxPrefix,
    required this.receiptPrefix,
    this.baseRouteKey = '',
    this.status = 'active',
  });

  final String routeKey;
  final String displayName;
  final String filePrefix;
  final String boxPrefix;
  final String receiptPrefix;
  final String baseRouteKey;
  final String status;

  factory RouteDefinition.fromMap(Map<String, dynamic> row) {
    return RouteDefinition(
      routeKey: '${row['route_key'] ?? ''}'.trim(),
      displayName: '${row['display_name'] ?? ''}'.trim(),
      filePrefix: '${row['file_prefix'] ?? ''}'.trim(),
      boxPrefix: '${row['box_prefix'] ?? ''}'.trim(),
      receiptPrefix: '${row['receipt_prefix'] ?? ''}'.trim(),
      baseRouteKey: '${row['base_route_key'] ?? ''}'.trim(),
      status: '${row['status'] ?? 'active'}'.trim(),
    );
  }
}

class RouteCatalog {
  RouteCatalog._();

  static const List<RouteDefinition> _builtIns = [
    RouteDefinition(
      routeKey: 'kr_la_sea',
      displayName: '한국->라오스 해상',
      filePrefix: 'KR_LA_SEA',
      boxPrefix: 'S',
      receiptPrefix: 'LKS',
    ),
    RouteDefinition(
      routeKey: 'kr_la_air',
      displayName: '한국->라오스 항공',
      filePrefix: 'KR_LA_AIR',
      boxPrefix: 'A',
      receiptPrefix: 'LKA',
    ),
    RouteDefinition(
      routeKey: 'la_kr_air_exp',
      displayName: '라오스->한국 항공 특송',
      filePrefix: 'LA_KR_AIR_EXP',
      boxPrefix: 'B',
      receiptPrefix: 'LKB',
    ),
    RouteDefinition(
      routeKey: 'la_th_land',
      displayName: '라오스->태국 육로',
      filePrefix: 'LA_TH_LAND',
      boxPrefix: 'LT',
      receiptPrefix: 'LKLT',
    ),
    RouteDefinition(
      routeKey: 'th_la_land',
      displayName: '태국->라오스 육로',
      filePrefix: 'TH_LA_LAND',
      boxPrefix: 'TL',
      receiptPrefix: 'LKTL',
    ),
    RouteDefinition(
      routeKey: 'la_vn_land',
      displayName: '라오스->베트남 육로',
      filePrefix: 'LA_VN_LAND',
      boxPrefix: 'LV',
      receiptPrefix: 'LKLV',
    ),
    RouteDefinition(
      routeKey: 'vn_la_land',
      displayName: '베트남->라오스 육로',
      filePrefix: 'VN_LA_LAND',
      boxPrefix: 'VL',
      receiptPrefix: 'LKVL',
    ),
    RouteDefinition(
      routeKey: 'la_ch_land',
      displayName: '라오스->중국 육로',
      filePrefix: 'LA_CH_LAND',
      boxPrefix: 'LC',
      receiptPrefix: 'LC',
    ),
    RouteDefinition(
      routeKey: 'ch_la_land',
      displayName: '중국->라오스 육로',
      filePrefix: 'CH_LA_LAND',
      boxPrefix: 'CL',
      receiptPrefix: 'LKCL',
    ),
    RouteDefinition(
      routeKey: 'la_kh_land',
      displayName: '라오스->캄보디아 육로',
      filePrefix: 'LA_KH_LAND',
      boxPrefix: 'LCB',
      receiptPrefix: 'LKLCB',
    ),
    RouteDefinition(
      routeKey: 'kh_la_land',
      displayName: '캄보디아->라오스 육로',
      filePrefix: 'KH_LA_LAND',
      boxPrefix: 'CBL',
      receiptPrefix: 'LKCBL',
    ),
  ];

  static Map<String, RouteDefinition> _runtime = const {};

  static List<RouteDefinition> get definitions {
    if (_runtime.isEmpty) return List.unmodifiable(_builtIns);
    final merged = <String, RouteDefinition>{
      for (final item in _builtIns) item.routeKey: item,
      ..._runtime,
    };
    return merged.values
        .where((item) => item.status == 'active')
        .toList(growable: false);
  }

  static List<String> get all => <String>[
        '전체',
        ...definitions.map((e) => e.displayName),
      ];

  static List<String> get routes => all.skip(1).toList(growable: false);

  static void applyDatabaseDefinitions(List<Map<String, dynamic>> rows) {
    final next = <String, RouteDefinition>{};
    for (final row in rows) {
      final item = RouteDefinition.fromMap(row);
      if (item.routeKey.isEmpty ||
          item.displayName.isEmpty ||
          item.status != 'active') {
        continue;
      }
      next[item.routeKey] = item;
    }
    _runtime = Map.unmodifiable(next);
  }

  static RouteDefinition? definitionForKey(String key) {
    final runtime = _runtime[key];
    if (runtime != null) return runtime;
    for (final item in _builtIns) {
      if (item.routeKey == key) return item;
    }
    return null;
  }

  static RouteDefinition? definitionForLabel(String label) {
    if (label == '전체') return null;
    for (final item in definitions) {
      if (item.displayName == label) return item;
    }
    return null;
  }

  static String keyFor(String labelOrKey) {
    if (labelOrKey == '전체') return 'all';
    final byLabel = definitionForLabel(labelOrKey);
    if (byLabel != null) return byLabel.routeKey;
    final byKey = definitionForKey(labelOrKey);
    return byKey?.routeKey ?? labelOrKey;
  }

  static String labelForKey(String key) =>
      definitionForKey(key)?.displayName ?? key;

  static String filePrefixFor(String labelOrKey) =>
      definitionForKey(keyFor(labelOrKey))?.filePrefix ?? '';

  static String boxPrefixFor(String labelOrKey) =>
      definitionForKey(keyFor(labelOrKey))?.boxPrefix ?? '';

  static String baseRouteKeyFor(String labelOrKey) {
    final key = keyFor(labelOrKey);
    final definition = definitionForKey(key);
    final base = definition?.baseRouteKey.trim() ?? '';
    return base.isEmpty ? key : base;
  }

  /// 신규 운송 경로는 선택한 기존 BASE의 번들 명세서/가견적 폼을 재사용합니다.
  static String formRouteKeyFor(String labelOrKey) =>
      baseRouteKeyFor(labelOrKey);

  static String boxExampleFor(String labelOrKey) {
    final key = keyFor(labelOrKey);
    const builtIn = <String, String>{
      'kr_la_sea': 'S001',
      'kr_la_air': 'A001',
      'la_kr_air_exp': 'B01-01',
      'la_th_land': 'LT01-01',
      'th_la_land': 'TL01-01',
      'la_vn_land': 'LV01-01',
      'vn_la_land': 'VL01-01',
      'la_ch_land': 'LC01-01',
      'ch_la_land': 'CL01-01',
      'la_kh_land': 'LCB10-01',
      'kh_la_land': 'CBL10-01',
    };
    final fixed = builtIn[key];
    if (fixed != null) return fixed;
    final prefix = boxPrefixFor(labelOrKey);
    return prefix.isEmpty ? '' : '${prefix}01-01';
  }

  static String receiptExampleFor(String labelOrKey) {
    final key = keyFor(labelOrKey);
    const builtIn = <String, String>{
      'kr_la_sea': 'LKS 01',
      'kr_la_air': 'LKA 01',
      'la_kr_air_exp': 'LKB2026xx-xx',
      'la_th_land': 'LKLT2026xx-xx',
      'th_la_land': 'LKTL2026xx-xx',
      'la_vn_land': 'LKLV2026xx-xx',
      'vn_la_land': 'LKVL2026xx-xx',
      'la_ch_land': 'LC2026xx-xx',
      'ch_la_land': 'LKCL2026xx-xx',
      'la_kh_land': 'LKLCB2026xx-xx',
      'kh_la_land': 'LKCBL2026xx-xx',
    };
    final fixed = builtIn[key];
    if (fixed != null) return fixed;
    final prefix = definitionForKey(key)?.receiptPrefix ?? '';
    return prefix.isEmpty ? '' : '${prefix}2026xx-xx';
  }

  static String? keyFromFileName(String fileName) {
    final upper = fileName.toUpperCase();
    for (final item in definitions) {
      final prefix = item.filePrefix.trim().toUpperCase();
      if (prefix.isNotEmpty && upper.startsWith(prefix)) {
        return item.routeKey;
      }
    }
    return null;
  }

  static String labelFor(String label) => <String, String>{
        '전체': 'All',
        '한국->라오스 해상': 'Korea -> Laos Sea',
        '한국->라오스 항공': 'Korea -> Laos Air',
        '라오스->한국 항공 특송': 'Laos -> Korea Air Express',
        '라오스->태국 육로': 'Laos -> Thailand Land',
        '태국->라오스 육로': 'Thailand -> Laos Land',
        '라오스->베트남 육로': 'Laos -> Vietnam Land',
        '베트남->라오스 육로': 'Vietnam -> Laos Land',
        '라오스->중국 육로': 'Laos -> China Land',
        '중국->라오스 육로': 'China -> Laos Land',
        '라오스->캄보디아 육로': 'Laos -> Cambodia Land',
        '캄보디아->라오스 육로': 'Cambodia -> Laos Land',
      }[label] ??
      label;
}
