# Explicit shipment Zones — 2026-09-22

The shared database now preserves a directly entered or approved per-shipment
Zone before applying automatic customer, delivery or quantity defaults. There
is no Zone registry or whitelist: custom text such as ST or Z-임시 is accepted.

- Excel changes to existing cargo still require the existing approval flow.
- New custom Excel Zones are explicit. Cached A/B/C/F/102 values on new Excel
  rows remain automatic; approving or directly changing one makes it explicit.
- Clearing a manually entered Zone restores automatic calculation.
- App/web manual add, bulk editing, approval, import finalization and legacy
  maintenance recalculation all preserve explicit Zones.
- Existing receipt numbering, discounts, charges, lock checks and permissions
  remain in place. Neither a client binary nor an App reinstall is required.

Production migration: preserve_explicit_shipment_zones.
Regression: verify_explicit_shipment_zones.sql runs through the actual shared
RPCs as an authenticated administrator and rolls back every fixture, approval
notification and revision. It covers pending/rejected/modified approvals,
reupload idempotency, arbitrary text, quantity defaults, direct standard-Zone
edits, reset, both manual-add clients, legacy recalculation and locked cargo.

After a rollback rehearsal, the 43 active, unlocked 뷰티판다 cargo rows in
한국->라오스 해상 / 2026 / 09 were restored from F to their latest approved ST.
Both client finalizers were then run. Assertions confirmed that every other
cargo field, all other voyage rows, discount rules and extra charges were
unchanged. The active company discount remains 10%. Existing approval history
and subsequent duplicate pending requests were retained without alteration.
