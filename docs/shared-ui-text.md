# Shared web/app UI text — 2026-09-17

The existing public.site_public_text table remains the only saved copy source.
No new table, database, permission, carrier or financial logic is introduced.

## Requested title

- KO: 라오스 국내 배송 조회 & 관리
- EN: Laos Domestic Delivery Tracking & Management
- LO: ການຕິດຕາມແລະຈັດການການຂົນສົ່ງໃນປະເທດລາວ

The public title uses domesticTracking in both clients; domestic.title is a
read-compatible alias. The management menu remains 라오스 국내 배송 관리.
The existing saved title/translations were already correct and were not rewritten.
Other legacy aliases are listed in shared-ui-text/contract.json; duplicate web
editor entries are folded into the canonical entry. Latest timestamp wins when
legacy and canonical records coexist; canonical wins tied timestamps.

## Scope and refresh

The contract maps 204 existing fixed UI keys: all domestic-tracking strings plus
explicitly matched shared labels used by AppStrings, UiLocalizations, CargoUiStrings
and the management menu. Ambiguous or platform-specific copy is not guessed.
Web-only sections have no corresponding app screen; native dialogs and operational
record values are not UI overrides. This is not an automatic source-code deployment
system. Feature or permission changes still require both client releases and shared
server verification.

The app reads the public table at startup, foreground/reconnect invalidations and
the existing 30-second foreground poll. The web reads at startup, focus/visibility
return and every 30 seconds. Background text polling skips the text editor so its
saved compare-and-swap snapshot and unsaved translations remain stable. Public
labels update in place. App active tabs and delivery editors rebuild the same State
objects, retaining controllers and entered values. Other labels read the same cached
snapshot when their screen rebuilds or reopens. No business records are reloaded by
a text-only notification.

Both clients page through overrides. App reads are coalesced, applied atomically,
and retain the last successful snapshot on network failure. Deletions/reset restore
defaults. Only known fixed keys are accepted; placeholders and lengths are checked.
Text is rendered as text, never executable markup. Customer names, phone numbers,
waybills, route codes and Excel/document templates are not passed to this resolver.
Existing active-approved-admin-only editing and optimistic concurrency stay intact.

## Maintaining parity

Keep the identical shared-ui-text/contract.json in web and app repositories.
For app generation run python3 tool/generate_shared_ui_text.py; CI checks generated
Dart is current. Web tests compare the contract against the actual rendered registry.
When changing a shared default or adding a shared screen, update both repositories,
the contract/mappings and meaningful UI coverage. Administrator copy edits need no
new release after this bridge is installed; code/feature changes do.

## Validation

Web tests cover all three title languages, popup/menu aliases, editor save/reset and
concurrency, periodic text refresh preserving drafts, plus existing delivery logic.
App tests cover shared languages and menu isolation, aliases, paginated reads,
offline retention, reset, coalescing, and an open lookup preserving its number.
Physical phone receipt of the new OTA patch remains a device-side verification.

