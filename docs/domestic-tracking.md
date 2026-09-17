# Laos domestic tracking

App and website call the same `domestic-tracking` Edge Function. Operators map an LK statement or a separate LK reference to one or more city/province carrier waybills, with optional private photos. Individual cargo links remain compatible. Full-number lookup returns a newest-first timeline in Laos time (UTC+7).

## Access and consistency

- A validated Supabase user and active profile are required. Admin/staff can manage all records. Partners retain operational read access and can create records and edit their own records; the server checks created_by. Members only see statement/reference mappings they own under the existing customer matching rules.
- Photos and receiver details are restricted to operational roles, linked customer ID, or matching recipient name **and** phone. Photos are private, limited to 5 MB, and served through 10-minute signed URLs. No anonymous table or storage access is granted.
- Optimistic revisions reject conflicting staff edits. Carrier refreshes merge with staff events and retain cached history on errors. Searches refresh at most once every five minutes per parcel, with 30 API operations per user per minute.
- Photos replaced by managers are retained privately for recovery. A future retention policy should define their deletion schedule.
- The system displays carrier branch locations, not live GPS. Carrier text is preserved; status labels are localized into Korean, English and Lao.

## Carrier coverage verified 2026-09-16

| Carrier | Integration |
| --- | --- |
| HAL | Public website tracking JSON endpoint verified. State 5 means destination collection pending; state 6 means customer received. No login required. |
| ANS | Public browser tracking works. Server requests to the website's GraphQL service redirect to an unrelated domain; adapter deliberately disabled. Official deep link plus stored staff events while public-page automation is unavailable in the current server runtime. No carrier API contract is a prerequisite. |
| J&T | Public search confirmed to show a slider CAPTCHA. The official link carries the complete waybill number; the user completes verification on that page. |
| Lao Post | Public search requires reCAPTCHA. The official link carries the complete tracking number; the user completes verification on that page. |
| Mixay | Registration and staff events supported; external integration planned. |

No carrier credentials, customer sessions, CAPTCHA bypass, or fabricated shipment events are used. Upstream fetches reject redirects. Only selected normalized fields are stored, not complete carrier payloads.

## Deployment and verification

Apply `20260916053707_laos_domestic_tracking.sql`, then deploy the Edge Function with `index.ts`, `carriers.mjs` and `statements.mjs`. The function performs JWT validation using `auth.getUser`; gateway `verify_jwt=false` supports the project's current key configuration without making the handler anonymous.

Run `node --test supabase/functions/domestic-tracking/*.test.mjs` (Node 24), Flutter analyze and `flutter test test/domestic_tracking_test.dart`. Site regression tests live in the separate Sites repository.

## Public search first

The owner prefers matching registered carrier + tracking number against the public website, without carrier contracts or partner API credentials. HAL already uses the public tracking service. ANS opens the public result directly. J&T and Lao Post preserve the number in their public search URLs, but their human-verification steps prevent unattended aggregation. Browser-rendered results are not yet imported into the central timeline. Do not represent external links as automatic data synchronization.
## Statement and local reference mapping (2026-09-17)

Both clients use the same two steps:
1. Choose an existing transport route, year, voyage, enter the **LK receipt/statement number** (`shipments.receipt_number`, for example `LKS 03`), and confirm. The server resolves the exact statement and displays its cargo count. Changing any field requires reconfirmation. Existing supplier `invoice_number` is not the LK receipt number.
2. Enter the **carrier waybill number** separately, confirm the carrier, choose city/province, and optionally attach a photo. Repeat registration to attach additional waybills to the same LK statement.

`LKS 03`, `LKS03`, `lks003` normalize together within the chosen route/year/voyage. Voyage `08` and `09` remain distinct. An ambiguous search requires narrower filters. Registration requires an existing statement; no statement or shipment is invented. Numeric-only receipt entry is accepted only with all transport filters and a unique match.

For ecommerce or separate local deliveries, select **Separate LK reference**, choose ecommerce/local and enter the LK management number. The carrier waybill has its own field. These are typed reference namespaces, not automatically generated ecommerce statements; future ecommerce can supply its separately managed numbers. Same reference can have multiple carrier waybills. Registration does not automatically discover shipments from other companies.

Apply `20260917063225_domestic_statement_mapping.sql` to the existing database before deploying these files. It adds only reference columns/indexes and service-only SQL helpers to existing tables. Direct statement links write both `link_*` and legacy `statement_*` fields, preserving the previous contracts. Existing cargo/standalone rows and old installed clients remain supported. No anonymous table/RPC/storage access is added.

`statement_resolve` validates registration. `statement_lookup` joins direct statement and legacy cargo links, paginates 20 records and checks customer access. Legacy box/inbound invoice lookup remains accepted in search for compatibility. `reference_lookup` uses the exact reference namespace/number and customer matching. Carrier corrections retain staff history/photos while clearing obsolete carrier events; in-flight refreshes cannot overwrite a corrected carrier. Concurrent operator edits return `RECORD_CHANGED`.

Website homepage access was changed to public on 2026-09-17 at the owner's request. LK business/member pages still require the existing LK Supabase login. This is a Sites audience change, not an auth/database permission change.

Verification: API regression tests cover receipt identity, multiple waybills, voyage isolation, customer privacy, partner ownership, legacy clients, correction races and optimistic edits. Flutter widget tests cover confirm-before-save, changed voyage, stale lookup and ecommerce mapping. Web DOM tests cover the same mapping/search contract. Actual signed-in phone/browser operation and real carrier waybill end-to-end validation require the owner's normal account and shipment; no customer production records are created for tests.
