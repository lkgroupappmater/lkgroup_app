Patch182R - IMPORTANT CORRECTION

- Removes Patch182's incorrect Park Seongho = hardcoded 100% discount.
- NO customer/person gets a fixed discount in Dart.
- Discount percent and discount group/name come ONLY from the resolved
  customer discount rule/chart (or explicit receipt-level manual discount).
- Park Seongho's LKS 100 / Zone 102 fixed routing can remain separate;
  this patch only corrects the DISCOUNT calculation/display.
- Right statement panel uses the actual FreightService discountPercent:
    할인 or 특별할인 label + actual chart percentage + actual dollar amount.
- Remark also follows the resolved discount rule; no Park-specific suppression.

SQL none.
Edge deploy none.
V00 re-upload not required for this rollback itself.
