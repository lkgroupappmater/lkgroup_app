Patch181

Statement right yellow discount area:
Before:
  할인 20%                  -
After:
  할인              20%  -$0.00

If actual discount amount is non-zero:
  할인              20%  -$12.34

Special discount:
  특별할인          15%  -$8.50

The percentage shown is the same actual/fallback percentage already used
by the statement Remark logic.

Final USD calculation is unchanged:
gross freight + extra costs - actual discounts.

SQL: none
Edge deploy: none
V00 re-upload: not required
