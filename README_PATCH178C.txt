Patch178C

Root cause of the remaining SQLSTATE 21000:
- local_delivery_profiles DB upsert conflict key = route_key, source_no
- but Dart in-memory dedupe key used section.type + sourceNo
- therefore two different in-memory keys could still become the same DB source_no
  and one bulk INSERT ... ON CONFLICT tried to update the same DB row twice.

Fix:
1) in-memory delivery key now exactly matches final profileSourceNo
2) local_delivery_profiles upsert is done one row at a time as a defensive guard
3) no SQL changes
4) no Edge deploy

This patch does NOT touch real shipment rows.
V00 remains BASE-only route update mode.
