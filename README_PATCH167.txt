Patch167
========

Scope only:
- BASE Excel local/province delivery table is written before shipment upsert.
- Removes expensive global special-note refresh from the delivery-table import path.
- Runs existing admin_finalize_excel_batch_rules once after the full batch is ready.
- Adds a small colored delivery badge in Cargo Management:
  * province = orange
  * province prepaid = blue
  * city = green
  * city prepaid = yellow

Expected result after re-upload:
- delivery data participates in matching during normalization
- province forced zone F can apply
- receipt priority can become province -> city -> normal -> Park -> unknown
- statement/export can receive delivery company/address/prepaid fields through the existing DB path
- upload should avoid the previous unnecessary global refresh

No Edge Function change in this patch.
No unrelated UI/layout change.
