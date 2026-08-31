LKGroup Patch162b - exporter TypeScript regex repair

Purpose:
- Repairs ONLY the three malformed RegExp literals inserted by Patch162.
- Does not re-run Patch162 and does not touch SQL / Flutter UI / other files.
- Safe to run once; if the corrected text is already present it leaves it unchanged.

Run from project root:
powershell -ExecutionPolicy Bypass -File .\patch162b\apply_patch162b.ps1

Then:
npx supabase functions deploy export-shipment-excel
flutter analyze
