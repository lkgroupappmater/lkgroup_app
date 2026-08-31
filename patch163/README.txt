LKGroup Patch163 - BASE local delivery + route-specific discount safety

Scope
1) BASE Excel "시내, 지방배송" sheet is imported into local_delivery_profiles.
2) Excel fill semantics are preserved:
   - green row (RGB 92D050) => city
   - white/default => province
   - yellow cell (RGB FFFF00), especially local company/destination => preferred
3) Matching prefers preferred=true, then source_no.
4) Discount rules remain route_key specific.
   KR-LA SEA and KR-LA AIR are never merged by this patch.
   Existing FreightService already requests the current route_key and prefers exact-route rules.

Apply
1. Extract ZIP into project root so .\patch163 exists.
2. Run:
   powershell -ExecutionPolicy Bypass -File .\patch163\apply_patch163.ps1
3. In Supabase SQL Editor run:
   supabase/supabase_095_local_delivery_import_preferred.sql
4. Run:
   flutter analyze

No Edge Function deploy is required for Patch163.

Important
- Run SQL 095 before testing a new BASE Excel upload, because the importer writes the new preferred column.
- Patch163 does not touch FreightService formulas, statement layout, quotation layout, receipt numbering, or Patch162 exporter code.
