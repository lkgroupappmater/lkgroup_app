LKGroup Patch162 - Document Automation Pipeline

묶음 처리:
1) 할인/특별할인 + 시내/지방배송 자동문구를 shipments.special_note_auto와 실제 Excel P(비고)에 반영
2) 앱 명세서 Remark에 같은 자동문구 표시 + 기존 Inland/Delivery는 기존 CustomerBenefitService 연결 유지
3) Excel Row data 하단 X:AE에 DOCUMENT AUTOMATION 테이블 생성
   - Receipt / Customer / Phone / Remark Auto / Inland Delivery / Delivery Type / Extra USD / Amount USD
   - 영수번호 N2 기반 한-sheet 명세서 수식의 원천 데이터로 구성
   - Remark/Inland 표시 셀을 자동 탐색해 INDEX/MATCH 수식으로 연결
   - N3/N4/N5 보조수식도 같은 N2를 기준으로 자동 변경
4) 배송 유형 코드
   - city = 시내배송 (녹색 기준)
   - province = 일반 지방배송 (주황색 기준)
   - province_prepaid_kr = 지방배송 한국 선결제 (파란색 기준)
5) 기존 FreightService snapshot 운임 계산은 변경하지 않음. 기타비용은 운임 후 가산.

적용:
powershell -ExecutionPolicy Bypass -File .\apply_patch162.ps1

그 다음 Supabase SQL Editor:
supabase/supabase_094_document_automation_refresh.sql 실행

Edge Function 배포:
supabase functions deploy export-shipment-excel

검사:
flutter analyze

중요:
- Patch162는 원본 명세서 디자인/기존 운임 공식 자체를 재작성하지 않습니다.
- Excel 명세서 N2 영수번호 선택 구조와 기존 수식은 유지합니다.
- Row data 자동화 테이블을 추가하여 후속 수식 연결을 위한 단일 source를 만듭니다.
