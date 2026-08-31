from pathlib import Path

p = Path.cwd() / "lib" / "services" / "shipment_service.dart"
if not p.exists():
    raise SystemExit("lib/services/shipment_service.dart not found. Run from lkgroup_app project root.")

text = p.read_text(encoding="utf-8-sig")

def replace_once(old, new, label):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"{label}: expected 1 match, found {n}. No file changed.")
    text = text.replace(old, new, 1)

replace_once(
"""    const chunkSize = 40;""",
"""    // Patch168: bulk-import RPC suppresses the expensive per-row normalize trigger.
    // 100 rows keeps request count low while avoiding one huge JSON payload.
    const chunkSize = 100;""",
"chunk size",
)

replace_once(
"""        'manager_upsert_unlocked_shipments',
        params: {'p_rows': payload},""",
"""        'manager_upsert_unlocked_shipments_bulk',
        params: {'p_rows': payload},""",
"bulk rpc",
)

old_retry = """      final isStatementTimeout =
          message.contains('57014') ||
          message.toLowerCase().contains('statement timeout');

      if (isStatementTimeout && rows.length > 5) {"""

new_retry = """      final lower = message.toLowerCase();
      final isRetryable =
          message.contains('57014') ||
          lower.contains('statement timeout') ||
          lower.contains('connection abort') ||
          lower.contains('connection reset') ||
          lower.contains('connection closed') ||
          lower.contains('clientexception');

      if (isRetryable && rows.length > 10) {"""

replace_once(old_retry, new_retry, "retry logic")

p.write_text(text, encoding="utf-8")
print("Patch168 Dart applied.")
