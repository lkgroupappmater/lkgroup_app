Patch173 - Excel repair popup root-cause fix

실제 다운로드 XLSX를 XML 단위로 검사해서 원인을 확인했습니다.

1) JavaScript String.replace에 Excel formula '$N$2'를 replacement 문자열로 직접 전달함
   -> JS가 '$2'를 정규식 capture group으로 해석
   -> 실제 파일 수식이 '$N s="246"' 같은 깨진 문자열로 생성됨.

2) SEA 원본 템플릿은 N2:N3, L4:N4가 merge 상태인데
   N3/N4에 보조 수식을 강제로 기록함.
   -> Excel이 열 때 repair/remove records 경고 원인.

수정:
- formula replacement를 callback 방식으로 변경해 '$'를 문자 그대로 보존.
- N3/N4/N5 보조 수식 삽입 제거.
- 실제 Remark/Inland 표시 수식은 유지.
- calcChain 및 기존 디자인/수식 구조는 건드리지 않음.

SQL 없음.
Edge Function 재배포 필요.
