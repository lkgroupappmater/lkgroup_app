// lib/core/app_language.dart
// Full replacement – keeps enum, adds flag helpers and consultation templates.
// TODO: Connect to admin/DB for runtime language override and AI translation API.

enum AppLanguage { korean, english, lao }

// ── Flag & label helpers ─────────────────────────────────────────────────────
extension AppLanguageExt on AppLanguage {
  String get flag {
    switch (this) {
      case AppLanguage.korean:
        return '🇰🇷';
      case AppLanguage.english:
        return '🇬🇧';
      case AppLanguage.lao:
        return '🇱🇦';
    }
  }

  String get label {
    switch (this) {
      case AppLanguage.korean:
        return '한국어';
      case AppLanguage.english:
        return 'English';
      case AppLanguage.lao:
        return 'ລາວ';
    }
  }

  String get flagLabel => '${flag}  ${label}';
}

// ── UI string map ─────────────────────────────────────────────────────────────
// TODO: Replace with proper i18n resource files or admin-configurable strings.
class AppStrings {
  static String get(AppLanguage lang, String key) {
    return _strings[lang]?[key] ?? _strings[AppLanguage.korean]?[key] ?? key;
  }

  static const _strings = <AppLanguage, Map<String, String>>{
    AppLanguage.korean: {
      'home': '홈',
      'home_title': 'LK Group',
      'tracking': '화물 조회',
      'tracking_title': '화물 조회',
      'quote': '견적 요청',
      'quote_title': '견적 요청',
      'account': '계정',
      'account_title': '사용자 로그인',
      'consultation': '상담하기',
      'consultation_title': 'CargoFlow 상담',
      'consultation_status': 'AI 상담 준비 중',
      'consultation_hint': '궁금하신 내용을 입력하세요',
      'consultation_send': '전송',
      'consultation_notice':
      '운송 일정·견적·화물 조회·통관 안내는 기본 안내를 제공하며,\n실제 AI 상담은 서버/API 연결 후 활성화됩니다.',
      'consultation_submitted':
      '상담 요청이 접수되었습니다. 담당자가 확인 후 안내드리겠습니다.',
      'chip_schedule': '운송 일정',
      'chip_quote': '운임 견적',
      'chip_tracking': '화물 조회',
      'chip_customs': '통관 안내',
      'contact_title': '상담 및 연락처',
      'notices': '공지사항',
      'schedule': '운송 일정',
      'admin_link_needed': '관리자 링크 설정 필요',
      'link_placeholder_msg': '이 연락처의 링크가 아직 설정되지 않았습니다.\n관리자에게 문의하세요.',
      'close': '닫기',
      'notifications': '알림',
      'no_notifications': '새 알림이 없습니다.',
    },
    AppLanguage.english: {
      'home': 'Home',
      'home_title': 'LK Group',
      'tracking': 'Tracking',
      'tracking_title': 'Cargo Tracking',
      'quote': 'Quote',
      'quote_title': 'Quote Request',
      'account': 'Account',
      'account_title': 'User Login',
      'consultation': 'Consult',
      'consultation_title': 'CargoFlow Support',
      'consultation_status': 'AI Chat Coming Soon',
      'consultation_hint': 'Type your question here',
      'consultation_send': 'Send',
      'consultation_notice':
      'Basic guidance for schedule, quote, tracking & customs.\nFull AI chat activates after server/API connection.',
      'consultation_submitted':
      'Your inquiry has been received. Our team will get back to you shortly.',
      'chip_schedule': 'Schedule',
      'chip_quote': 'Quote',
      'chip_tracking': 'Tracking',
      'chip_customs': 'Customs',
      'contact_title': 'Contact & Support',
      'notices': 'Notices',
      'schedule': 'Schedule',
      'admin_link_needed': 'Admin link not configured',
      'link_placeholder_msg':
      'The link for this contact has not been set yet.\nPlease contact the administrator.',
      'close': 'Close',
      'notifications': 'Notifications',
      'no_notifications': 'No new notifications.',
    },
    AppLanguage.lao: {
      'home': 'ໜ້າຫຼັກ',
      'home_title': 'LK Group',
      'tracking': 'ຕິດຕາມສິນຄ້າ',
      'tracking_title': 'ຕິດຕາມສິນຄ້າ',
      'quote': 'ຂໍລາຄາ',
      'quote_title': 'ຂໍລາຄາ',
      'account': 'ບັນຊີ',
      'account_title': 'ເຂົ້າສູ່ລະບົບ',
      'consultation': 'ປຶກສາ',
      'consultation_title': 'CargoFlow ສະໜັບສະໜູນ',
      'consultation_status': 'AI ກຳລັງກຽມ',
      'consultation_hint': 'ພິມຄຳຖາມຂອງທ່ານ',
      'consultation_send': 'ສົ່ງ',
      'consultation_notice':
      'ໃຫ້ຄຳແນະນຳພື້ນຖານດ້ານຕາຕະລາງ, ລາຄາ, ການຕິດຕາມ & ພາສີ.\nAI ຈະເປີດໃຊ້ຫຼັງຈາກເຊື່ອມຕໍ່ server/API.',
      'consultation_submitted':
      'ໄດ້ຮັບຄຳຮ້ອງຂໍຂອງທ່ານແລ້ວ. ທີມງານຈະຕິດຕໍ່ກັບທ່ານ.',
      'chip_schedule': 'ຕາຕະລາງ',
      'chip_quote': 'ລາຄາ',
      'chip_tracking': 'ຕິດຕາມ',
      'chip_customs': 'ພາສີ',
      'contact_title': 'ຕິດຕໍ່ & ສະໜັບສະໜູນ',
      'notices': 'ແຈ້ງການ',
      'schedule': 'ຕາຕະລາງ',
      'admin_link_needed': 'ຜູ້ດູແລລະບົບຍັງບໍ່ໄດ້ຕັ້ງຄ່າ',
      'link_placeholder_msg':
      'ລິ້ງຂອງຜູ້ຕິດຕໍ່ນີ້ຍັງບໍ່ໄດ້ຕັ້ງ.\nກະລຸນາຕິດຕໍ່ຜູ້ດູແລລະບົບ.',
      'close': 'ປິດ',
      'notifications': 'ການແຈ້ງເຕືອນ',
      'no_notifications': 'ບໍ່ມີການແຈ້ງເຕືອນໃໝ່.',
    },
  };
}

