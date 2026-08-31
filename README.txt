Patch172A - Excel download unblock / fast-path
- Fix 500 permission denied receipt_extra_costs via service_role SELECT only.
- Edge export reuses shipment_rows already fetched from DB by Flutter instead of re-querying shipments.
- DB fallback remains for old/direct callers.
- Statement Remark content centered / enlarged.
- No unrelated UI changes.
After applying: flutter analyze -> SQL -> deploy Edge.
Then download V08 XLSX and upload it to ChatGPT for actual output verification.
