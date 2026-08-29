// lib/core/route_catalog.dart
/// 앱 전체 공통 운송 경로.
/// 기존 경로를 삭제하지 않고, 공유받은 Excel 파일 코드와 1:1 매칭 정보를 추가했습니다.
const List<String> routeLabels = RouteCatalog.all;

class RouteCatalog {
  RouteCatalog._();

  static const List<String> all = [
    '전체',
    '한국->라오스 해상',
    '한국->라오스 항공',
    '라오스->한국 항공 특송',
    '라오스->태국 육로',
    '태국->라오스 육로',
    '라오스->베트남 육로',
    '베트남->라오스 육로',
    '라오스->중국 육로',
    '중국->라오스 육로',
    '라오스->캄보디아 육로',
    '캄보디아->라오스 육로',
  ];

  static List<String> get routes => all.skip(1).toList(growable: false);

  static const Map<String, String> _keys = {
    '전체': 'all',
    '한국->라오스 해상': 'kr_la_sea',
    '한국->라오스 항공': 'kr_la_air',
    '라오스->한국 항공 특송': 'la_kr_air_exp',
    '라오스->태국 육로': 'la_th_land',
    '태국->라오스 육로': 'th_la_land',
    '라오스->베트남 육로': 'la_vn_land',
    '베트남->라오스 육로': 'vn_la_land',
    '라오스->중국 육로': 'la_ch_land',
    '중국->라오스 육로': 'ch_la_land',
    '라오스->캄보디아 육로': 'la_kh_land',
    '캄보디아->라오스 육로': 'kh_la_land',
  };

  static const Map<String, String> _filePrefixes = {
    'kr_la_sea': 'KR_LA_SEA',
    'kr_la_air': 'KR_LA_AIR',
    'la_kr_air_exp': 'LA_KR_AIR_EXP',
    'la_th_land': 'LA_TH_LAND',
    'th_la_land': 'TH_LA_LAND',
    'la_vn_land': 'LA_VN_LAND',
    'vn_la_land': 'VN_LA_LAND',
    'la_ch_land': 'LA_CH_LAND',
    'ch_la_land': 'CH_LA_LAND',
    'la_kh_land': 'LA_KH_LAND',
    'kh_la_land': 'KH_LA_LAND',
  };

  // 실제 운송 Excel 양식의 박스/영수 번호 표기 규칙.
  // 2026 Cambodia 양방향 신규 BASE 기준:
  // LA->KH = LCB / LKLCB, KH->LA = CBL / LKCBL.
  static const Map<String, String> _boxPrefixes = {
    'kr_la_sea': 'S',
    'kr_la_air': 'A',
    'la_kr_air_exp': 'B',
    'la_th_land': 'LT',
    'th_la_land': 'TL',
    'la_vn_land': 'LV',
    'vn_la_land': 'VL',
    'la_ch_land': 'LC',
    'ch_la_land': 'CL',
    'la_kh_land': 'LCB',
    'kh_la_land': 'CBL',
  };

  static const Map<String, String> _boxExamples = {
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

  static const Map<String, String> _receiptExamples = {
    'kr_la_sea': 'LKS 01',
    'kr_la_air': 'LKA 01',
    'la_kr_air_exp': 'LKB2026xx-xx',
    'la_th_land': 'LKLT2026xx-xx',
    'th_la_land': 'LKTL2026xx-xx',
    'la_vn_land': 'LKLV2026xx-xx',
    'vn_la_land': 'LKVL2026xx-xx',
    'la_ch_land': 'LC2026xx-xx',
    'ch_la_land': 'LKCL2026xx-xx',
    'la_kh_land': 'LKLCB 2026xx-xx',
    'kh_la_land': 'LKCBL 2026xx-xx',
  };

  static String boxPrefixFor(String label) => _boxPrefixes[keyFor(label)] ?? '';
  static String boxExampleFor(String label) => _boxExamples[keyFor(label)] ?? '';
  static String receiptExampleFor(String label) => _receiptExamples[keyFor(label)] ?? '';

  static String keyFor(String label) => _keys[label] ?? label;
  static String filePrefixFor(String label) => _filePrefixes[keyFor(label)] ?? '';
  static String labelForKey(String key) {
    for (final entry in _keys.entries) {
      if (entry.value == key) return entry.key;
    }
    return key;
  }

  static String? keyFromFileName(String fileName) {
    final upper = fileName.toUpperCase();
    for (final entry in _filePrefixes.entries) {
      if (upper.startsWith(entry.value)) return entry.key;
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
