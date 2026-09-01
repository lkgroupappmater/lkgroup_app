Patch190
1. 박성호/CEO: raw identity token reaches fallback matcher. No 100% hardcode; BASE/DB remains source.
2. 고객 리스트: mobile dropdown overflow reduction, actual quantity sum, bottom summary, edit receipt+Zone.
3. 명세서: final USD/KIP/THB/KRW money rows right aligned.
4. 견적서: discount percent/amount moved toward 4/5 and final money rows right aligned.

IMPORTANT: global cargo-existence logic is NOT changed in this patch.
Current customer-list already excludes blank receipt numbers; display count now uses quantity.
We will audit all calculation/export paths before enforcing quantity > 0 globally.

No SQL / Edge deploy / V00 upload / recalc.
