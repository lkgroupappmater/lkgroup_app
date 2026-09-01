from pathlib import Path

p = Path("supabase/functions/export-shipment-excel/index.ts")
if not p.exists():
    raise SystemExit("PATCH200C1 STOP: exporter not found")

s = p.read_text(encoding="utf-8-sig")

bad = '/<c\\\\b[^>]*r="([A-Z]+)\\\\d+"[^>]*(?:\\\\/>|>[\\\\s\\\\S]*?<\\\\/c>)/g,'
good = '/<c\\b[^>]*r="([A-Z]+)\\d+"[^>]*(?:\\/>|>[\\s\\S]*?<\\/c>)/g,'

if bad in s:
    s = s.replace(bad, good, 1)
elif good in s:
    print("PATCH200C1: already fixed")
else:
    raise SystemExit("PATCH200C1 STOP: parse-error regex anchor not found")

p.write_text(s, encoding="utf-8")
print("PATCH200C1 applied: TypeScript regex literal repaired")
