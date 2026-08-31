Patch168 - Fast Excel Upload

Confirmed root cause:
- Current DB has a FOR EACH ROW trigger (trg_shipments_auto_normalize).
- Every inserted/updated Excel row calls normalize_shipment_batch().
- 404 rows therefore trigger voyage-wide normalization hundreds of times.
- This explains minutes-long uploads and connection aborts.

Patch:
- Adds manager_upsert_unlocked_shipments_bulk(jsonb).
- Bulk RPC temporarily suppresses ONLY the auto-normalize trigger.
- Existing manager_upsert_unlocked_shipments is preserved.
- Patch167's finalizer still normalizes the voyage once after all rows/rules are ready.
- Dart chunk size 40 -> 100.
- Connection abort/reset/ClientException now uses split retry.

No Edge Function deployment.
No unrelated UI/design changes.
