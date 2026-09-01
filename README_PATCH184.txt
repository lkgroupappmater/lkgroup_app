Patch184 - VERIFIED correction

Why 183R looked unapplied:
- previous menu search could hit a file that merely referenced the unloading screen,
  instead of the actual visible management-menu block.
- statement patch relied on an older exact text shape and could become a no-op.
This patch uses structural anchors and performs explicit post-patch verification.

1) Park Seongho discount
- NO hardcoded 100%.
- Current shipment phone/identity is 'CEO', so the previous numeric-only phone
  guard returned before consulting the discount chart.
- Now exact non-numeric identity tokens (CEO == CEO) are allowed as a strong match.
- The percentage still comes ONLY from customer discount DB/chart.
- Therefore if Park's chart row is 100%, statement shows 100%. If chart changes,
  the app follows the changed percentage automatically.

2) Statement / quotation adjustment area
- label left
- percent at ~54%-72% (visually near 2/3)
- amount at far right
- structural replacement, not fragile old-text replacement.

3) Management menu
- finds the actual LOCAL Dart file containing BOTH:
  '하역 자료 관리' and UnloadingListManagementScreen
- clones that exact menu item as '고객 리스트'
- verifies the navigation link exists after patch.

4) Excel customer list
- normal customers KEEP original A/B/C/F formula
- forced override ONLY:
  fixed 102 names -> 102
  city/province delivery, 김요셉, 뷰티판다 -> F
- title voyage + LKS XX + delivery signature words retained.

SQL none.
Edge deploy required for Excel exporter.
V00 reupload not required.
Recalculate not required.
