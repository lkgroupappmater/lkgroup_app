// lib/core/route_catalog.dart
/// 앱 전체에서 공통으로 사용하는 운송 경로 목록입니다.
/// TODO: 운영 DB의 routes 테이블에서 관리자가 추가·수정한 목록을 불러오세요.
const List<String> routeLabels = RouteCatalog.all;

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

  static List<String> get routes => all.skip(1).toList(growable: false);

  static String keyFor(String label) => <String, String>{
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
      }[label] ?? label;

  static String labelFor(String label) => <String, String>{
        '전체': 'All',
        '한국->라오스 해상': 'Korea -> Laos Sea',
        '한국->라오스 항공': 'Korea -> Laos Air',
        '라오스->한국 항공 특송': 'Laos -> Korea Air Express',
        '라오스->태국 육로': 'Laos -> Thailand Road',
        '라오스->베트남 육로': 'Laos -> Vietnam Road',
        '라오스->중국 육로': 'Laos -> China Road',
        '라오스->캄보디아 육로': 'Laos -> Cambodia Road',
        '태국->라오스 육로': 'Thailand -> Laos Road',
        '베트남->라오스 육로': 'Vietnam -> Laos Road',
        '중국->라오스 육로': 'China -> Laos Road',
        '캄보디아->라오스 육로': 'Cambodia -> Laos Road',
      }[label] ?? label;
}

