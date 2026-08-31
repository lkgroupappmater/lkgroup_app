from pathlib import Path

root = Path.cwd()
p = root / "lib" / "services" / "excel_import_service.dart"
if not p.exists():
    raise SystemExit("lib/services/excel_import_service.dart not found. Run from project root.")

text = p.read_text(encoding="utf-8-sig")

def once(old, new, label):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"{label}: expected 1 match, found {n}. No file changed.")
    text = text.replace(old, new, 1)

# Patch167 finalizer existed, but resequence was accidentally omitted.
once(
"""          'p_route': routeLabel,
          'p_year': year,
          'p_voyage': voyage,
        },""",
"""          'p_route': routeLabel,
          'p_year': year,
          'p_voyage': voyage,
          'p_resequence': true,
        },""",
"finalizer resequence",
)

# Avoid province/city No. collisions: both sections restart at No.1.
once(
"""    final bySourceNo = <int, Map<String, dynamic>>{};""",
"""    final bySourceNo = <String, Map<String, dynamic>>{};""",
"delivery key map",
)

# Use section-aware internal source id. Province keeps old No.; city gets +10000.
once(
"""        final sourceNo = currentSourceNo!;
        final customerName = rowCustomer.isNotEmpty ? rowCustomer : currentCustomerName;""",
"""        final sourceNo = currentSourceNo!;
        final profileSourceNo =
            section.type == 'city' ? 10000 + sourceNo : sourceNo;
        final profileKey = '${section.type ?? 'legacy'}|$sourceNo';
        final customerName = rowCustomer.isNotEmpty ? rowCustomer : currentCustomerName;""",
"section-aware source id",
)

once(
"""          'source_no': sourceNo,""",
"""          'source_no': profileSourceNo,""",
"profile source_no",
)

once(
"""        final existing = bySourceNo[sourceNo];""",
"""        final existing = bySourceNo[profileKey];""",
"lookup composite key",
)

once(
"""          bySourceNo[sourceNo] = profile;""",
"""          bySourceNo[profileKey] = profile;""",
"store composite key",
)

# Current BASE Excel is route-level source of truth. Clear stale profiles for this route
# before re-inserting the current workbook list. This DELETE has a route WHERE condition.
old = """    if (bySourceNo.isEmpty) return 0;

    await SupabaseService.client.from('local_delivery_profiles').upsert(
          bySourceNo.values.toList(growable: false),
          onConflict: 'route_key,source_no',
        );"""
new = """    if (bySourceNo.isEmpty) return 0;

    await SupabaseService.client
        .from('local_delivery_profiles')
        .delete()
        .eq('route_key', routeKey);

    await SupabaseService.client.from('local_delivery_profiles').upsert(
          bySourceNo.values.toList(growable: false),
          onConflict: 'route_key,source_no',
        );"""
once(old, new, "replace stale route profiles")

p.write_text(text, encoding="utf-8")
print("Patch167B Dart applied.")
