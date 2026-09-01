Patch193
- A4 portrait customer sign list
- top margin about one title-line, bottom almost none
- about 25 one-line customers/page
- receipt ascending numeric order
- centered customer/company name
- no phone column
- columns: receipt / customer-company / zone / box number / qty / signature
- box numbers comma-separated, max 10 per line
- rows grow only when a customer needs extra box-number lines
- delivery labels only in signature cell:
  지방배송 / 지방배송(선결제) / 시내배송 / 시내배송(선결제)
- signature cell gets the established delivery color
- first page title only; later pages start with table
No SQL / Edge / recalc / V00.

정렬 추가:
- 일반 영수번호 숫자 오름차순
- 박성호 대표 / LKS 100은 수취인 불명 바로 앞
- 수취인 불명 / 미확인 / XX / 비숫자 영수번호는 절대 맨 마지막
