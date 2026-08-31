LKGroup Patch162d FINAL PARSE REPAIR

Purpose:
- Replaces only wireStatementAutomationFormulas() in export-shipment-excel/index.ts.
- Uses ASCII-only source in the PowerShell patch to avoid Windows PowerShell 5.1 Korean encoding corruption.
- Korean label matching is preserved via Unicode escape sequences inside TypeScript.
- Does not touch FreightService, DB schema, app UI, or other exporter helpers.

Run from project root:
powershell -ExecutionPolicy Bypass -File .\patch162d\apply_patch162d.ps1

Then:
npx supabase functions deploy export-shipment-excel
flutter analyze
