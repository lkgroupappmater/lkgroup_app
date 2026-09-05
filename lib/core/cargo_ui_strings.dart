import 'app_language.dart';

/// Cargo tracking/management-only fixed labels.
///
/// To change a translation, edit the value beside the same Korean key in
/// [_english] or [_lao]. Database values such as routes, customer names and
/// notes are intentionally not translated here.
class CargoUiStrings {
  CargoUiStrings._();

  static String get(AppLanguage language, String korean) {
    switch (language) {
      case AppLanguage.korean:
        return korean;
      case AppLanguage.english:
        return _english[korean] ?? korean;
      case AppLanguage.lao:
        return _lao[korean] ?? korean;
    }
  }

  static String format(
    AppLanguage language,
    String korean,
    Map<String, Object?> values,
  ) {
    var result = get(language, korean);
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return result;
  }

  static const Map<String, String> _english = {
    '전체': 'All',
    '확인': 'OK',
    '취소': 'Cancel',
    '닫기': 'Close',
    '추가': 'Add',
    '삭제': 'Delete',
    '편집': 'Edit',
    '저장': 'Save',
    '적용': 'Apply',
    '수정 저장': 'Save Changes',
    '검색 중...': 'Searching...',
    '운송 경로': 'Route',
    '년도': 'Year',
    '항차': 'Voyage',
    '박스번호': 'Box Number',
    '송장번호': 'Invoice Number',
    '화물번호': 'Cargo Number',
    '화물개수': 'Quantity',
    '이름': 'Name',
    '이름/라오스 수령인': 'Name / Laos Recipient',
    '이름/수령인': 'Name / Recipient',
    '수취인 이름 / 회사명': 'Recipient / Company',
    '본인 이름': 'Your Name',
    '연락처': 'Phone',
    '본인 연락처': 'Your Phone',
    '기타 내용': 'Notes',
    '비고': 'Notes',
    '무게(kg)': 'Weight (kg)',
    '가로(cm)': 'Length (cm)',
    '세로(cm)': 'Width (cm)',
    '높이(cm)': 'Height (cm)',
    '무게 / 크기': 'Weight / Size',
    '입고날짜': 'Received Date',
    '영수번호': 'Receipt Number',
    '영수번호/구획': 'Receipt / Zone',
    '영수번호 / 구획': 'Receipt / Zone',
    '총 개수': 'Total Quantity',
    '운임 확인': 'Check Freight',
    '화물 검색': 'Search Cargo',
    '화물 관리': 'Cargo Management',
    '화물 추가 입력': 'Add Cargo',
    '박스 추가 (행 추가)': 'Add Box Row',
    '화물 편집': 'Edit Cargo',
    '검색 결과 명세서': 'Search Result Statements',
    '선택 화물 삭제 대기': 'Move Selected Cargo to Pending Deletion',
    '삭제 대기': 'Pending Deletion',
    '삭제 취소': 'Cancel Deletion',
    '바로 삭제': 'Delete Now',
    '화물 삭제': 'Delete Cargo',
    '화물 바로 삭제': 'Delete Cargo Now',
    '일괄 저장': 'Save All',
    '이름 / 회사명': 'Name / Company',
    '중량 (kg)': 'Weight (kg)',
    '가로 (cm)': 'Length (cm)',
    '세로 (cm)': 'Width (cm)',
    '높이 (cm)': 'Height (cm)',
    '년도 / 항차': 'Year / Voyage',
    '화물 정보': 'Cargo Information',
    '선택한 화물 정보 수정': 'Edit Selected Cargo',
    '화물 정보 저장': 'Save Cargo',
    '화물 정보 수정 요청': 'Request Cargo Change',
    '체크 명세서 PDF': 'Selected Statements PDF',
    '화물 삭제 대기': 'Pending Cargo Deletion',
    '삭제 대기 중인 화물이 없습니다.': 'There is no cargo pending deletion.',
    '통합 관리': 'Integrated Management',
    '선적 일정 관리': 'Shipping Schedules',
    '공지사항 관리': 'Notice Management',
    '화물 종합 관리': 'Cargo Management',
    '엑셀 화물 업로드': 'Upload Cargo Excel',
    '회원 종합 관리': 'Member Management',
    '변경 승인 관리': 'Change Approvals',
    '견적 요청 관리': 'Quote Requests',
    '기준 환율 입력': 'Exchange Rates',
    '계정으로 돌아가기': 'Back to Account',
    '회원': 'Member',
    '명세서': 'Statement',
    '명세서 발급': 'Create Statement',
    '이미지': 'Image',
    '그룹 전체 운임': 'Group Freight Total',
    '영수번호별 명세서': 'Statements by Receipt',
    '추가 할인명': 'Discount Name',
    '할인율': 'Discount Rate',
    '할인 적용': 'Apply Discount',
    '할인 편집 / 삭제': 'Edit / Delete Discount',
    '비용 이름': 'Cost Name',
    '금액 (USD)': 'Amount (USD)',
    '기타 비용': 'Extra Cost',
    '선택 화물 편집': 'Edit Selected Cargo',
    '선택 화물 삭제': 'Delete Selected Cargo',
    '고객 단위 편집': 'Edit Customer Group',
    '잠금': 'Lock',
    '잠금 해제': 'Unlock',
    '불확실 화물 표시': 'Mark as Uncertain',
    '불확실 표시 해제': 'Clear Uncertain Flag',
    '수령인 / 회사명': 'Recipient / Company',
    '수취인 불명 / 데이터 불문명 화물': 'Unknown / Uncertain Cargo',
    '상세 안내': 'Details',
    '확인 요청 대기': 'Verification Pending',
    '수취인 불명 화물 보관·처분 상세 안내': 'Unknown Cargo Storage & Disposal',
    '본인 화물 확인 및 정정 요청': 'Verify and Correct My Cargo',
    '수취인 불명 화물 정보 입력': 'Enter Unknown Cargo Recipient',
    '확인 참고 내용 (선택)': 'Verification Notes (Optional)',
    '수취인 정보 적용': 'Apply Recipient Information',
    '본인 화물 확인 요청': 'Request Cargo Verification',
    '현재 확인이 필요한 수취인 불명 화물이 없습니다.': 'There is no unknown cargo requiring verification.',
    '화물을 눌러 정보 입력/수정': 'Tap cargo to enter or edit information',
    '화물을 눌러 본인 확인 요청': 'Tap cargo to request verification',
    '청구중량': 'Chargeable Weight',
    '단가': 'Rate',
    '박스': 'Box',
    '개': ' item(s)',
    '건': ' record(s)',
    '지방배송': 'Provincial Delivery',
    '지방배송(선결제)': 'Provincial Delivery (Prepaid)',
    '시내배송': 'City Delivery',
    '시내배송(선결제)': 'City Delivery (Prepaid)',
    '중량 / 크기 편집': 'Edit Weight / Size',
    '명세서를 열 수 있는 영수번호가 없습니다.':
        'There is no receipt number available for a statement.',
    '명세서 보기': 'View Statement',
    '현재': 'Current',
    '특별할인': 'Special Discount',
    '예: 지인 할인, 서비스 할인':
        'e.g. customer discount, service discount',
    '할인율은 0~100 사이로 입력해 주세요.':
        'Enter a discount rate between 0 and 100.',
    '추가 할인': 'Additional Discount',
    '예: 통관비용, 보관료': 'e.g. customs fee, storage fee',
    '체크 시 해당 고객의 할인율을 이 기타 비용에도 적용합니다. 기본은 미체크입니다.':
        'When selected, the customer discount also applies to this cost. The default is off.',
    '비용 이름과 금액을 확인해 주세요.':
        'Check the cost name and amount.',
    '필요한 경우 비고를 입력해 주세요.': 'Enter notes if needed.',
    '물품 내용, 발송인 등 관리자 확인에 도움이 되는 내용을 입력해 주세요.':
        'Enter the item details, sender, or other information that can help staff verify it.',
    '관리자는 입력한 수취인 정보를 바로 반영하고 영수번호/구획을 다시 계산합니다.':
        'The recipient details are applied immediately and the receipt number and zone are recalculated.',
    '요청 승인 후 수취인 정보가 반영되며 영수번호는 해당 항차 기준으로 처리됩니다.':
        'The recipient details are applied after approval and the receipt number follows the selected voyage.',
    '관리자는 확인이 필요한 화물을 눌러 수취인 이름과 연락처를 바로 입력·수정할 수 있습니다.':
        'Staff can tap cargo requiring verification to enter or edit the recipient name and phone.',
    '본인 화물이 확인되면 해당 화물을 눌러 이름과 연락처를 입력하고 확인 요청할 수 있습니다.':
        'When you find your cargo, tap it to enter your name and phone and request verification.',
    '이름/연락처': 'Name / Phone',
    '수취인 불명': 'Unknown Recipient',
    '검색한 화물이 없습니다. 화물을 추가하시겠습니까?':
        'No cargo was found. Would you like to add cargo?',
    '화물 검색 실패': 'Cargo search failed',
    '화물 조회 실패': 'Could not load cargo',
    '운임 계산 실패': 'Freight calculation failed',
    '그룹 운임 계산 실패': 'Group freight calculation failed',
    '협력/파트너 계정은 명세서를 조회할 수 없습니다.':
        'Partner accounts cannot view statements.',
    '협력/파트너 계정은 명세서를 출력할 수 없습니다.':
        'Partner accounts cannot export statements.',
    '명세서를 확인할 화물을 선택해 주세요.':
        'Select cargo to view its statement.',
    '선택한 화물에 영수번호가 없습니다.':
        'The selected cargo has no receipt number.',
    '명세서는 같은 영수번호(고객)의 화물끼리 선택해 주세요.':
        'Select cargo with the same receipt number (customer).',
    '명세서의 운송경로/년도/항차 정보를 확인할 수 없습니다.':
        'The statement route, year, or voyage could not be identified.',
    'PDF로 저장할 명세서의 화물을 먼저 체크해 주세요.':
        'Select cargo before creating a statement PDF.',
    '이 항차에서 체크된 화물이 없습니다.':
        'No cargo is selected for this voyage.',
    '수정할 내용을 입력해 주세요.': 'Enter the information to change.',
    '선택한 화물 정보를 저장했습니다.':
        'The selected cargo information was saved.',
    '관리자에게 화물 정보 수정 요청을 보냈습니다.':
        'The cargo change request was sent to an administrator.',
    '화물 정보 처리 실패': 'Cargo update failed',
    '화물 삭제 대기 목록 불러오기 실패':
        'Could not load cargo pending deletion',
    '{box} 화물을 삭제 대기로 이동하시겠습니까?\n\n삭제 대기 중에는 아래 "화물 삭제 대기"에서 취소하거나 바로 삭제할 수 있습니다.':
        'Move cargo {box} to pending deletion?\n\nYou can cancel or delete it immediately from Pending Cargo Deletion below.',
    '{box} 화물을 삭제 대기로 이동했습니다.':
        'Cargo {box} was moved to pending deletion.',
    '화물 삭제 대기 처리 실패': 'Could not move cargo to pending deletion',
    '화물 삭제를 취소했습니다.': 'Cargo deletion was cancelled.',
    '삭제 취소 실패': 'Could not cancel deletion',
    '{box} 화물을 바로 삭제하시겠습니까?\n\n바로 삭제 후에는 앱에서 복구할 수 없습니다.':
        'Delete cargo {box} now?\n\nIt cannot be restored in the app after deletion.',
    '{box} 화물을 바로 삭제했습니다.': 'Cargo {box} was deleted.',
    '화물 바로 삭제 실패': 'Could not delete cargo',
    '확인할 고객을 선택해 주세요.': 'Select a customer to continue.',
    '선택한 고객/영수번호의 명세서 발급 형식을 선택해 주세요.':
        'Choose a statement format for the selected customer or receipt.',
    '복수 고객/영수번호 명세서는 PDF로만 발급됩니다.':
        'Statements for multiple customers or receipts are available only as PDF.',
    '박스를 추가하려면 운송 경로, 년도, 항차를 각각 선택해 주세요.':
        'Select a route, year, and voyage before adding a box.',
    '년도를 확인해 주세요.': 'Check the year.',
    '선택한 운송 경로의 박스번호 형식을 확인할 수 없습니다.':
        'The box-number format for the selected route could not be identified.',
    '다음 박스번호 확인 실패': 'Could not determine the next box number',
    '{box} 박스 행을 추가했습니다.': 'Box row {box} was added.',
    '박스 행 추가 실패': 'Could not add the box row',
    '편집할 화물을 먼저 체크해 주세요.': 'Select cargo to edit.',
    '여러 화물 편집 시 입력한 항목만 선택 화물 전체에 적용됩니다.':
        'When editing multiple cargo items, only entered fields are applied to all selected items.',
    '화물 편집 실패': 'Could not edit cargo',
    '삭제할 화물을 먼저 체크해 주세요.': 'Select cargo to delete.',
    '{count}건을 삭제 대기로 이동하시겠습니까?':
        'Move {count} item(s) to pending deletion?',
    '{count}건을 삭제 대기로 이동했습니다.':
        '{count} item(s) were moved to pending deletion.',
    '그룹 삭제 처리 실패': 'Could not process group deletion',
    '불확실 화물로 표시했습니다. 변경 승인 관리에서 확인할 수 있습니다.':
        'Marked as uncertain cargo. Review it in Change Approvals.',
    '불확실 표시를 해제했습니다.': 'The uncertain flag was cleared.',
    '불확실 표시 처리 실패': 'Could not update the uncertain flag',
    '화물 데이터를 잠금했습니다.': 'Cargo data was locked.',
    '화물 데이터 잠금을 해제했습니다.': 'Cargo data was unlocked.',
    '화물 잠금 처리 실패': 'Could not update the cargo lock',
    '고객 정보 편집': 'Edit Customer Information',
    '이 영수번호에 묶인 {count}개 화물에 동일하게 적용됩니다.':
        'The change applies to all {count} cargo item(s) under this receipt.',
    '{count}개 화물의 고객 정보를 수정했습니다.':
        'Customer information was updated for {count} cargo item(s).',
    '고객 단위 편집 실패': 'Could not update the customer group',
    '중량 / 크기 정보를 저장했습니다.': 'Weight and dimensions were saved.',
    '중량 / 크기 편집 실패': 'Could not update weight and dimensions',
    '그룹 명세서/운임 로딩 실패':
        'Could not load the group statement or freight',
    '할인을 연결할 영수번호 정보를 확인할 수 없습니다.':
        'The receipt information required for the discount is unavailable.',
    '{receipt} 할인 적용을 삭제했습니다.':
        'The discount for {receipt} was deleted.',
    '{receipt} 할인 적용 완료': 'The discount for {receipt} was applied.',
    '기타 비용을 연결할 영수번호 정보를 확인할 수 없습니다.':
        'The receipt information required for the extra cost is unavailable.',
    '수취인 정보를 반영했습니다.': 'Recipient information was applied.',
    '관리자에게 본인 화물 확인 및 정정 요청을 보냈습니다.':
        'Your cargo verification and correction request was sent to an administrator.',
    '수취인 정보 적용 실패': 'Could not apply recipient information',
    '본인 화물 확인 요청 실패': 'Could not send the cargo verification request',
  };

