import 'app_language.dart';
class CargoEntryText {
  static String value(AppLanguage language, String key) {
    const copy = {
      'number': ['자동 화물번호(임의 수정 가능)', 'Automatic cargo number (editable)', 'ເລກສິນຄ້າອັດຕະໂນມັດ (ແກ້ໄຂໄດ້)'],
      'matched': ['같은 항차의 고객 정보로 구획·비고를 채웠습니다. 수정하거나 지울 수 있습니다.', 'Zone and notes filled from this customer in the same voyage. You can edit or clear them.', 'ຕື່ມເຂດ ແລະ ໝາຍເຫດຈາກລູກຄ້າໃນຖ້ຽວດຽວກັນແລ້ວ. ສາມາດແກ້ໄຂ ຫຼື ລຶບໄດ້.'],
      'ambiguous': ['같은 고객의 구획·비고가 서로 달라 직접 확인해 주세요.', 'This customer has different zones or notes. Please check and enter them.', 'ເຂດ ຫຼື ໝາຍເຫດຂອງລູກຄ້ານີ້ແຕກຕ່າງກັນ. ກະລຸນາກວດສອບ ແລະ ປ້ອນເອງ.'],
      'error': ['고객 정보 확인이 지연됩니다. 구획·비고를 직접 입력할 수 있습니다.', 'Customer lookup is unavailable. You can enter the zone and notes manually.', 'ບໍ່ສາມາດກວດຂໍ້ມູນລູກຄ້າໄດ້. ສາມາດປ້ອນເຂດ ແລະ ໝາຍເຫດເອງໄດ້.'],
    };
    return copy[key]?[language == AppLanguage.english ? 1 : language == AppLanguage.lao ? 2 : 0] ?? '';
  }
}
