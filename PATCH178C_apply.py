from pathlib import Path

p = Path("lib/services/excel_import_service.dart")
s = p.read_text(encoding="utf-8-sig")

old = """        final profileSourceNo =
            section.type == 'city' ? 10000 + sourceNo : sourceNo;
        final profileKey = '${section.type ?? 'legacy'}|$sourceNo';"""
new = """        final profileSourceNo =
            section.type == 'city' ? 10000 + sourceNo : sourceNo;

        // DB conflict key is (route_key, source_no), so the in-memory key MUST
        // be the same identity. Using section/type in the Dart key allowed two
        // rows with the same final source_no into one bulk UPSERT, causing
        // SQLSTATE 21000: ON CONFLICT DO UPDATE ... row a second time.
        final profileKey = '$profileSourceNo';"""

if old not in s:
    raise SystemExit("local delivery profileKey anchor not found")
s = s.replace(old, new, 1)

old2 = """    await SupabaseService.client.from('local_delivery_profiles').upsert(
          bySourceNo.values.toList(growable: false),
          onConflict: 'route_key,source_no',
        );"""
new2 = """    // Defensive one-row UPSERT: even if a future BASE layout produces
    // rows that normalize to the same DB key, PostgreSQL will never receive
    // duplicate conflict targets in the same INSERT statement.
    for (final profile in bySourceNo.values) {
      await SupabaseService.client
          .from('local_delivery_profiles')
          .upsert(
            profile,
            onConflict: 'route_key,source_no',
          );
    }"""

if old2 not in s:
    raise SystemExit("local delivery bulk upsert anchor not found")
s = s.replace(old2, new2, 1)

p.write_text(s, encoding="utf-8")
print("Patch178C applied.")
