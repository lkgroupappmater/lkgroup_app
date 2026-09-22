# Excel change review idempotency — 2026-09-22

Shared DB migration: reconcile_applied_excel_change_requests.

Existing cargo imports create review requests; they do not apply unapproved
changes. Review applies the Excel request plus only explicit administrator edits.

- Completed/equal Excel requests are archived as already_applied, with their
  original changes retained and no fabricated administrator approval.
- The pending reader compares against live cargo and returns only actual
  differences plus current editable fields, including Zone.
- Preview and upload compare the remaining differences when checking for an
  existing pending request. Partial completion does not create a second request.
- Approval uses cargo-before-request locking and reconciles equal duplicates.
- The web single editor sends only actual edits, matching batch behavior.
- The App single editor starts with proposed Excel values, shares the validated
  ApprovalDraft implementation and clears stale controllers on refresh.

Validation: verify_excel_request_idempotency.sql passed through real shared RPCs
as an authenticated admin, with fixtures/notifications rolled back. It covers
F→C, ST, partial requests, repeated preview/import, editable cargo data, both
finalizers, preserved audit records and private internal helpers.
The website admin integration suite passed all 78 tests.
Production read-only comparison of the latest approved fields for 188 active
SEA 2026 V09 shipments found no differences. All 139 ST rows and 19 explicitly
approved C rows are preserved; no pending Zone request remains for that voyage.
No real cargo values or historical approved requests were rewritten in this fix.
