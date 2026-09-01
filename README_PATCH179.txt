Patch179

- Rejects bogus generic discount group labels such as 할인금액/할인율/할인.
- Searches a wider BASE area and prefers semantic group names:
  라선협, 지상사/협의회/회원사, 법인장/지인, 아파트, 기업, 특별 etc.
- Right statement discount percentage now uses FreightService line.discountPercent,
  not discount dollars divided by gross dollars.
  Therefore 20% still displays even when current sample amount is $0.
- Right row label is simply 할인 20% as requested.
- Remark becomes e.g. 라선협 할인 20% 적용 after V00 is uploaded again.
- If DB still contains the old bogus label before refresh, it falls back to 할인 20% 적용.

SQL: none
Edge deploy: none
After applying, upload KR_LA_SEA_2026_V00_SHIPMENTS.xlsx again.
V00 BASE mode will automatically refresh existing route batches.
