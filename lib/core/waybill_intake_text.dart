import 'app_language.dart';
import 'domestic_tracking_text.dart';

const intakeWords = <String, List<String>> {
  'close': ['닫기', 'Close', 'ປິດ'],
  "auto": [
    "배송장 자동 등록",
    "Automatic waybill registration",
    "ລົງທະບຽນໃບສົ່ງອັດຕະໂນມັດ"
  ],
  "limits": [
    "최대 50장 · 개당 5MB · 합계 250MB (JPG/PNG/WebP)",
    "Up to 50 images · 5MB each · 250MB total (JPG/PNG/WebP)",
    "ສູງສຸດ 50 ຮູບ · 5MB/ຮູບ · ລວມ 250MB (JPG/PNG/WebP)"
  ],
  "review": [
    "사진과 인식 결과·연결 고객을 확인해 주세요. 확인한 송장만 최종 등록됩니다.",
    "Check each photo, extracted details and recipient link. Only reviewed waybills will be registered.",
    "ກວດຮູບ, ຂໍ້ມູນ ແລະ ຜູ້ຮັບ. ລົງທະບຽນສະເພາະໃບທີ່ຢືນຢັນ."
  ],
  "pick": [
    "송장 사진 선택",
    "Select waybill images",
    "ເລືອກຮູບໃບສົ່ງ"
  ],
  "reviewed": [
    "사진·번호·업체·고객 확인 완료",
    "Photo, number, carrier and recipient checked",
    "ກວດຮູບ, ເລກ, ບໍລິສັດ ແລະ ຜູ້ຮັບແລ້ວ"
  ],
  "confirm": [
    "확인한 송장 최종 등록",
    "Register reviewed waybills",
    "ລົງທະບຽນໃບທີ່ຢືນຢັນ"
  ],
  "match": [
    "고객·명세서 연결 확인",
    "Confirm customer / statement link",
    "ຢືນຢັນຜູ້ຮັບ / ໃບລາຍການ"
  ],
  "unmatched": [
    "연결 대상 선택 필요",
    "Select a link target",
    "ກະລຸນາເລືອກລາຍການເຊື່ອມ"
  ],
  "separate": [
    "별도 국내배송으로 등록",
    "Register as a separate delivery",
    "ລົງທະບຽນເປັນການຈັດສົ່ງແຍກ"
  ],
  "failed": [
    "자동 인식 실패: 사진을 보고 직접 입력하거나 다시 시도하세요.",
    "Recognition failed: enter the details from the photo or retry.",
    "ອ່ານຮູບບໍ່ໄດ້: ປ້ອນຂໍ້ມູນເອງ ຫຼື ລອງໃໝ່."
  ],
  "pending": [
    "확인 대기",
    "Awaiting review",
    "ລໍຖ້າກວດ"
  ],
  "media": [
    "송장번호·송장/박스 사진 관리",
    "Manage tracking number and waybill / box photos",
    "ຈັດການເລກໃບສົ່ງ ແລະ ຮູບໃບສົ່ງ / ກ່ອງ"
  ],
  "waybill": [
    "송장 사진",
    "Waybill photo",
    "ຮູບໃບສົ່ງ"
  ],
  "box": [
    "박스 사진",
    "Box photo",
    "ຮູບກ່ອງ"
  ],
  "customers": [
    "고객 ID 관리",
    "Customer ID management",
    "ຈັດການ ID ລູກຄ້າ"
  ],
  "conflict": [
    "동명이인·전화번호 불일치 확인",
    "Review matching names / different phones",
    "ກວດຊື່ຊ້ຳ / ເບີໂທບໍ່ກົງ"
  ],
  "fixed": [
    "발급된 ID는 유지됩니다. 총괄 관리자만 변경할 수 있습니다.",
    "Issued IDs remain fixed. Only a general administrator can change them.",
    "ID ທີ່ອອກແລ້ວຈະຄົງທີ່. ສະເພາະຜູ້ດູແລຫຼັກສາມາດປ່ຽນໄດ້."
  ],
  "reason": [
    "변경 사유",
    "Reason for change",
    "ເຫດຜົນທີ່ປ່ຽນ"
  ],
  "error": [
    "처리하지 못했습니다. 입력값을 확인한 뒤 다시 시도해 주세요.",
    "Unable to complete. Check the details and retry.",
    "ດຳເນີນການບໍ່ໄດ້. ກວດຂໍ້ມູນແລ້ວລອງໃໝ່."
  ],
  "REVIEW_REQUIRED": [
    "모든 등록 대상 송장을 확인해 주세요.",
    "Review every waybill selected for registration.",
    "ກວດທຸກໃບສົ່ງທີ່ຈະລົງທະບຽນ."
  ],
  "DUPLICATE_RECORD": [
    "ID 또는 송장이 이미 사용 중입니다. 다시 확인해 주세요.",
    "The ID or waybill is already in use. Check again.",
    "ID ຫຼື ໃບສົ່ງນີ້ຖືກໃຊ້ແລ້ວ."
  ],
  "OCR_NOT_CONFIGURED": [
    "자동 인식 서버 설정을 확인해야 합니다. 직접 입력은 가능합니다.",
    "Recognition is not configured. You can enter details manually.",
    "ການອ່ານອັດຕະໂນມັດຍັງບໍ່ພ້ອມ. ປ້ອນເອງໄດ້."
  ],
  "UPLOAD_INCOMPLETE": [
    "사진 업로드가 완료되지 않았습니다. 다시 시도하세요.",
    "Photo upload is incomplete. Retry.",
    "ອັບໂຫຼດຮູບບໍ່ຄົບ. ລອງໃໝ່."
  ],
  "BATCH_EXPIRED": [
    "하루가 지나 대기 작업이 만료됐습니다. 사진을 다시 선택하세요.",
    "This draft expired after 24 hours. Select the photos again.",
    "ຮ່າງໝົດອາຍຸຫຼັງ 24 ຊົ່ວໂມງ. ເລືອກຮູບໃໝ່."
  ]
};
String intakeText(AppLanguage language, String key) => intakeWords[key]?[language.index] ?? domesticText(language, key);
