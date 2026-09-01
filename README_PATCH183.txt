Patch183

1) Statement + quotation adjustment rows
- left: label
- around 2/3: percentage
- far right: amount
- applies to 할인 / 특별할인 / 세금 계산서(VAT)
- statement math is unchanged
- quotation currently has no customer-discount input, so percent/amount remain '-'
  but use the same layout.

2) Excel output - 고객 리스트
- SEA title xx항차 -> actual voyage
- receipt xx -> route prefix + XX (e.g. LKS XX)
- B: customer name from current DB shipment
- C Area Categorized: final DB F / 102 forcibly written, overriding formula
- E signature text:
  지방배송 / 지방배송(선결제) / 시내배송 / 시내배송(선결제)
- E cell delivery colors:
  province orange / province prepaid blue / city green / city prepaid yellow

3) Excel Remark
- Existing Row data DOCUMENT AUTOMATION / special_note_auto linkage is preserved.
- Share content -> discount group/% -> delivery already flows to statement Remark.
- Existing Excel discount/VAT formulas are preserved.

SQL: none
Edge deploy: required
V00 upload: not required
Recalculate: not required for this patch
