import 'app_language.dart';
import 'domestic_tracking_text.dart';

const intakeWords = <String, List<String>> {
  "close": [
    "닫기",
    "Close",
    "ປິດ"
  ],
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
    "변경 사유 (선택)",
    "Reason for change (optional)",
    "ເຫດຜົນທີ່ປ່ຽນ (ບໍ່ບັງຄັບ)"
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
    "ID·이름/전화번호 조합 또는 송장이 이미 사용 중입니다. 고객 중복이면 통합 기능으로 검토하세요.",
    "The ID, name / phone pair or waybill is already in use. Review a merge for duplicate customers.",
    "ID, ຊື່/ເບີໂທ ຫຼື ໃບສົ່ງຖືກໃຊ້ແລ້ວ. ຖ້າລູກຄ້າຊ້ຳ ໃຫ້ກວດການລວມ."
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
  ],
  "selectAll": [
    "전체 송장 확인·선택",
    "Check and select all waybills",
    "ຢືນຢັນ ແລະ ເລືອກໃບສົ່ງທັງໝົດ"
  ],
  "fixedRecipient": [
    "수령인은 선택한 명세서·화물 정보를 사용합니다. 사진에서 송장번호와 배송업체만 확인합니다.",
    "Recipient details come from the selected statement or cargo. Only the tracking number and carrier are read from the photo.",
    "ໃຊ້ຂໍ້ມູນຜູ້ຮັບຈາກໃບລາຍການທີ່ເລືອກ. ອ່ານສະເພາະເລກໃບສົ່ງ ແລະ ບໍລິສັດຈາກຮູບ."
  ],
  "duplicates": [
    "중복·유사 고객",
    "Duplicate / similar customers",
    "ລູກຄ້າຊ້ຳ / ຄ້າຍກັນ"
  ],
  "mismatches": [
    "고객 ID 불일치",
    "Customer ID mismatches",
    "ID ລູກຄ້າບໍ່ກົງ"
  ],
  "sourceRows": [
    "연결 자료",
    "Linked records",
    "ຂໍ້ມູນທີ່ເຊື່ອມ"
  ],
  "reviewStatus": [
    "중복·연결 검토",
    "Review duplicates / links",
    "ກວດລາຍການຊ້ຳ / ການເຊື່ອມ"
  ],
  "total": [
    "전체 고객",
    "All customers",
    "ລູກຄ້າທັງໝົດ"
  ],
  "reset": [
    "필터 초기화",
    "Reset filters",
    "ລ້າງຕົວກອງ"
  ],
  "mergeHelp": [
    "동일 고객인지 비교한 뒤 남길 ID를 선택하세요. 통합하면 연결 자료와 확인된 이름·전화번호 표기가 선택한 ID로 이어집니다. 기존 화물 내역과 로그인 권한은 유지됩니다.",
    "Compare the customers and choose the ID to keep. Merging transfers linked records and reviewed name / phone variants. Historical cargo and login permissions remain unchanged.",
    "ກວດວ່າເປັນລູກຄ້າຄົນດຽວກັນ ແລ້ວເລືອກ ID ທີ່ຈະເກັບໄວ້. ຂໍ້ມູນເຊື່ອມ ແລະ ຊື່/ເບີໂທທີ່ຢືນຢັນຈະຖືກລວມ. ປະຫວັດສິນຄ້າ ແລະ ສິດເຂົ້າໃຊ້ຍັງຄົງເດີມ."
  ],
  "findTarget": [
    "남길 ID / 이름 / 전화번호 검색",
    "Find ID / name / phone to keep",
    "ຄົ້ນຫາ ID / ຊື່ / ເບີໂທທີ່ຈະເກັບ"
  ],
  "keepId": [
    "남길 고객 ID",
    "Customer ID to keep",
    "ID ລູກຄ້າທີ່ຈະເກັບ"
  ],
  "fromId": [
    "통합할 고객 ID",
    "Customer ID to merge",
    "ID ລູກຄ້າທີ່ຈະລວມ"
  ],
  "mergePreview": [
    "통합 내용 확인",
    "Review merge",
    "ກວດການລວມ"
  ],
  "mergedTotal": [
    "통합 후 연결 자료 수",
    "Linked records after merge",
    "ຈຳນວນຂໍ້ມູນຫຼັງລວມ"
  ],
  "sameCustomer": [
    "두 ID가 같은 고객임을 확인했습니다",
    "I confirmed both IDs belong to the same customer",
    "ຢືນຢັນວ່າທັງສອງ ID ເປັນລູກຄ້າຄົນດຽວກັນ"
  ],
  "merge": [
    "확인 후 통합",
    "Confirm merge",
    "ຢືນຢັນການລວມ"
  ],
  "noCandidates": [
    "중복 후보가 없습니다. ID·이름·전화번호로 검색할 수 있습니다.",
    "No duplicate candidates. Search by ID, name or phone.",
    "ບໍ່ມີລາຍການຊ້ຳ. ຄົ້ນຫາດ້ວຍ ID, ຊື່ ຫຼື ເບີໂທໄດ້."
  ],
  "sourceHelp": [
    "불일치 자료는 올바른 ID를 고른 후 연결을 확인하세요. 해당 이름·전화번호 표기는 확인된 별칭으로 기억합니다. 이미 다른 ID에 등록된 표기는 먼저 고객 통합을 검토하세요.",
    "For mismatched records, choose the correct ID and confirm the link. This name / phone variant will be remembered. If it belongs to another ID, review a merge first.",
    "ເລືອກ ID ທີ່ຖືກຕ້ອງແລ້ວຢືນຢັນການເຊື່ອມ. ລະບົບຈະຈື່ຊື່/ເບີໂທນີ້. ຖ້າມີໃນ ID ອື່ນ ໃຫ້ກວດການລວມກ່ອນ."
  ],
  "resolveSource": [
    "이 ID로 연결 확인",
    "Confirm this ID link",
    "ຢືນຢັນເຊື່ອມ ID ນີ້"
  ],
  "same_name": [
    "동일 이름",
    "Same name",
    "ຊື່ດຽວກັນ"
  ],
  "same_phone": [
    "동일 전화번호",
    "Same phone",
    "ເບີໂທດຽວກັນ"
  ],
  "similar_name": [
    "이름 한 글자 차이",
    "Name differs by one character",
    "ຊື່ຕ່າງກັນໜຶ່ງຕົວ"
  ],
  "similar_phone": [
    "전화번호 한 자리 차이",
    "Phone differs by one digit",
    "ເບີໂທຕ່າງກັນໜຶ່ງຕົວ"
  ],
  "RESERVED_CUSTOMER_ID": [
    "고정 ID 001·002는 다른 ID로 통합하거나 번호를 변경할 수 없습니다. 해당 ID를 남길 ID로 선택하세요.",
    "Reserved IDs 001 and 002 cannot be renumbered or merged away. Select them as the ID to keep.",
    "ປ່ຽນເລກ ຫຼື ລວມ ID 001 ແລະ 002 ເຂົ້າ ID ອື່ນບໍ່ໄດ້. ເລືອກເປັນ ID ທີ່ຈະເກັບ."
  ],
  "RECORD_CHANGED": [
    "다른 곳에서 자료가 변경됐습니다. 새로 조회한 뒤 다시 확인해 주세요.",
    "This record changed elsewhere. Reload and review again.",
    "ຂໍ້ມູນຖືກປ່ຽນຈາກບ່ອນອື່ນ. ໂຫຼດໃໝ່ແລ້ວກວດອີກຄັ້ງ."
  ],
  "refresh": [
    "새로고침",
    "Refresh",
    "ໂຫຼດໃໝ່"
  ],
  "photoMode": [
    "사진 종류",
    "Photo type",
    "ປະເພດຮູບ"
  ],
  "recognizeWaybill": [
    "송장 인식 후 확인·등록",
    "Recognize and review waybills",
    "ອ່ານໃບສົ່ງ ແລ້ວກວດລົງທະບຽນ"
  ],
  "referencePhotos": [
    "화물 참고 사진 (송장 인식 없음)",
    "Cargo reference photos (no recognition)",
    "ຮູບປະກອບສິນຄ້າ (ບໍ່ອ່ານໃບສົ່ງ)"
  ],
  "referenceHelp": [
    "송장번호·배송업체 확인 없이 선택한 명세서·화물에 사진을 첨부합니다.",
    "Attach photos to the selected statement or cargo without a tracking number or carrier.",
    "ແນບຮູບໃສ່ໃບລາຍການ ຫຼື ສິນຄ້າທີ່ເລືອກ ໂດຍບໍ່ຕ້ອງລະບຸເລກໃບສົ່ງ ຫຼື ບໍລິສັດ."
  ],
  "uploadPhotos": [
    "사진 바로 올리기",
    "Upload photos now",
    "ອັບໂຫຼດຮູບທັນທີ"
  ]

};
String intakeText(AppLanguage language, String key) => intakeWords[key]?[language.index] ?? domesticText(language, key);
