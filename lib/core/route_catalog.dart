// lib/core/route_catalog.dart

/// 공통 운송 경로 목록. 연도·항차는 DB 값으로 교체할 수 있도록 별도 관리합니다.
class RouteCatalog {
  RouteCatalog._();

  static const List<String> all = [
    '전체',
    '한국->라오스 해상',
    '한국->라오스 항공',
    '라오스->한국 항공 특송',
    '라오스->태국 육로',
    '라오스->베트남 육로',
    '라오스->중국 육로',
    '라오스->캄보디아 육로',
    '태국->라오스 육로',
    '베트남->라오스 육로',
    '중국->라오스 육로',
    '캄보디아->라오스 육로',
  ];

  static List<String> get routes => all.sublist(1);

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
      '태국->라오스 육로': 'th_la_road',
      '베트남->라오스 육로': 'vn_la_road',
      '중국->라오스 육로': 'cn_la_road',
      '캄보디아->라오스 육로': 'kh_la_road',
    };
    return map[label] ?? label;
  }

  static String labelFor(String label) => label;
}

