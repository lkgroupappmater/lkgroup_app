# Excel template formatting contract (2026-11-18)

App and website use the same export / identity / finalizer service. This change does not change DB freight, customer matching, shipment data, discounts, routes or UI layouts.

## Problem and behavior

The supplied AIR voyage 22 workbook contains the approved header formatting. The existing VBA RestoreHeaderFontSizes runs on open/save/print and hard-codes font sizes, so a manually edited font can be overwritten. Server export validation previously checked formulas and stored bytes but did not check that original styles and header geometry remained intact. The reported date-to-currency conversion was not reproduced by replaying the current 14 transformation steps on the repaired attachment; historical corruption is not attributed to an unproven current code path.

- Keep the public VBA entry point, removing its hard-coded header formatting. Existing statement creation still copies the template sheet; item row fitting and monetary formats remain active.
- Apply formatting-only reference to the two exact existing SEA/AIR BASE storage paths and the exact AIR 2026 voyage 22 template path. No customer values, formulas, freight, or shipment data are copied from the attachment. Future uploads do not match these legacy paths and retain their own formatting.
- Restore customer-list A1:E3 and statement A1:N5 fonts, colors, borders, number formats, alignment and row heights from the supplied reference. Preserve values, formulas, merges, widths, VBA sheet identity and other routes' forms.
- Capture existing style tables and first-five-row formatting before transformations. Check again after VBA/presentation updates and before storage. Existing style indices must keep their definitions; new styles may be appended. Protect headers, row heights, merges, and widths; only the existing hidden cargo identity helper columns BA:BL are exempt from width checks. Rebuilt identity helpers and the two intentionally shared delivery sheets are excluded from header snapshots.
- Preserve template theme. Reject a changed date style, global font/style definition or header formatting instead of returning a successful download.
- Internal manifest is consumed before storage; authentication and storage access remain unchanged. Old in-flight exporters are accepted with an explicitly labeled finalizer-stage snapshot during rollout. New exports must report capture_stage=source.
- Reuse wrapped styles instead of adding duplicate styles or silently replacing an unknown style with style 0.

Reference SHA-256: `6bdced1d658db44022264164f4deef9193e8b15b0146a0abd8fdc8d358187225`. The committed reference has style XML and header coordinate/style mappings only. The customer workbook itself is not committed.

## Validation

- Web tests: 126 pass before final rollout checks.
- App shared backend tests: 30 pass; focused VBA, presentation and identity tests: 25 pass.
- Replayed all 14 relevant transformations on the supplied AIR 22 workbook and historical SEA/AIR source forms. Header formats remained intact; repeated VBA upgrades were idempotent.
- New regression tests cover date/currency mix-ups, global style/font changes, merge loss, style counts, macro behavior, and future upload precedence.
- Native Microsoft Excel execution is not available in this runtime; package structure, formulas, macro source and style semantics are tested. Production BASE results are recorded in policy_summary.integrity.template_styles and the existing stored_download_verified field.