// ── Contact items ─────────────────────────────────────────────────────────────
// TODO: Load URLs from admin panel / Firestore / REST API instead of placeholders.
class ContactItem {
  final String label;
  final String icon;   // semantic key used by UI
  final String url;    // TODO: replace with real URL from admin/DB

  const ContactItem({
    required this.label,
    required this.icon,
    required this.url,
  });
}

const List<ContactItem> kContactItems = [
  ContactItem(
    label: '카카오톡 단톡방',
    icon: 'kakao_group',
    url: 'https://placeholder.kakao.group', // TODO: set real KakaoTalk group URL
  ),
  ContactItem(
    label: '오픈상담톡(한글)',
    icon: 'open_chat_kr',
    url: 'https://placeholder.kakao.openchat.kr', // TODO: set real open chat URL (KR)
  ),
  ContactItem(
    label: '오픈상담톡(English)',
    icon: 'open_chat_en',
    url: 'https://placeholder.kakao.openchat.en', // TODO: set real open chat URL (EN)
  ),
  ContactItem(
    label: '오픈상담톡(ລາວ)',
    icon: 'open_chat_lo',
    url: 'https://placeholder.kakao.openchat.lo', // TODO: set real open chat URL (LO)
  ),
  ContactItem(
    label: '카카오톡(대표번호)',
    icon: 'kakao_rep',
    url: 'https://placeholder.kakao.rep', // TODO: set real KakaoTalk representative URL
  ),
  ContactItem(
    label: 'WhatsApp(대표번호)',
    icon: 'whatsapp',
    url: 'https://wa.me/placeholder',  // TODO: set real WhatsApp number
  ),
  ContactItem(
    label: 'Facebook',
    icon: 'facebook',
    url: 'https://facebook.com/placeholder', // TODO: set real Facebook page URL
  ),
  ContactItem(
    label: '네이버',
    icon: 'naver',
    url: 'https://placeholder.naver.com', // TODO: set real Naver channel URL
  ),
];




