# App, website and offline Excel release contract

The same `export-shipment-excel` deployment serves both clients. Changes to
customer identity, delivery matching, discounts, remarks, pricing or statement
numbering must include their applicable Excel formulas and regression scenarios
in the same release. A server cannot translate arbitrary new app code into an
offline Excel formula automatically; the corresponding exporter implementation
is part of the feature, not a later optional task.

Deploy the exporter together with the online change. Its deployment revision
automatically invalidates all active BASEs; the scheduled `sync-excel-bases`
worker rebuilds them without an operator download. DB changes to the registered
policy tables also queue BASE regeneration. The worker runs once per minute and
claims one route per run. Downloads request a current validated generation even
while background refresh is pending.

Each BASE is published only after shared-formula validation, an upload/download
SHA-256 comparison, and a transaction checking both input revision and original
template identity. Concurrent input changes and uploads cause a retry, never an
overwrite. Failures keep the previous file and queue a retry after five minutes.
Original storage paths remain in source history. The worker does not import
cargo, merge customers, assign receipt numbers or overwrite issued voyage files.

Before releasing Excel-impacting work:

1. Update the applicable offline formulas/data mapping with the online rule.
2. Test representative rules, manual overrides, locks, historical receipt
   preservation, repeated BASE refreshes and shared-formula integrity.
3. Deploy the exporter and confirm every affected `excel_base_sync_state` is
   ready with the current exporter revision.
4. Download the real stored BASE and exported voyage files and audit their ZIP,
   XML, formulas, macro bytes and unchanged layout parts. Native Excel opening
   and recalculation must be checked when available; structural validation is
   not a claim that desktop Excel was executed.

Offline files already saved to a user's device are snapshots. Downloading the
latest BASE gets the current rules; offline edits rejoin the existing upload and
approval process. Do not silently change past voyage statement numbers.
