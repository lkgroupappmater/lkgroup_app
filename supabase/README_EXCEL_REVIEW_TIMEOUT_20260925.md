# Excel bulk review timeout fix

The reported 282-request sea voyage 09 approval timed out after 60 seconds.
The RPC recalculated automatic Remark/discount/delivery for every cargo,
then the identity UPDATE trigger repeated the calculation even though no
customer identities had changed.

`20260925110628_optimize_atomic_excel_review.sql` applies ordinary fields as
one set and identity fields only where name or phone actually changed. The
existing identity and automatic-Remark triggers remain authoritative.
Reconciliation and notifications also use set operations. Authorization,
atomicity, locks, stale-data checks, receipt-charge links and the API timeout
are unchanged. App and Website both use this shared RPC; no client release
or replacement Excel template is required.

The actual 282-request batch completed in 168.769 ms in a rollback-only
regression. All requested values applied. Cargo, requests, notifications and
data revisions were restored by the test; real pending approvals were not
submitted. Separate fixtures cover identity edits, modified approval, locked
cargo, rejection, removal/restoration, receipt/box swaps, linked costs and
discounts, and member denial.
