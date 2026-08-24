// lib/core/route_catalog.dart

/// All cargo route labels used across shipment search, quote screens, etc.
class RouteCatalog {
  RouteCatalog._();

  /// Full ordered list including the "all" sentinel at index 0.
  static const List<String> all = [
    '전체',
    '한국->라오스 해상',
    '한국->라오스 항공',
    '라오스->한국 항공 특송',
    '라오스->태국 육로',
    '라오스->베트남 육로',
    '라오스->중국 육로',
    '라오스->캄보디아 육로',
  ];

  /// Routes excluding the "all" sentinel – used in quote dropdown.
  static List<String> get routes => all.sublist(1);

  /// Short snake_case key for a label (for API / storage).
  static String keyFor(String label) {
    const map = {
      '전체': 'all',
      '한국->라오스 해상': 'kr_la_sea',
      '한국->라오스 항공': 'kr_la_air',
      '라오스->한국 항공 특송': 'la_kr_express',
      '라오스->태국 육로': 'la_th_road',
      '라오스->베트남 육로': 'la_vn_road',
      '라오스->중국 육로': 'la_cn_road',
      '라오스->캄보디아 육로': 'la_kh_road',
    };
    return map[label] ?? label;
  }

  /// English label for a Korean route string (for display / API).
  static String labelFor(String label) {
    const map = {
      '전체': 'All',
      '한국->라오스 해상': 'Korea–Laos Sea',
      '한국->라오스 항공': 'Korea–Laos Air',
      '라오스->한국 항공 특송': 'Laos–Korea Air Express',
      '라오스->태국 육로': 'Laos–Thailand Road',
      '라오스->베트남 육로': 'Laos–Vietnam Road',
      '라오스->중국 육로': 'Laos–China Road',
      '라오스->캄보디아 육로': 'Laos–Cambodia Road',
    };
    return map[label] ?? label;
  }
}
