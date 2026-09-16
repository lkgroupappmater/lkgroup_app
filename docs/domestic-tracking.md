# Laos domestic tracking

App and website call the same `domestic-tracking` Edge Function. Managers register city/province waybills with an optional existing shipment link and private photo. Each cargo can have multiple waybills. Full-number lookup returns a newest-first timeline in Laos time (UTC+7).

## Access and consistency

- A validated Supabase user and active profile are required. Admin/staff can write; partners can list/read; members can look up an exact full registered number.
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

Apply `20260916053707_laos_domestic_tracking.sql`, then deploy the Edge Function with `index.ts` and `carriers.mjs`. The function performs JWT validation using `auth.getUser`; gateway `verify_jwt=false` supports the project's current key configuration without making the handler anonymous.

Run `node --test supabase/functions/domestic-tracking/*.test.mjs` (Node 24), Flutter analyze and `flutter test test/domestic_tracking_test.dart`. Site regression tests live in the separate Sites repository.

## Public search first

The owner prefers matching registered carrier + tracking number against the public website, without carrier contracts or partner API credentials. HAL already uses the public tracking service. ANS opens the public result directly. J&T and Lao Post preserve the number in their public search URLs, but their human-verification steps prevent unattended aggregation. Browser-rendered results are not yet imported into the central timeline. Do not represent external links as automatic data synchronization.
