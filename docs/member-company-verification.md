# Verified member company access — 2026-09-28

Company discovery previously returned masked records without receipt numbers or freight inputs. Approved company owners now receive ordinary complete shipment rows through the same database rules used by both clients.

- New or changed member name, phone or company queues an immutable approval snapshot. Removing the company or changing the snapshot immediately invalidates earlier authorization.
- Only an active approved general administrator can approve, reject or revoke. Members cannot write approval state. Company aliases split on explicit separators and compare exactly after case/whitespace normalization; no fuzzy matching.
- Customer and member management expose the review queue, matching cargo identities, phone numbers and customer IDs. Member account screens show the verification state.
- Search, customer-ID search, shipment RLS, statement rows, receipt extras and linked domestic-delivery photos use approved ownership. Mixed-recipient shared images remain protected.
- Existing client versions receive complete approved company rows without masked flags. Current app builds also add the review UI.

Validation: rollback-only live DB assertions passed for pending/unauthorized denial, admin approval, 295 matching cargo rows, default profile search, full shipment fields, customer ID search, statement/RLS/delivery access, stale approval rejection, profile changes, revocation and company removal. Domestic-tracking and website tests cover approved and unrelated company access and the review workflow. No tariff calculations, workbook formulas, historic receipt numbers or customer ID merges changed.
