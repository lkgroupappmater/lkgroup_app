import 'app_language.dart';

/// Fixed UI text shared by customer-facing screens.
///
/// Database values and operational identifiers stay unchanged. Only labels,
/// prompts and status text shown on screen are localized here.
class UiLocalizations {
  UiLocalizations._();

  static String get(AppLanguage language, String korean) {
    if (language == AppLanguage.korean) return korean;
    return (language == AppLanguage.lao ? _lao : _english)[korean] ?? korean;
  }

  static String format(
    AppLanguage language,
    String korean,
    Map<String, Object?> values,
  ) {
    var value = get(language, korean);
    for (final entry in values.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return value;
  }

  static String error(
    AppLanguage language,
    String koreanPrefix,
    Object error,
  ) {
    final prefix = get(language, koreanPrefix);
    final detail = '$error'.trim();
    if (detail.isEmpty ||
        (language != AppLanguage.korean &&
            RegExp(r'[가-힣]').hasMatch(detail))) {
      return prefix;
    }
    return '$prefix: $detail';
  }

  static const Map<String, String> _english = {
    '예: member@example.com': 'e.g. member@example.com',
    '대문자 + 소문자 + 숫자 포함 8자 이상':
        'At least 8 characters with uppercase, lowercase and a number',
    '계정과 암호를 입력해 주세요.': 'Enter your email/account and password.',
    '접속 실패': 'Sign-in failed',
    '회원 정보를 변경했습니다.': 'Profile updated.',
    '회원 정보 변경 실패': 'Could not update profile',
    '암호를 변경했습니다. 이메일 본인 인증도 완료되었습니다.':
        'Password changed and email verification completed.',
    '회원 탈퇴가 처리되었습니다.': 'Your account deletion has been processed.',
    '프로필 사진을 변경했습니다.': 'Profile photo updated.',
    '프로필 사진 변경 실패': 'Could not update profile photo',
    '회원 가입': 'Sign Up',
    '이름': 'Name',
    '예: 홍길동': 'e.g. Hong Gildong',
    '이름을(를) 입력해 주세요.': 'Enter your name.',
    '이메일': 'Email',
    '이메일을 입력해 주세요.': 'Enter your email.',
    '예: member@example.com 형식으로 입력해 주세요.':
        'Enter an email such as member@example.com.',
    '암호': 'Password',
    '예: Lkgroup2026': 'e.g. Lkgroup2026',
    '대문자·소문자·숫자를 각각 1자 이상 포함, 8자 이상':
        'At least 8 characters including uppercase, lowercase and a number',
    '암호는 8자 이상 입력해 주세요.':
        'The password must be at least 8 characters.',
    '영문 소문자를 1자 이상 포함해 주세요.':
        'Include at least one lowercase letter.',
    '영문 대문자를 1자 이상 포함해 주세요.':
        'Include at least one uppercase letter.',
    '숫자를 1자 이상 포함해 주세요.': 'Include at least one number.',
    '암호확인': 'Confirm Password',
    '위 암호를 다시 입력': 'Enter the password again',
    '암호가 서로 일치하지 않습니다.': 'Passwords do not match.',
    '전화번호': 'Phone Number',
    '전화번호를 입력해 주세요.': 'Enter your phone number.',
    '예: 020-5889-2547 형식으로 입력해 주세요.':
        'Enter a phone number such as 020-5889-2547.',
    '02058892547로 입력해도 저장 시 자동으로 형식을 맞춥니다.':
        'Numbers such as 02058892547 are formatted automatically when saved.',
    '회사명(선택)': 'Company (Optional)',
    '협력/파트너사 및 관리자는 총괄 관리자 승인이 필요 합니다.':
        'Partner and administrator accounts require super administrator approval.',
    '이메일 인증 코드 보내기': 'Send Email Verification Code',
    '이메일 인증 코드 다시 보내기': 'Resend Email Verification Code',
    '인증 코드 다시 보내기': 'Resend Code',
    '이메일 인증 코드': 'Email Verification Code',
    '메일로 받은 인증 코드 입력': 'Enter the code received by email',
    '이메일 인증 코드를 입력해 주세요.':
        'Enter the email verification code.',
    '인증 확인 및 가입 완료': 'Verify and Complete Sign-up',
    '취소': 'Cancel',
    '저장': 'Save',
    '변경': 'Change',
    '탈퇴 확인': 'Confirm Deletion',
    '인증 코드 전송 실패': 'Could not send verification code',
    '인증 코드 재전송 실패': 'Could not resend verification code',
    '이메일 인증 실패': 'Email verification failed',
    '이메일 인증 및 회원가입이 완료되었습니다. 로그인해 주세요.':
        'Email verification and sign-up are complete. Please sign in.',
    '{role} 가입 신청이 완료되었습니다. 총괄 관리자 승인 후 로그인할 수 있습니다.':
        'Your {role} registration request is complete. You can sign in after super administrator approval.',
    '회원 정보 변경': 'Edit Profile',
    '주소(선택)': 'Address (Optional)',
    '암호 변경': 'Change Password',
    '기존 암호': 'Current Password',
    '현재 사용 중인 암호 입력': 'Enter your current password',
    '기존 암호을(를) 입력해 주세요.': 'Enter your current password.',
    '새 암호': 'New Password',
    '대문자·소문자·숫자 포함 8자 이상':
        'At least 8 characters with uppercase, lowercase and a number',
    '새 암호 확인': 'Confirm New Password',
    '새 암호가 서로 일치하지 않습니다.': 'New passwords do not match.',
    '인증 이메일: {email}': 'Verification email: {email}',
    '이메일 인증 코드를 먼저 받아 입력해 주세요.':
        'Request and enter the email verification code first.',
    '이메일 인증 코드 전송 실패': 'Could not send email verification code',
    '암호 변경 실패': 'Could not change password',
    '회원 탈퇴': 'Delete Account',
    '회원 탈퇴를 진행하시겠습니까?': 'Do you want to delete your account?',
    '탈퇴 시 3일 동안 탈퇴 아이디/Email로 재가입이 안되니 신중하게 확인 바랍니다.':
        'After deletion, the same ID/email cannot be registered again for 3 days.',
    '본인 암호': 'Current Password',
    '본인 암호을(를) 입력해 주세요.': 'Enter your current password.',
    '회원 탈퇴 실패': 'Could not delete account',
    'Supabase의 Confirm Email 설정이 꺼져 있습니다. 이메일 인증 코드 회원가입을 사용하려면 Confirm Email을 활성화해 주세요.':
        'Confirm Email is disabled in Supabase. Enable it to use email-code sign-up.',
    '알림 조회 실패': 'Could not load notifications',
    '{name}님 로그인되었습니다.': '{name} signed in.',
    '상태: {status}': 'Status: {status}',
    '예정': 'Scheduled',
    '운송 중': 'In Transit',
    '대표번호 링크는 추후 관리자 설정이 필요합니다.':
        'The main contact link must be configured by an administrator.',
    '참여 코드 9112': 'Join code: 9112',
    '링크를 열 수 없습니다.': 'Could not open the link.',
    'LK그룹 카카오톡 단톡방': 'LK Group KakaoTalk Group',
    '오픈상담톡(한국어, Eng, ລາວ)': 'Open Chat Support (Korean, English, Lao)',
    '카카오톡(대표번호, Eng, ລາວ)': 'KakaoTalk (Main Number, English, Lao)',
    'WhatsApp(한국어, Eng, ລາວ)': 'WhatsApp (Korean, English, Lao)',
    'WhatsApp(대표번호, Eng, ລາວ)': 'WhatsApp (Main Number, English, Lao)',
    'LK Group 블로그': 'LK Group Blog',
    'LK Group 사무실 위치': 'LK Group Office Location',
    '할인율 적용': 'Apply Discount',
    '할인율 (%)': 'Discount (%)',
    '예: 20': 'e.g. 20',
    '할인 해제': 'Remove Discount',
    '적용': 'Apply',
    '할인율은 0~100% 범위로 입력해 주세요.':
        'Enter a discount between 0% and 100%.',
    '기타 비용 추가': 'Add Extra Cost',
    '비용 이름': 'Cost Name',
    '예: 통관비용, 보관료, 기타 수수료':
        'e.g. customs, storage or other fee',
    '금액 (USD)': 'Amount (USD)',
    '비용 이름과 0보다 큰 USD 금액을 입력해 주세요.':
        'Enter a cost name and a USD amount greater than zero.',
    '추가': 'Add',
    '로그인 필요': 'Sign-in Required',
    '운임 확인 및 견적 요청은 회원 로그인 후 이용하실 수 있습니다.':
        'Sign in to check freight rates and request a quote.',
    '대량 혹은 특수 견적 요청은 실명 및 회신을 위해 로그인 후 이용해 주세요.':
        'Sign in to submit a bulk or special quote request so we can verify your name and reply.',
    '회원 로그인': 'Member Sign-in',
    '선택한 박스의 무게와 가로·세로·높이를 모두 입력해 주세요.':
        'Enter the weight, length, width and height for every selected box.',
    '운임을 확인할 박스를 하나 이상 선택해 주세요.':
        'Select at least one box to calculate freight.',
    '대량 혹은 특수 견적 요청을 이용해 주세요.':
        'Please use the bulk or special quote request.',
    '협력/파트너사는 견적서 보기 권한이 없습니다.':
        'Partner accounts cannot view quotations.',
    '견적서 권한 확인 실패': 'Could not verify quotation access',
    '견적 요청 조회 실패': 'Could not load quote requests',
    '대량 혹은 특수 견적 요청': 'Bulk or Special Quote Request',
    '견적 요청 수정': 'Edit Quote Request',
    '운송 경로': 'Route',
    '제목': 'Subject',
    '내용': 'Details',
    '기타 연락처': 'Other Contact',
    '제목과 내용을 입력해 주세요.': 'Enter a subject and details.',
    '견적 요청': 'Request Quote',
    '수정 저장': 'Save Changes',
    '견적 요청을 보냈습니다.': 'Quote request sent.',
    '견적 요청을 수정했습니다.': 'Quote request updated.',
    '견적 요청 처리 실패': 'Could not process quote request',
    '추가 회신': 'Additional Message',
    '추가 내용': 'Additional Details',
    '송부': 'Send',
    '추가 회신 실패': 'Could not send additional message',
    '견적 요청을 삭제하시겠습니까?': 'Delete this quote request?',
    '삭제 처리 실패': 'Could not request deletion',
    '삭제 취소 실패': 'Could not cancel deletion',
    '지금 목록에서 삭제하시겠습니까?': 'Delete it from the list now?',
    '바로 삭제 실패': 'Could not delete immediately',
    '확인': 'OK',
    '이 기타 비용에도 현재 할인율 적용':
        'Apply the current discount to this extra cost',
    '박스 {index} · 청구중량 {weight}kg · 단가 USD {rate}{moving}{packing}':
        'Box {index} · Chargeable {weight}kg · Rate USD {rate}{moving}{packing}',
    ' · 이삿짐 통관 +\${amount}': ' · Moving cargo clearance +\${amount}',
    ' · 박스 포장 +\${amount}': ' · Box packing +\${amount}',
    '기타 비용 · {name}{discount}': 'Extra cost · {name}{discount}',
    ' · 할인 적용': ' · Discount applied',
    '할인 전  USD {amount}': 'Before discount  USD {amount}',
    '할인 {percent}%  -{amount}': 'Discount {percent}%  -{amount}',
    '총 운임  USD {amount}': 'Total freight  USD {amount}',
    '운임은 USD 기준이며, 이외 화폐는 가견적 안내시의 환율 기준이므로, 최종 운임 책정시의 환율변동으로 인한 운임 차이가 발생할수 있으니, 참고용으로만 확인 부탁 드립니다.':
        'Freight is calculated in USD. Other currencies use the indicative exchange rate and may differ from the final charge due to exchange-rate changes.',
    '삭제 대기': 'Pending Deletion',
    '회신 완료': 'Replied',
    '관리자 확인': 'Administrator Review',
    '확인 전': 'Pending Review',
    '기타 연락처: {contact}': 'Other contact: {contact}',
    '삭제 취소': 'Cancel Deletion',
    '바로 삭제': 'Delete Now',
    '수정': 'Edit',
    '삭제': 'Delete',
    '관리자 회신': 'Administrator Reply',
    '일정 조회 실패': 'Could not load schedules',
    '선적 일정 삭제 확인': 'Confirm Schedule Deletion',
    '삭제하면 홈 화면에서는 즉시 보이지 않습니다.\n삭제된 자료는 30일 동안 임시 보관 후 완전히 삭제됩니다.':
        'After deletion, it disappears from Home immediately.\nDeleted data is retained for 30 days and then permanently removed.',
    '삭제 대기중으로 변경했습니다. 30일 후 완전히 삭제됩니다.':
        'Moved to pending deletion. It will be permanently deleted after 30 days.',
    '삭제 요청 실패': 'Could not request deletion',
    '삭제를 취소했습니다. 홈 화면에 다시 표시됩니다.':
        'Deletion canceled. It is visible on Home again.',
    '임시 보관 기간을 무시하고 DB에서 완전히 삭제할까요?':
        'Permanently delete it from the database now?',
    '선적 일정을 완전히 삭제했습니다.': 'Schedule permanently deleted.',
    '선적 일정 추가': 'Add Shipping Schedule',
    '선적 일정 편집': 'Edit Shipping Schedule',
    '년도': 'Year',
    '항차': 'Voyage',
    '예: 17항차': 'e.g. Voyage 17',
    '항차을(를) 입력해 주세요.': 'Enter the voyage.',
    '출발지': 'Origin',
    '예: 인천 국제 공항': 'e.g. Incheon International Airport',
    '출발지을(를) 입력해 주세요.': 'Enter the origin.',
    '도착지': 'Destination',
    '예: 라오스 왓따이 공항': 'e.g. Wattay International Airport, Laos',
    '도착지을(를) 입력해 주세요.': 'Enter the destination.',
    '접수 마감일': 'Booking Closing Date',
    '20260903으로 입력해도 작성 시 2026-09-03으로 자동 변환됩니다.':
        'An entry such as 20260903 is converted to 2026-09-03 automatically.',
    '도착 예정일': 'Estimated Arrival Date',
    '날짜를 입력해 주세요.': 'Enter a date.',
    '예: 2026-09-03 형식으로 입력해 주세요.':
        'Enter a date such as 2026-09-03.',
    '올바른 날짜를 입력해 주세요.': 'Enter a valid date.',
    '존재하는 날짜를 입력해 주세요.': 'Enter an existing calendar date.',
    'YYYY-MM-DD 또는 YYYYMMDD 형식': 'YYYY-MM-DD or YYYYMMDD format',
    '상세 내용 또는 추가 내용': 'Details or Additional Information',
    '예: 출항/도착 일정은 현지 사정에 따라 변경될 수 있습니다.':
        'e.g. Departure and arrival dates may change due to local conditions.',
    '작성': 'Create',
    '작성 실패': 'Could not create',
    '저장 실패': 'Could not save',
    '선적 일정 목록 관리': 'Manage Shipping Schedules',
    '일정 추가': 'Add Schedule',
    '등록된 선적 일정이 없습니다.': 'No shipping schedules are registered.',
    '삭제 대기중': 'Pending Deletion',
    '마감: {close} · 도착예정: {arrival}':
        'Closing: {close} · ETA: {arrival}',
    '공지 및 안내 조회 실패': 'Could not load notices',
    '공지 및 안내 삭제 확인': 'Confirm Notice Deletion',
    '공지 및 안내를 완전히 삭제했습니다.': 'Notice permanently deleted.',
    '공지 및 안내 추가': 'Add Notice',
    '공지 및 안내 편집': 'Edit Notice',
    '예: 9월 한국→라오스 해상 일정 안내':
        'e.g. September Korea → Laos Sea Schedule',
    '공지 내용을 입력해 주세요.': 'Enter the notice details.',
    '등록 날짜 표시': 'Show Published Date',
    '상단 고정': 'Pin to Top',
    '공지 및 안내 관리': 'Notice Management',
    '관리자 권한이 필요합니다.': 'Administrator access is required.',
    '공지 및 안내 목록 관리': 'Manage Notices',
    '등록된 공지 및 안내가 없습니다.': 'No notices are registered.',
    '직접 입력 (선택)': 'Manual entry (optional)',
    '비어 있는 영어·라오스어는 자동 번역됩니다. 직접 입력한 번역은 우선 저장됩니다.':
        'Empty English and Lao fields are translated automatically. Manually entered translations take priority.',
  };

  static const Map<String, String> _lao = {
    '예: member@example.com': 'ຕົວຢ່າງ: member@example.com',
    '대문자 + 소문자 + 숫자 포함 8자 이상':
        'ຢ່າງໜ້ອຍ 8 ຕົວ ມີຕົວພິມໃຫຍ່, ຕົວພິມນ້ອຍ ແລະ ຕົວເລກ',
    '계정과 암호를 입력해 주세요.': 'ກະລຸນາປ້ອນອີເມວ/ບັນຊີ ແລະ ລະຫັດຜ່ານ.',
    '접속 실패': 'ເຂົ້າລະບົບບໍ່ສຳເລັດ',
    '회원 정보를 변경했습니다.': 'ອັບເດດຂໍ້ມູນສະມາຊິກແລ້ວ.',
    '회원 정보 변경 실패': 'ອັບເດດຂໍ້ມູນສະມາຊິກບໍ່ສຳເລັດ',
    '암호를 변경했습니다. 이메일 본인 인증도 완료되었습니다.':
        'ປ່ຽນລະຫັດຜ່ານ ແລະ ຢືນຢັນອີເມວແລ້ວ.',
    '회원 탈퇴가 처리되었습니다.': 'ດຳເນີນການລຶບບັນຊີແລ້ວ.',
    '프로필 사진을 변경했습니다.': 'ປ່ຽນຮູບໂປຣໄຟລ໌ແລ້ວ.',
    '프로필 사진 변경 실패': 'ປ່ຽນຮູບໂປຣໄຟລ໌ບໍ່ສຳເລັດ',
    '회원 가입': 'ລົງທະບຽນ',
    '이름': 'ຊື່',
    '예: 홍길동': 'ຕົວຢ່າງ: Hong Gildong',
    '이름을(를) 입력해 주세요.': 'ກະລຸນາປ້ອນຊື່.',
    '이메일': 'ອີເມວ',
    '이메일을 입력해 주세요.': 'ກະລຸນາປ້ອນອີເມວ.',
    '예: member@example.com 형식으로 입력해 주세요.':
        'ກະລຸນາປ້ອນອີເມວເຊັ່ນ member@example.com.',
    '암호': 'ລະຫັດຜ່ານ',
    '예: Lkgroup2026': 'ຕົວຢ່າງ: Lkgroup2026',
    '대문자·소문자·숫자를 각각 1자 이상 포함, 8자 이상':
        'ຢ່າງໜ້ອຍ 8 ຕົວ ພ້ອມຕົວພິມໃຫຍ່, ຕົວພິມນ້ອຍ ແລະ ຕົວເລກ',
    '암호는 8자 이상 입력해 주세요.': 'ລະຫັດຜ່ານຕ້ອງມີຢ່າງໜ້ອຍ 8 ຕົວ.',
    '영문 소문자를 1자 이상 포함해 주세요.': 'ຕ້ອງມີຕົວພິມນ້ອຍຢ່າງໜ້ອຍ 1 ຕົວ.',
    '영문 대문자를 1자 이상 포함해 주세요.': 'ຕ້ອງມີຕົວພິມໃຫຍ່ຢ່າງໜ້ອຍ 1 ຕົວ.',
    '숫자를 1자 이상 포함해 주세요.': 'ຕ້ອງມີຕົວເລກຢ່າງໜ້ອຍ 1 ຕົວ.',
    '암호확인': 'ຢືນຢັນລະຫັດຜ່ານ',
    '위 암호를 다시 입력': 'ປ້ອນລະຫັດຜ່ານອີກຄັ້ງ',
    '암호가 서로 일치하지 않습니다.': 'ລະຫັດຜ່ານບໍ່ກົງກັນ.',
    '전화번호': 'ເບີໂທ',
    '전화번호를 입력해 주세요.': 'ກະລຸນາປ້ອນເບີໂທ.',
    '예: 020-5889-2547 형식으로 입력해 주세요.':
        'ກະລຸນາປ້ອນເບີໂທເຊັ່ນ 020-5889-2547.',
    '02058892547로 입력해도 저장 시 자동으로 형식을 맞춥니다.':
        'ເບີ 02058892547 ຈະຖືກຈັດຮູບແບບອັດຕະໂນມັດເມື່ອບັນທຶກ.',
    '회사명(선택)': 'ບໍລິສັດ (ບໍ່ບັງຄັບ)',
    '협력/파트너사 및 관리자는 총괄 관리자 승인이 필요 합니다.':
        'ບັນຊີຄູ່ຮ່ວມງານ ແລະ ຜູ້ບໍລິຫານຕ້ອງໄດ້ຮັບອະນຸມັດຈາກຜູ້ບໍລິຫານສູງສຸດ.',
    '이메일 인증 코드 보내기': 'ສົ່ງລະຫັດຢືນຢັນອີເມວ',
    '이메일 인증 코드 다시 보내기': 'ສົ່ງລະຫັດຢືນຢັນອີເມວອີກຄັ້ງ',
    '인증 코드 다시 보내기': 'ສົ່ງລະຫັດອີກຄັ້ງ',
    '이메일 인증 코드': 'ລະຫັດຢືນຢັນອີເມວ',
    '메일로 받은 인증 코드 입력': 'ປ້ອນລະຫັດທີ່ໄດ້ຮັບທາງອີເມວ',
    '이메일 인증 코드를 입력해 주세요.': 'ກະລຸນາປ້ອນລະຫັດຢືນຢັນອີເມວ.',
    '인증 확인 및 가입 완료': 'ຢືນຢັນ ແລະ ສຳເລັດການລົງທະບຽນ',
    '취소': 'ຍົກເລີກ',
    '저장': 'ບັນທຶກ',
    '변경': 'ປ່ຽນ',
    '탈퇴 확인': 'ຢືນຢັນລຶບບັນຊີ',
    '인증 코드 전송 실패': 'ສົ່ງລະຫັດຢືນຢັນບໍ່ສຳເລັດ',
    '인증 코드 재전송 실패': 'ສົ່ງລະຫັດຢືນຢັນຄືນບໍ່ສຳເລັດ',
    '이메일 인증 실패': 'ຢືນຢັນອີເມວບໍ່ສຳເລັດ',
    '이메일 인증 및 회원가입이 완료되었습니다. 로그인해 주세요.':
        'ຢືນຢັນອີເມວ ແລະ ລົງທະບຽນສຳເລັດ. ກະລຸນາເຂົ້າລະບົບ.',
    '{role} 가입 신청이 완료되었습니다. 총괄 관리자 승인 후 로그인할 수 있습니다.':
        'ສົ່ງຄຳຂໍລົງທະບຽນ {role} ແລ້ວ. ສາມາດເຂົ້າລະບົບຫຼັງຈາກຜູ້ບໍລິຫານສູງສຸດອະນຸມັດ.',
    '회원 정보 변경': 'ແກ້ໄຂຂໍ້ມູນສະມາຊິກ',
    '주소(선택)': 'ທີ່ຢູ່ (ບໍ່ບັງຄັບ)',
    '암호 변경': 'ປ່ຽນລະຫັດຜ່ານ',
    '기존 암호': 'ລະຫັດຜ່ານປັດຈຸບັນ',
    '현재 사용 중인 암호 입력': 'ປ້ອນລະຫັດຜ່ານປັດຈຸບັນ',
    '기존 암호을(를) 입력해 주세요.': 'ກະລຸນາປ້ອນລະຫັດຜ່ານປັດຈຸບັນ.',
    '새 암호': 'ລະຫັດຜ່ານໃໝ່',
    '대문자·소문자·숫자 포함 8자 이상':
        'ຢ່າງໜ້ອຍ 8 ຕົວ ມີຕົວພິມໃຫຍ່, ຕົວພິມນ້ອຍ ແລະ ຕົວເລກ',
    '새 암호 확인': 'ຢືນຢັນລະຫັດຜ່ານໃໝ່',
    '새 암호가 서로 일치하지 않습니다.': 'ລະຫັດຜ່ານໃໝ່ບໍ່ກົງກັນ.',
    '인증 이메일: {email}': 'ອີເມວຢືນຢັນ: {email}',
    '이메일 인증 코드를 먼저 받아 입력해 주세요.':
        'ກະລຸນາຂໍ ແລະ ປ້ອນລະຫັດຢືນຢັນອີເມວກ່ອນ.',
    '이메일 인증 코드 전송 실패': 'ສົ່ງລະຫັດຢືນຢັນອີເມວບໍ່ສຳເລັດ',
    '암호 변경 실패': 'ປ່ຽນລະຫັດຜ່ານບໍ່ສຳເລັດ',
    '회원 탈퇴': 'ລຶບບັນຊີ',
    '회원 탈퇴를 진행하시겠습니까?': 'ທ່ານຕ້ອງການລຶບບັນຊີບໍ?',
    '탈퇴 시 3일 동안 탈퇴 아이디/Email로 재가입이 안되니 신중하게 확인 바랍니다.':
        'ຫຼັງລຶບບັນຊີ ຈະບໍ່ສາມາດລົງທະບຽນດ້ວຍ ID/ອີເມວເກົ່າໄດ້ 3 ມື້.',
    '본인 암호': 'ລະຫັດຜ່ານປັດຈຸບັນ',
    '본인 암호을(를) 입력해 주세요.': 'ກະລຸນາປ້ອນລະຫັດຜ່ານປັດຈຸບັນ.',
    '회원 탈퇴 실패': 'ລຶບບັນຊີບໍ່ສຳເລັດ',
    'Supabase의 Confirm Email 설정이 꺼져 있습니다. 이메일 인증 코드 회원가입을 사용하려면 Confirm Email을 활성화해 주세요.':
        'Confirm Email ຖືກປິດໃນ Supabase. ກະລຸນາເປີດເພື່ອໃຊ້ລະຫັດອີເມວໃນການລົງທະບຽນ.',
    '알림 조회 실패': 'ໂຫຼດການແຈ້ງເຕືອນບໍ່ສຳເລັດ',
    '{name}님 로그인되었습니다.': '{name} ເຂົ້າລະບົບແລ້ວ.',
    '상태: {status}': 'ສະຖານະ: {status}',
    '예정': 'ກຳນົດໄວ້',
    '운송 중': 'ກຳລັງຂົນສົ່ງ',
    '대표번호 링크는 추후 관리자 설정이 필요합니다.':
        'ລິ້ງເບີຫຼັກຕ້ອງໃຫ້ຜູ້ບໍລິຫານຕັ້ງຄ່າ.',
    '참여 코드 9112': 'ລະຫັດເຂົ້າຮ່ວມ: 9112',
    '링크를 열 수 없습니다.': 'ບໍ່ສາມາດເປີດລິ້ງໄດ້.',
    'LK그룹 카카오톡 단톡방': 'ກຸ່ມ KakaoTalk ຂອງ LK Group',
    '오픈상담톡(한국어, Eng, ລາວ)': 'Open Chat ປຶກສາ (ເກົາຫຼີ, ອັງກິດ, ລາວ)',
    '카카오톡(대표번호, Eng, ລາວ)': 'KakaoTalk (ເບີຫຼັກ, ອັງກິດ, ລາວ)',
    'WhatsApp(한국어, Eng, ລາວ)': 'WhatsApp (ເກົາຫຼີ, ອັງກິດ, ລາວ)',
    'WhatsApp(대표번호, Eng, ລາວ)': 'WhatsApp (ເບີຫຼັກ, ອັງກິດ, ລາວ)',
    'LK Group 블로그': 'ບລັອກ LK Group',
    'LK Group 사무실 위치': 'ທີ່ຕັ້ງຫ້ອງການ LK Group',
    '할인율 적용': 'ນຳໃຊ້ສ່ວນຫຼຸດ',
    '할인율 (%)': 'ສ່ວນຫຼຸດ (%)',
    '예: 20': 'ຕົວຢ່າງ: 20',
    '할인 해제': 'ຍົກເລີກສ່ວນຫຼຸດ',
    '적용': 'ນຳໃຊ້',
    '할인율은 0~100% 범위로 입력해 주세요.': 'ກະລຸນາປ້ອນສ່ວນຫຼຸດ 0–100%.',
    '기타 비용 추가': 'ເພີ່ມຄ່າໃຊ້ຈ່າຍອື່ນ',
    '비용 이름': 'ຊື່ຄ່າໃຊ້ຈ່າຍ',
    '예: 통관비용, 보관료, 기타 수수료': 'ຕົວຢ່າງ: ພາສີ, ຄ່າເກັບຮັກສາ ຫຼື ຄ່າອື່ນ',
    '금액 (USD)': 'ຈຳນວນເງິນ (USD)',
    '비용 이름과 0보다 큰 USD 금액을 입력해 주세요.':
        'ກະລຸນາປ້ອນຊື່ຄ່າໃຊ້ຈ່າຍ ແລະ ຈຳນວນ USD ຫຼາຍກວ່າ 0.',
    '추가': 'ເພີ່ມ',
    '로그인 필요': 'ຕ້ອງເຂົ້າລະບົບ',
    '운임 확인 및 견적 요청은 회원 로그인 후 이용하실 수 있습니다.':
        'ກະລຸນາເຂົ້າລະບົບເພື່ອກວດຄ່າຂົນສົ່ງ ແລະ ຂໍໃບສະເໜີລາຄາ.',
    '대량 혹은 특수 견적 요청은 실명 및 회신을 위해 로그인 후 이용해 주세요.':
        'ກະລຸນາເຂົ້າລະບົບເພື່ອສົ່ງຄຳຂໍລາຄາຈຳນວນຫຼາຍ ຫຼື ພິເສດ ເພື່ອຢືນຢັນຊື່ ແລະ ຮັບຄຳຕອບ.',
    '회원 로그인': 'ເຂົ້າລະບົບສະມາຊິກ',
    '선택한 박스의 무게와 가로·세로·높이를 모두 입력해 주세요.':
        'ກະລຸນາປ້ອນນ້ຳໜັກ, ຄວາມຍາວ, ຄວາມກວ້າງ ແລະ ຄວາມສູງຂອງທຸກກ່ອງ.',
    '운임을 확인할 박스를 하나 이상 선택해 주세요.':
        'ກະລຸນາເລືອກຢ່າງໜ້ອຍ 1 ກ່ອງເພື່ອຄຳນວນຄ່າຂົນສົ່ງ.',
    '대량 혹은 특수 견적 요청을 이용해 주세요.': 'ກະລຸນາໃຊ້ຄຳຂໍລາຄາແບບຈຳນວນຫຼາຍ ຫຼື ພິເສດ.',
    '협력/파트너사는 견적서 보기 권한이 없습니다.': 'ບັນຊີຄູ່ຮ່ວມງານບໍ່ສາມາດເບິ່ງໃບສະເໜີລາຄາໄດ້.',
    '견적서 권한 확인 실패': 'ກວດສິດເບິ່ງໃບສະເໜີລາຄາບໍ່ສຳເລັດ',
    '견적 요청 조회 실패': 'ໂຫຼດຄຳຂໍໃບສະເໜີລາຄາບໍ່ສຳເລັດ',
    '대량 혹은 특수 견적 요청': 'ຂໍລາຄາແບບຈຳນວນຫຼາຍ ຫຼື ພິເສດ',
    '견적 요청 수정': 'ແກ້ໄຂຄຳຂໍລາຄາ',
    '운송 경로': 'ເສັ້ນທາງຂົນສົ່ງ',
    '제목': 'ຫົວຂໍ້',
    '내용': 'ລາຍລະອຽດ',
    '기타 연락처': 'ຊ່ອງທາງຕິດຕໍ່ອື່ນ',
    '제목과 내용을 입력해 주세요.': 'ກະລຸນາປ້ອນຫົວຂໍ້ ແລະ ລາຍລະອຽດ.',
    '견적 요청': 'ຂໍໃບສະເໜີລາຄາ',
    '수정 저장': 'ບັນທຶກການແກ້ໄຂ',
    '견적 요청을 보냈습니다.': 'ສົ່ງຄຳຂໍລາຄາແລ້ວ.',
    '견적 요청을 수정했습니다.': 'ແກ້ໄຂຄຳຂໍລາຄາແລ້ວ.',
    '견적 요청 처리 실패': 'ຈັດການຄຳຂໍລາຄາບໍ່ສຳເລັດ',
    '추가 회신': 'ຂໍ້ຄວາມເພີ່ມເຕີມ',
    '추가 내용': 'ລາຍລະອຽດເພີ່ມເຕີມ',
    '송부': 'ສົ່ງ',
    '추가 회신 실패': 'ສົ່ງຂໍ້ຄວາມເພີ່ມບໍ່ສຳເລັດ',
    '견적 요청을 삭제하시겠습니까?': 'ລຶບຄຳຂໍລາຄານີ້ບໍ?',
    '삭제 처리 실패': 'ດຳເນີນການລຶບບໍ່ສຳເລັດ',
    '삭제 취소 실패': 'ຍົກເລີກການລຶບບໍ່ສຳເລັດ',
    '지금 목록에서 삭제하시겠습니까?': 'ລຶບອອກຈາກລາຍການຕອນນີ້ບໍ?',
    '바로 삭제 실패': 'ລຶບທັນທີບໍ່ສຳເລັດ',
    '확인': 'ຕົກລົງ',
    '이 기타 비용에도 현재 할인율 적용': 'ນຳໃຊ້ສ່ວນຫຼຸດປັດຈຸບັນກັບຄ່ານີ້',
    '박스 {index} · 청구중량 {weight}kg · 단가 USD {rate}{moving}{packing}':
        'ກ່ອງ {index} · ນ້ຳໜັກຄິດໄລ່ {weight}kg · ລາຄາ USD {rate}{moving}{packing}',
    ' · 이삿짐 통관 +\${amount}': ' · ພາສີເຄື່ອງຍ້າຍບ້ານ +\${amount}',
    ' · 박스 포장 +\${amount}': ' · ຄ່າບັນຈຸກ່ອງ +\${amount}',
    '기타 비용 · {name}{discount}': 'ຄ່າອື່ນ · {name}{discount}',
    ' · 할인 적용': ' · ນຳໃຊ້ສ່ວນຫຼຸດ',
    '할인 전  USD {amount}': 'ກ່ອນຫຼຸດ  USD {amount}',
    '할인 {percent}%  -{amount}': 'ສ່ວນຫຼຸດ {percent}%  -{amount}',
    '총 운임  USD {amount}': 'ຄ່າຂົນສົ່ງລວມ  USD {amount}',
    '운임은 USD 기준이며, 이외 화폐는 가견적 안내시의 환율 기준이므로, 최종 운임 책정시의 환율변동으로 인한 운임 차이가 발생할수 있으니, 참고용으로만 확인 부탁 드립니다.':
        'ຄ່າຂົນສົ່ງຄິດເປັນ USD. ສະກຸນເງິນອື່ນໃຊ້ອັດຕາແລກປ່ຽນໂດຍປະມານ ແລະ ອາດແຕກຕ່າງຈາກຄ່າສຸດທ້າຍ.',
    '삭제 대기': 'ລໍຖ້າລຶບ',
    '회신 완료': 'ຕອບແລ້ວ',
    '관리자 확인': 'ລໍຖ້າຜູ້ບໍລິຫານກວດ',
    '확인 전': 'ລໍຖ້າກວດ',
    '기타 연락처: {contact}': 'ຊ່ອງທາງຕິດຕໍ່ອື່ນ: {contact}',
    '삭제 취소': 'ຍົກເລີກການລຶບ',
    '바로 삭제': 'ລຶບທັນທີ',
    '수정': 'ແກ້ໄຂ',
    '삭제': 'ລຶບ',
    '관리자 회신': 'ຄຳຕອບຈາກຜູ້ບໍລິຫານ',
    '일정 조회 실패': 'ໂຫຼດຕາຕະລາງບໍ່ສຳເລັດ',
    '선적 일정 삭제 확인': 'ຢືນຢັນລຶບຕາຕະລາງຂົນສົ່ງ',
    '삭제하면 홈 화면에서는 즉시 보이지 않습니다.\n삭제된 자료는 30일 동안 임시 보관 후 완전히 삭제됩니다.':
        'ຫຼັງລຶບ ລາຍການຈະຫາຍຈາກໜ້າຫຼັກທັນທີ.\nຂໍ້ມູນຈະຖືກເກັບ 30 ມື້ກ່ອນລຶບຖາວອນ.',
    '삭제 대기중으로 변경했습니다. 30일 후 완전히 삭제됩니다.':
        'ຍ້າຍໄປລໍຖ້າລຶບແລ້ວ. ຈະລຶບຖາວອນຫຼັງ 30 ມື້.',
    '삭제 요청 실패': 'ຂໍລຶບບໍ່ສຳເລັດ',
    '삭제를 취소했습니다. 홈 화면에 다시 표시됩니다.':
        'ຍົກເລີກການລຶບແລ້ວ. ລາຍການຈະສະແດງໃນໜ້າຫຼັກອີກຄັ້ງ.',
    '임시 보관 기간을 무시하고 DB에서 완전히 삭제할까요?':
        'ລຶບອອກຈາກຖານຂໍ້ມູນຖາວອນຕອນນີ້ບໍ?',
    '선적 일정을 완전히 삭제했습니다.': 'ລຶບຕາຕະລາງຂົນສົ່ງຖາວອນແລ້ວ.',
    '선적 일정 추가': 'ເພີ່ມຕາຕະລາງຂົນສົ່ງ',
    '선적 일정 편집': 'ແກ້ໄຂຕາຕະລາງຂົນສົ່ງ',
    '년도': 'ປີ',
    '항차': 'ຖ້ຽວ',
    '예: 17항차': 'ຕົວຢ່າງ: ຖ້ຽວ 17',
    '항차을(를) 입력해 주세요.': 'ກະລຸນາປ້ອນຖ້ຽວ.',
    '출발지': 'ຕົ້ນທາງ',
    '예: 인천 국제 공항': 'ຕົວຢ່າງ: ສະໜາມບິນສາກົນອິນຊອນ',
    '출발지을(를) 입력해 주세요.': 'ກະລຸນາປ້ອນຕົ້ນທາງ.',
    '도착지': 'ປາຍທາງ',
    '예: 라오스 왓따이 공항': 'ຕົວຢ່າງ: ສະໜາມບິນວັດໄຕ, ລາວ',
    '도착지을(를) 입력해 주세요.': 'ກະລຸນາປ້ອນປາຍທາງ.',
    '접수 마감일': 'ວັນປິດຮັບ',
    '20260903으로 입력해도 작성 시 2026-09-03으로 자동 변환됩니다.':
        'ການປ້ອນ 20260903 ຈະຖືກປ່ຽນເປັນ 2026-09-03 ອັດຕະໂນມັດ.',
    '도착 예정일': 'ວັນຄາດວ່າຈະຮອດ',
    '날짜를 입력해 주세요.': 'ກະລຸນາປ້ອນວັນທີ.',
    '예: 2026-09-03 형식으로 입력해 주세요.':
        'ກະລຸນາປ້ອນວັນທີເຊັ່ນ 2026-09-03.',
    '올바른 날짜를 입력해 주세요.': 'ກະລຸນາປ້ອນວັນທີໃຫ້ຖືກຕ້ອງ.',
    '존재하는 날짜를 입력해 주세요.': 'ກະລຸນາປ້ອນວັນທີທີ່ມີຢູ່ຈິງ.',
    'YYYY-MM-DD 또는 YYYYMMDD 형식': 'ຮູບແບບ YYYY-MM-DD ຫຼື YYYYMMDD',
    '상세 내용 또는 추가 내용': 'ລາຍລະອຽດ ຫຼື ຂໍ້ມູນເພີ່ມ',
    '예: 출항/도착 일정은 현지 사정에 따라 변경될 수 있습니다.':
        'ຕົວຢ່າງ: ວັນອອກ ແລະ ວັນຮອດອາດປ່ຽນຕາມສະພາບທ້ອງຖິ່ນ.',
    '작성': 'ສ້າງ',
    '작성 실패': 'ສ້າງບໍ່ສຳເລັດ',
    '저장 실패': 'ບັນທຶກບໍ່ສຳເລັດ',
    '선적 일정 목록 관리': 'ຈັດການຕາຕະລາງຂົນສົ່ງ',
    '일정 추가': 'ເພີ່ມຕາຕະລາງ',
    '등록된 선적 일정이 없습니다.': 'ບໍ່ມີຕາຕະລາງຂົນສົ່ງ.',
    '삭제 대기중': 'ລໍຖ້າລຶບ',
    '마감: {close} · 도착예정: {arrival}':
        'ປິດຮັບ: {close} · ຄາດວ່າຮອດ: {arrival}',
    '공지 및 안내 조회 실패': 'ໂຫຼດແຈ້ງການບໍ່ສຳເລັດ',
    '공지 및 안내 삭제 확인': 'ຢືນຢັນລຶບແຈ້ງການ',
    '공지 및 안내를 완전히 삭제했습니다.': 'ລຶບແຈ້ງການຖາວອນແລ້ວ.',
    '공지 및 안내 추가': 'ເພີ່ມແຈ້ງການ',
    '공지 및 안내 편집': 'ແກ້ໄຂແຈ້ງການ',
    '예: 9월 한국→라오스 해상 일정 안내': 'ຕົວຢ່າງ: ຕາຕະລາງທາງເຮືອ ເກົາຫຼີ → ລາວ ເດືອນກັນຍາ',
    '공지 내용을 입력해 주세요.': 'ກະລຸນາປ້ອນລາຍລະອຽດແຈ້ງການ.',
    '등록 날짜 표시': 'ສະແດງວັນທີເຜີຍແຜ່',
    '상단 고정': 'ປັກໄວ້ເທິງ',
    '공지 및 안내 관리': 'ຈັດການແຈ້ງການ',
    '관리자 권한이 필요합니다.': 'ຕ້ອງມີສິດຜູ້ບໍລິຫານ.',
    '공지 및 안내 목록 관리': 'ຈັດການລາຍການແຈ້ງການ',
    '등록된 공지 및 안내가 없습니다.': 'ບໍ່ມີແຈ້ງການ.',
    '직접 입력 (선택)': 'ປ້ອນເອງ (ບໍ່ບັງຄັບ)',
    '비어 있는 영어·라오스어는 자동 번역됩니다. 직접 입력한 번역은 우선 저장됩니다.':
        'ຊ່ອງອັງກິດ ແລະ ລາວທີ່ວ່າງຈະຖືກແປອັດຕະໂນມັດ. ຂໍ້ຄວາມທີ່ປ້ອນເອງຈະຖືກເກັບເປັນຫຼັກ.',
  };
}