  static const Map<String, String> _lao = {
    '전체': 'ທັງໝົດ',
    '확인': 'ຕົກລົງ',
    '취소': 'ຍົກເລີກ',
    '닫기': 'ປິດ',
    '추가': 'ເພີ່ມ',
    '삭제': 'ລົບ',
    '편집': 'ແກ້ໄຂ',
    '저장': 'ບັນທຶກ',
    '적용': 'ນຳໃຊ້',
    '수정 저장': 'ບັນທຶກການແກ້ໄຂ',
    '검색 중...': 'ກຳລັງຄົ້ນຫາ...',
    '운송 경로': 'ເສັ້ນທາງຂົນສົ່ງ',
    '년도': 'ປີ',
    '항차': 'ຖ້ຽວ',
    '박스번호': 'ເລກກ່ອງ',
    '송장번호': 'ເລກໃບຂົນສົ່ງ',
    '화물번호': 'ເລກສິນຄ້າ',
    '화물개수': 'ຈຳນວນສິນຄ້າ',
    '이름': 'ຊື່',
    '이름/라오스 수령인': 'ຊື່ / ຜູ້ຮັບໃນລາວ',
    '이름/수령인': 'ຊື່ / ຜູ້ຮັບ',
    '수취인 이름 / 회사명': 'ຜູ້ຮັບ / ບໍລິສັດ',
    '본인 이름': 'ຊື່ຂອງທ່ານ',
    '연락처': 'ເບີໂທ',
    '본인 연락처': 'ເບີໂທຂອງທ່ານ',
    '기타 내용': 'ໝາຍເຫດ',
    '비고': 'ໝາຍເຫດ',
    '무게(kg)': 'ນ້ຳໜັກ (kg)',
    '가로(cm)': 'ຍາວ (cm)',
    '세로(cm)': 'ກວ້າງ (cm)',
    '높이(cm)': 'ສູງ (cm)',
    '무게 / 크기': 'ນ້ຳໜັກ / ຂະໜາດ',
    '입고날짜': 'ວັນທີ່ຮັບເຂົ້າ',
    '영수번호': 'ເລກໃບຮັບ',
    '영수번호/구획': 'ໃບຮັບ / ໂຊນ',
    '영수번호 / 구획': 'ໃບຮັບ / ໂຊນ',
    '총 개수': 'ຈຳນວນລວມ',
    '운임 확인': 'ກວດຄ່າຂົນສົ່ງ',
    '화물 검색': 'ຄົ້ນຫາສິນຄ້າ',
    '화물 관리': 'ຈັດການສິນຄ້າ',
    '화물 추가 입력': 'ເພີ່ມສິນຄ້າ',
    '박스 추가 (행 추가)': 'ເພີ່ມແຖວກ່ອງ',
    '화물 편집': 'ແກ້ໄຂສິນຄ້າ',
    '검색 결과 명세서': 'ໃບລາຍການຜົນຄົ້ນຫາ',
    '선택 화물 삭제 대기': 'ຍ້າຍສິນຄ້າທີ່ເລືອກໄປລໍຖ້າລົບ',
    '삭제 대기': 'ລໍຖ້າລົບ',
    '삭제 취소': 'ຍົກເລີກການລົບ',
    '바로 삭제': 'ລົບທັນທີ',
    '화물 삭제': 'ລົບສິນຄ້າ',
    '화물 바로 삭제': 'ລົບສິນຄ້າທັນທີ',
    '일괄 저장': 'ບັນທຶກທັງໝົດ',
    '이름 / 회사명': 'ຊື່ / ບໍລິສັດ',
    '중량 (kg)': 'ນ້ຳໜັກ (kg)',
    '가로 (cm)': 'ຍາວ (cm)',
    '세로 (cm)': 'ກວ້າງ (cm)',
    '높이 (cm)': 'ສູງ (cm)',
    '년도 / 항차': 'ປີ / ຖ້ຽວ',
    '화물 정보': 'ຂໍ້ມູນສິນຄ້າ',
    '선택한 화물 정보 수정': 'ແກ້ໄຂສິນຄ້າທີ່ເລືອກ',
    '화물 정보 저장': 'ບັນທຶກສິນຄ້າ',
    '화물 정보 수정 요청': 'ຂໍແກ້ໄຂຂໍ້ມູນສິນຄ້າ',
    '체크 명세서 PDF': 'PDF ໃບລາຍການທີ່ເລືອກ',
    '화물 삭제 대기': 'ລໍຖ້າລົບສິນຄ້າ',
    '삭제 대기 중인 화물이 없습니다.': 'ບໍ່ມີສິນຄ້າທີ່ລໍຖ້າລົບ.',
    '통합 관리': 'ຈັດການລວມ',
    '선적 일정 관리': 'ຈັດການຕາຕະລາງຂົນສົ່ງ',
    '공지사항 관리': 'ຈັດການແຈ້ງການ',
    '화물 종합 관리': 'ຈັດການສິນຄ້າ',
    '엑셀 화물 업로드': 'ອັບໂຫຼດ Excel ສິນຄ້າ',
    '회원 종합 관리': 'ຈັດການສະມາຊິກ',
    '변경 승인 관리': 'ອະນຸມັດການປ່ຽນແປງ',
    '견적 요청 관리': 'ຈັດການຄຳຂໍລາຄາ',
    '기준 환율 입력': 'ອັດຕາແລກປ່ຽນ',
    '계정으로 돌아가기': 'ກັບໄປບັນຊີ',
    '회원': 'ສະມາຊິກ',
    '명세서': 'ໃບລາຍການ',
    '명세서 발급': 'ສ້າງໃບລາຍການ',
    '이미지': 'ຮູບພາບ',
    '그룹 전체 운임': 'ຄ່າຂົນສົ່ງລວມ',
    '영수번호별 명세서': 'ໃບລາຍການຕາມເລກໃບຮັບ',
    '추가 할인명': 'ຊື່ສ່ວນຫຼຸດ',
    '할인율': 'ອັດຕາສ່ວນຫຼຸດ',
    '할인 적용': 'ນຳໃຊ້ສ່ວນຫຼຸດ',
    '할인 편집 / 삭제': 'ແກ້ໄຂ / ລົບສ່ວນຫຼຸດ',
    '비용 이름': 'ຊື່ຄ່າໃຊ້ຈ່າຍ',
    '금액 (USD)': 'ຈຳນວນເງິນ (USD)',
    '기타 비용': 'ຄ່າໃຊ້ຈ່າຍອື່ນ',
    '선택 화물 편집': 'ແກ້ໄຂສິນຄ້າທີ່ເລືອກ',
    '선택 화물 삭제': 'ລົບສິນຄ້າທີ່ເລືອກ',
    '고객 단위 편집': 'ແກ້ໄຂກຸ່ມລູກຄ້າ',
    '잠금': 'ລັອກ',
    '잠금 해제': 'ປົດລັອກ',
    '불확실 화물 표시': 'ໝາຍວ່າບໍ່ແນ່ນອນ',
    '불확실 표시 해제': 'ຍົກເລີກໝາຍບໍ່ແນ່ນອນ',
    '수령인 / 회사명': 'ຜູ້ຮັບ / ບໍລິສັດ',
    '수취인 불명 / 데이터 불문명 화물': 'ສິນຄ້າບໍ່ຮູ້ຜູ້ຮັບ / ບໍ່ຊັດເຈນ',
    '상세 안내': 'ລາຍລະອຽດ',
    '확인 요청 대기': 'ລໍຖ້າກວດສອບ',
    '수취인 불명 화물 보관·처분 상세 안내': 'ການເກັບຮັກສາແລະຈັດການສິນຄ້າບໍ່ຮູ້ຜູ້ຮັບ',
    '본인 화물 확인 및 정정 요청': 'ກວດສອບແລະຂໍແກ້ໄຂສິນຄ້າຂອງຂ້ອຍ',
    '수취인 불명 화물 정보 입력': 'ປ້ອນຂໍ້ມູນຜູ້ຮັບສິນຄ້າ',
    '확인 참고 내용 (선택)': 'ໝາຍເຫດການກວດສອບ (ບໍ່ບັງຄັບ)',
    '수취인 정보 적용': 'ນຳໃຊ້ຂໍ້ມູນຜູ້ຮັບ',
    '본인 화물 확인 요청': 'ຂໍກວດສອບສິນຄ້າ',
    '현재 확인이 필요한 수취인 불명 화물이 없습니다.': 'ບໍ່ມີສິນຄ້າບໍ່ຮູ້ຜູ້ຮັບທີ່ຕ້ອງກວດສອບ.',
    '화물을 눌러 정보 입력/수정': 'ແຕະສິນຄ້າເພື່ອປ້ອນຫຼືແກ້ໄຂ',
    '화물을 눌러 본인 확인 요청': 'ແຕະສິນຄ້າເພື່ອຂໍກວດສອບ',
    '청구중량': 'ນ້ຳໜັກຄິດໄລ່',
    '단가': 'ອັດຕາ',
    '박스': 'ກ່ອງ',
    '개': ' ຊິ້ນ',
    '건': ' ລາຍການ',
    '지방배송': 'ສົ່ງຕ່າງແຂວງ',
    '지방배송(선결제)': 'ສົ່ງຕ່າງແຂວງ (ຈ່າຍລ່ວງໜ້າ)',
    '시내배송': 'ສົ່ງໃນເມືອງ',
    '시내배송(선결제)': 'ສົ່ງໃນເມືອງ (ຈ່າຍລ່ວງໜ້າ)',
    '중량 / 크기 편집': 'ແກ້ໄຂນ້ຳໜັກ / ຂະໜາດ',
    '명세서를 열 수 있는 영수번호가 없습니다.':
        'ບໍ່ມີເລກໃບຮັບທີ່ສາມາດເປີດໃບລາຍການໄດ້.',
    '명세서 보기': 'ເບິ່ງໃບລາຍການ',
    '현재': 'ປັດຈຸບັນ',
    '특별할인': 'ສ່ວນຫຼຸດພິເສດ',
    '예: 지인 할인, 서비스 할인':
        'ຕົວຢ່າງ: ສ່ວນຫຼຸດລູກຄ້າ, ສ່ວນຫຼຸດບໍລິການ',
    '할인율은 0~100 사이로 입력해 주세요.':
        'ກະລຸນາປ້ອນອັດຕາສ່ວນຫຼຸດລະຫວ່າງ 0 ຫາ 100.',
    '추가 할인': 'ສ່ວນຫຼຸດເພີ່ມເຕີມ',
    '예: 통관비용, 보관료': 'ຕົວຢ່າງ: ຄ່າພາສີ, ຄ່າເກັບຮັກສາ',
    '체크 시 해당 고객의 할인율을 이 기타 비용에도 적용합니다. 기본은 미체크입니다.':
        'ເມື່ອເລືອກ ສ່ວນຫຼຸດຂອງລູກຄ້າຈະນຳໃຊ້ກັບຄ່າໃຊ້ຈ່າຍນີ້. ຄ່າເລີ່ມຕົ້ນແມ່ນບໍ່ເລືອກ.',
    '비용 이름과 금액을 확인해 주세요.':
        'ກະລຸນາກວດຊື່ຄ່າໃຊ້ຈ່າຍແລະຈຳນວນເງິນ.',
    '필요한 경우 비고를 입력해 주세요.': 'ປ້ອນໝາຍເຫດຖ້າຈຳເປັນ.',
    '물품 내용, 발송인 등 관리자 확인에 도움이 되는 내용을 입력해 주세요.':
        'ປ້ອນລາຍລະອຽດສິນຄ້າ, ຜູ້ສົ່ງ ຫຼື ຂໍ້ມູນອື່ນທີ່ຊ່ວຍໃຫ້ພະນັກງານກວດສອບ.',
    '관리자는 입력한 수취인 정보를 바로 반영하고 영수번호/구획을 다시 계산합니다.':
        'ຂໍ້ມູນຜູ້ຮັບຈະຖືກນຳໃຊ້ທັນທີ ແລະ ຄຳນວນເລກໃບຮັບກັບໂຊນໃໝ່.',
    '요청 승인 후 수취인 정보가 반영되며 영수번호는 해당 항차 기준으로 처리됩니다.':
        'ຂໍ້ມູນຜູ້ຮັບຈະຖືກນຳໃຊ້ຫຼັງຈາກອະນຸມັດ ແລະ ເລກໃບຮັບຈະຄິດຕາມຖ້ຽວນັ້ນ.',
    '관리자는 확인이 필요한 화물을 눌러 수취인 이름과 연락처를 바로 입력·수정할 수 있습니다.':
        'ພະນັກງານສາມາດແຕະສິນຄ້າທີ່ຕ້ອງກວດສອບເພື່ອປ້ອນ ຫຼື ແກ້ໄຂຊື່ແລະເບີໂທຜູ້ຮັບ.',
    '본인 화물이 확인되면 해당 화물을 눌러 이름과 연락처를 입력하고 확인 요청할 수 있습니다.':
        'ເມື່ອພົບສິນຄ້າຂອງທ່ານ ໃຫ້ແຕະເພື່ອປ້ອນຊື່ແລະເບີໂທ ແລ້ວສົ່ງຄຳຂໍກວດສອບ.',
    '이름/연락처': 'ຊື່ / ເບີໂທ',
    '수취인 불명': 'ບໍ່ຮູ້ຜູ້ຮັບ',
    '검색한 화물이 없습니다. 화물을 추가하시겠습니까?':
        'ບໍ່ພົບສິນຄ້າ. ຕ້ອງການເພີ່ມສິນຄ້າບໍ?',
    '화물 검색 실패': 'ຄົ້ນຫາສິນຄ້າບໍ່ສຳເລັດ',
    '화물 조회 실패': 'ໂຫຼດຂໍ້ມູນສິນຄ້າບໍ່ສຳເລັດ',
    '운임 계산 실패': 'ຄຳນວນຄ່າຂົນສົ່ງບໍ່ສຳເລັດ',
    '그룹 운임 계산 실패': 'ຄຳນວນຄ່າຂົນສົ່ງຂອງກຸ່ມບໍ່ສຳເລັດ',
    '협력/파트너 계정은 명세서를 조회할 수 없습니다.':
        'ບັນຊີຄູ່ຮ່ວມງານບໍ່ສາມາດເບິ່ງໃບລາຍການໄດ້.',
    '협력/파트너 계정은 명세서를 출력할 수 없습니다.':
        'ບັນຊີຄູ່ຮ່ວມງານບໍ່ສາມາດສົ່ງອອກໃບລາຍການໄດ້.',
    '명세서를 확인할 화물을 선택해 주세요.':
        'ກະລຸນາເລືອກສິນຄ້າເພື່ອເບິ່ງໃບລາຍການ.',
    '선택한 화물에 영수번호가 없습니다.':
        'ສິນຄ້າທີ່ເລືອກບໍ່ມີເລກໃບຮັບ.',
    '명세서는 같은 영수번호(고객)의 화물끼리 선택해 주세요.':
        'ກະລຸນາເລືອກສິນຄ້າທີ່ມີເລກໃບຮັບດຽວກັນ.',
    '명세서의 운송경로/년도/항차 정보를 확인할 수 없습니다.':
        'ບໍ່ສາມາດກວດສອບເສັ້ນທາງ, ປີ ຫຼື ຖ້ຽວຂອງໃບລາຍການໄດ້.',
    'PDF로 저장할 명세서의 화물을 먼저 체크해 주세요.':
        'ກະລຸນາເລືອກສິນຄ້າກ່ອນສ້າງ PDF.',
    '이 항차에서 체크된 화물이 없습니다.':
        'ບໍ່ມີສິນຄ້າທີ່ເລືອກໃນຖ້ຽວນີ້.',
    '수정할 내용을 입력해 주세요.': 'ກະລຸນາປ້ອນຂໍ້ມູນທີ່ຈະແກ້ໄຂ.',
    '선택한 화물 정보를 저장했습니다.':
        'ບັນທຶກຂໍ້ມູນສິນຄ້າທີ່ເລືອກແລ້ວ.',
    '관리자에게 화물 정보 수정 요청을 보냈습니다.':
        'ສົ່ງຄຳຂໍແກ້ໄຂຂໍ້ມູນສິນຄ້າໃຫ້ຜູ້ບໍລິຫານແລ້ວ.',
    '화물 정보 처리 실패': 'ປັບປຸງຂໍ້ມູນສິນຄ້າບໍ່ສຳເລັດ',
    '화물 삭제 대기 목록 불러오기 실패': 'ໂຫຼດລາຍການລໍຖ້າລົບບໍ່ສຳເລັດ',
    '{box} 화물을 삭제 대기로 이동하시겠습니까?\n\n삭제 대기 중에는 아래 "화물 삭제 대기"에서 취소하거나 바로 삭제할 수 있습니다.':
        'ຍ້າຍສິນຄ້າ {box} ໄປລໍຖ້າລົບບໍ?\n\nສາມາດຍົກເລີກ ຫຼື ລົບທັນທີໄດ້ໃນລາຍການລໍຖ້າລົບ.',
    '{box} 화물을 삭제 대기로 이동했습니다.': 'ຍ້າຍສິນຄ້າ {box} ໄປລໍຖ້າລົບແລ້ວ.',
    '화물 삭제 대기 처리 실패': 'ຍ້າຍສິນຄ້າໄປລໍຖ້າລົບບໍ່ສຳເລັດ',
    '화물 삭제를 취소했습니다.': 'ຍົກເລີກການລົບສິນຄ້າແລ້ວ.',
    '삭제 취소 실패': 'ຍົກເລີກການລົບບໍ່ສຳເລັດ',
    '{box} 화물을 바로 삭제하시겠습니까?\n\n바로 삭제 후에는 앱에서 복구할 수 없습니다.':
        'ລົບສິນຄ້າ {box} ທັນທີບໍ?\n\nຫຼັງຈາກລົບແລ້ວບໍ່ສາມາດກູ້ຄືນໃນແອັບໄດ້.',
    '{box} 화물을 바로 삭제했습니다.': 'ລົບສິນຄ້າ {box} ແລ້ວ.',
    '화물 바로 삭제 실패': 'ລົບສິນຄ້າບໍ່ສຳເລັດ',
    '확인할 고객을 선택해 주세요.': 'ກະລຸນາເລືອກລູກຄ້າ.',
    '선택한 고객/영수번호의 명세서 발급 형식을 선택해 주세요.':
        'ກະລຸນາເລືອກຮູບແບບໃບລາຍການຂອງລູກຄ້າ ຫຼື ເລກໃບຮັບທີ່ເລືອກ.',
    '복수 고객/영수번호 명세서는 PDF로만 발급됩니다.':
        'ໃບລາຍການຫຼາຍລູກຄ້າ ຫຼື ຫຼາຍເລກໃບຮັບສ້າງໄດ້ເປັນ PDF ເທົ່ານັ້ນ.',
    '박스를 추가하려면 운송 경로, 년도, 항차를 각각 선택해 주세요.':
        'ກະລຸນາເລືອກເສັ້ນທາງ, ປີ ແລະ ຖ້ຽວກ່ອນເພີ່ມກ່ອງ.',
    '년도를 확인해 주세요.': 'ກະລຸນາກວດສອບປີ.',
    '선택한 운송 경로의 박스번호 형식을 확인할 수 없습니다.':
        'ບໍ່ສາມາດກວດສອບຮູບແບບເລກກ່ອງຂອງເສັ້ນທາງນີ້ໄດ້.',
    '다음 박스번호 확인 실패': 'ກວດຫາເລກກ່ອງຖັດໄປບໍ່ສຳເລັດ',
    '{box} 박스 행을 추가했습니다.': 'ເພີ່ມແຖວກ່ອງ {box} ແລ້ວ.',
    '박스 행 추가 실패': 'ເພີ່ມແຖວກ່ອງບໍ່ສຳເລັດ',
    '편집할 화물을 먼저 체크해 주세요.': 'ກະລຸນາເລືອກສິນຄ້າທີ່ຈະແກ້ໄຂ.',
    '여러 화물 편집 시 입력한 항목만 선택 화물 전체에 적용됩니다.':
        'ເມື່ອແກ້ໄຂຫຼາຍລາຍການ ຈະນຳໃຊ້ສະເພາະຂໍ້ມູນທີ່ປ້ອນໃຫ້ທຸກລາຍການທີ່ເລືອກ.',
    '화물 편집 실패': 'ແກ້ໄຂສິນຄ້າບໍ່ສຳເລັດ',
    '삭제할 화물을 먼저 체크해 주세요.': 'ກະລຸນາເລືອກສິນຄ້າທີ່ຈະລົບ.',
    '{count}건을 삭제 대기로 이동하시겠습니까?': 'ຍ້າຍ {count} ລາຍການໄປລໍຖ້າລົບບໍ?',
    '{count}건을 삭제 대기로 이동했습니다.': 'ຍ້າຍ {count} ລາຍການໄປລໍຖ້າລົບແລ້ວ.',
    '그룹 삭제 처리 실패': 'ຈັດການການລົບກຸ່ມບໍ່ສຳເລັດ',
    '불확실 화물로 표시했습니다. 변경 승인 관리에서 확인할 수 있습니다.':
        'ໝາຍເປັນສິນຄ້າບໍ່ແນ່ນອນແລ້ວ. ກວດໄດ້ໃນການອະນຸມັດການປ່ຽນແປງ.',
    '불확실 표시를 해제했습니다.': 'ຍົກເລີກໝາຍບໍ່ແນ່ນອນແລ້ວ.',
    '불확실 표시 처리 실패': 'ປັບປຸງໝາຍບໍ່ແນ່ນອນບໍ່ສຳເລັດ',
    '화물 데이터를 잠금했습니다.': 'ລັອກຂໍ້ມູນສິນຄ້າແລ້ວ.',
    '화물 데이터 잠금을 해제했습니다.': 'ປົດລັອກຂໍ້ມູນສິນຄ້າແລ້ວ.',
    '화물 잠금 처리 실패': 'ປັບປຸງການລັອກສິນຄ້າບໍ່ສຳເລັດ',
    '고객 정보 편집': 'ແກ້ໄຂຂໍ້ມູນລູກຄ້າ',
    '이 영수번호에 묶인 {count}개 화물에 동일하게 적용됩니다.':
        'ການປ່ຽນແປງຈະນຳໃຊ້ກັບສິນຄ້າ {count} ລາຍການໃນເລກໃບຮັບນີ້.',
    '{count}개 화물의 고객 정보를 수정했습니다.':
        'ອັບເດດຂໍ້ມູນລູກຄ້າສຳລັບສິນຄ້າ {count} ລາຍການແລ້ວ.',
    '고객 단위 편집 실패': 'ອັບເດດກຸ່ມລູກຄ້າບໍ່ສຳເລັດ',
    '중량 / 크기 정보를 저장했습니다.': 'ບັນທຶກນ້ຳໜັກ ແລະ ຂະໜາດແລ້ວ.',
    '중량 / 크기 편집 실패': 'ແກ້ໄຂນ້ຳໜັກ ແລະ ຂະໜາດບໍ່ສຳເລັດ',
    '그룹 명세서/운임 로딩 실패': 'ໂຫຼດໃບລາຍການ ຫຼື ຄ່າຂົນສົ່ງຂອງກຸ່ມບໍ່ສຳເລັດ',
    '할인을 연결할 영수번호 정보를 확인할 수 없습니다.':
        'ບໍ່ມີຂໍ້ມູນເລກໃບຮັບສຳລັບສ່ວນຫຼຸດ.',
    '{receipt} 할인 적용을 삭제했습니다.': 'ລົບສ່ວນຫຼຸດຂອງ {receipt} ແລ້ວ.',
    '{receipt} 할인 적용 완료': 'ນຳໃຊ້ສ່ວນຫຼຸດໃຫ້ {receipt} ແລ້ວ.',
    '기타 비용을 연결할 영수번호 정보를 확인할 수 없습니다.':
        'ບໍ່ມີຂໍ້ມູນເລກໃບຮັບສຳລັບຄ່າໃຊ້ຈ່າຍອື່ນ.',
    '수취인 정보를 반영했습니다.': 'ນຳໃຊ້ຂໍ້ມູນຜູ້ຮັບແລ້ວ.',
    '관리자에게 본인 화물 확인 및 정정 요청을 보냈습니다.':
        'ສົ່ງຄຳຂໍກວດສອບ ແລະ ແກ້ໄຂສິນຄ້າໃຫ້ຜູ້ບໍລິຫານແລ້ວ.',
    '수취인 정보 적용 실패': 'ນຳໃຊ້ຂໍ້ມູນຜູ້ຮັບບໍ່ສຳເລັດ',
    '본인 화물 확인 요청 실패': 'ສົ່ງຄຳຂໍກວດສອບສິນຄ້າບໍ່ສຳເລັດ',
  };
}
