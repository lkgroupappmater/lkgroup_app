// lib/core/route_catalog.dart
import 'app_language.dart';
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
    this.documentTitle = '',
    this.remark = '',
    this.baseRouteKey = '',
    this.status = 'active',
  });

  final String routeKey;
  final String displayName;
  final String filePrefix;
  final String boxPrefix;
  final String receiptPrefix;
  final String documentTitle;
  final String remark;
  final String baseRouteKey;
  final String status;

  factory RouteDefinition.fromMap(Map<String, dynamic> row) {
    return RouteDefinition(
      routeKey: '${row['route_key'] ?? ''}'.trim(),
      displayName: '${row['display_name'] ?? ''}'.trim(),
      filePrefix: '${row['file_prefix'] ?? ''}'.trim(),
      boxPrefix: '${row['box_prefix'] ?? ''}'.trim(),
      receiptPrefix: '${row['receipt_prefix'] ?? ''}'.trim(),
      documentTitle: '${row['document_title'] ?? ''}'.trim(),
      remark: '${row['remark'] ?? ''}'.trim(),
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
  static bool _databaseLoaded = false;

  static List<RouteDefinition> get definitions {
    if (!_databaseLoaded) return List.unmodifiable(_builtIns);
    final active = _runtime.values
        .where((item) => item.status == 'active')
        .toList();
    // Keep the same business order in every language and with older servers.
    // Newly added routes follow the eleven standard routes in server order.
    final order = <String, int>{
      for (var i = 0; i < active.length; i++) active[i].routeKey: 100 + i,
      for (var i = 0; i < _builtIns.length; i++) _builtIns[i].routeKey: i,
    };
    active.sort((a, b) => order[a.routeKey]!.compareTo(order[b.routeKey]!));
    return List.unmodifiable(active);
  }

  static List<String> get all => <String>[
        '전체',
        ...definitions.map((e) => e.displayName),
      ];

  static List<String> get routes => all.skip(1).toList(growable: false);

  static String localizedLabel(String displayName, AppLanguage language) {
    if (language == AppLanguage.korean || displayName == '전체') {
      return displayName == '전체'
          ? AppStrings.get(language, 'all')
          : displayName;
    }

    // Route names are operational keys, so translate them locally instead of
    // relying on an AI-generated database value. This also covers new routes
    // that follow the existing "country -> country + mode" naming convention.
    final parsed = _localizedKoreanRoute(displayName, language);
    if (parsed != null) return parsed;

    RouteDefinition? route;
    for (final item in definitions) {
      if (item.displayName == displayName || item.routeKey == displayName) {
        route = item;
        break;
      }
    }
    if (route == null) return displayName;
    const english = <String, String>{
      'kr_la_sea': 'Korea → Laos Sea',
      'kr_la_air': 'Korea → Laos Air',
      'la_kr_air_exp': 'Laos → Korea Air Express',
      'la_th_land': 'Laos → Thailand Land',
      'th_la_land': 'Thailand → Laos Land',
      'la_vn_land': 'Laos → Vietnam Land',
      'vn_la_land': 'Vietnam → Laos Land',
      'la_ch_land': 'Laos → China Land',
      'ch_la_land': 'China → Laos Land',
      'la_kh_land': 'Laos → Cambodia Land',
      'kh_la_land': 'Cambodia → Laos Land',
    };
    const lao = <String, String>{
      'kr_la_sea': 'ເກົາຫຼີ → ລາວ ທາງເຮືອ',
      'kr_la_air': 'ເກົາຫຼີ → ລາວ ທາງອາກາດ',
      'la_kr_air_exp': 'ລາວ → ເກົາຫຼີ ດ່ວນທາງອາກາດ',
      'la_th_land': 'ລາວ → ໄທ ທາງບົກ',
      'th_la_land': 'ໄທ → ລາວ ທາງບົກ',
      'la_vn_land': 'ລາວ → ຫວຽດນາມ ທາງບົກ',
      'vn_la_land': 'ຫວຽດນາມ → ລາວ ທາງບົກ',
      'la_ch_land': 'ລາວ → ຈີນ ທາງບົກ',
      'ch_la_land': 'ຈີນ → ລາວ ທາງບົກ',
      'la_kh_land': 'ລາວ → ກຳປູເຈຍ ທາງບົກ',
      'kh_la_land': 'ກຳປູເຈຍ → ລາວ ທາງບົກ',
    };
    return (language == AppLanguage.lao ? lao : english)[route.routeKey] ??
        displayName;
  }

  static String? _localizedKoreanRoute(
    String displayName,
    AppLanguage language,
  ) {
    final normalized = displayName
        .trim()
        .replaceAll('→', '->')
        .replaceAll(RegExp(r'\s*->\s*'), '->')
        .replaceAll(RegExp(r'\s+'), ' ');
    final match = RegExp(
      r'^(한국|라오스|태국|베트남|중국|캄보디아)->(한국|라오스|태국|베트남|중국|캄보디아)\s+(해상|항공 특송|항공|육로)$',
    ).firstMatch(normalized);
    if (match == null) return null;

    const englishCountries = <String, String>{
      '한국': 'Korea',
      '라오스': 'Laos',
      '태국': 'Thailand',
      '베트남': 'Vietnam',
      '중국': 'China',
      '캄보디아': 'Cambodia',
    };
    const laoCountries = <String, String>{
      '한국': 'ເກົາຫຼີ',
      '라오스': 'ລາວ',
      '태국': 'ໄທ',
      '베트남': 'ຫວຽດນາມ',
      '중국': 'ຈີນ',
      '캄보디아': 'ກຳປູເຈຍ',
    };
    const englishModes = <String, String>{
      '해상': 'Sea Freight',
      '항공': 'Air Freight',
      '항공 특송': 'Air Express',
      '육로': 'Land Transport',
    };
    const laoModes = <String, String>{
      '해상': 'ທາງເຮືອ',
      '항공': 'ທາງອາກາດ',
      '항공 특송': 'ດ່ວນທາງອາກາດ',
      '육로': 'ທາງບົກ',
    };

    final origin = match.group(1)!;
    final destination = match.group(2)!;
    final mode = match.group(3)!;
    if (language == AppLanguage.lao) {
      return '${laoCountries[origin]} → ${laoCountries[destination]} '
          '${laoModes[mode]}';
    }
    return '${englishCountries[origin]} → ${englishCountries[destination]} '
        '${englishModes[mode]}';
  }

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
    _databaseLoaded = true;
  }

  static RouteDefinition? definitionForKey(String key) {
    final runtime = _runtime[key];
    if (runtime != null) return runtime;
    if (_databaseLoaded) return null;
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
  /// 기존 내장/실제 경로는 자기 Excel form 제목을 그대로 사용하고,
  /// 신규 동적 경로가 다른 BASE form을 상속하는 경우에만 최소 title overlay를 허용합니다.
  static bool usesInheritedForm(String labelOrKey) {
    final key = keyFor(labelOrKey);
    return baseRouteKeyFor(labelOrKey) != key;
  }

  static String documentTitleFor(String labelOrKey) {
    final definition = definitionForKey(keyFor(labelOrKey));
    final title = definition?.documentTitle.trim() ?? '';
    return title.isEmpty ? (definition?.displayName ?? labelOrKey) : title;
  }

  static String remarkFor(String labelOrKey) =>
      definitionForKey(keyFor(labelOrKey))?.remark.trim() ?? '';

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
