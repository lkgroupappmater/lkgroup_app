# Restore unknown / uncertain cargo visibility

Review-queue creation was coupled to receipt normalization. Preserving Excel
receipt assignments skipped that path, leaving the current two unresolved
unknown cargos outside the review queue. Web search also lacked the separate
unknown-cargo RPC surface already present in the App.

The shared migration maintains the unknown review queue directly on cargo
identity/deletion changes and backfills missing active unknown entries. It does
not edit cargo, renumber receipts, or approve pending corrections. Keeping an
item as unknown completes its current admin review but leaves it searchable;
changing its unknown identity reopens review. Confirmation or deletion removes
it from the unresolved list. Recovered recipients and locked completed reviews
retain their existing classifications.

App and Web use `list_unknown_recipient_cargo`, with no date cutoff. The list
also includes unlocked incomplete recipient data and manual uncertainty. The
existing member claim action uses the same eligibility and admin approval
workflow. Member name/phone masking follows the existing masking helpers;
anonymous access is denied. Managers retain full details. Normal owner,
company and invoice search permissions are unchanged.

The Web addition reuses existing card/form styles after normal search results,
loads independently of search filters, refreshes on visibility and every minute,
and clears cached data on logout/account change. Existing App screens already
call these RPCs; no Dart/UI change or mobile binary release is required.

Validation: 9 focused Node tests passed. Rollback-only SQL fixtures passed for
unknown/incomplete/manual/known/locked cargo, old retained unknowns, review
reopening, receipt preservation, member masking, claims, duplicate prevention,
anonymous denial, claim approval, trash/restore and recovered recipients. The
fixture transaction left zero test cargo. Live admin and customer-list RPCs now
both return Sea 2026/09 S067 and S085, with LKS XX preserved. Six recovered
recipient records retain their existing false unknown flag. Security advisor
reports authenticated SECURITY DEFINER exposure for the two intentionally
authenticated RPCs; both enforce their caller/role rules. Internal trigger
execution is not granted to authenticated or anonymous callers.

The connected browser currently has no signed-in website session. Authenticated
UI interaction has not been manually verified; DOM unit tests and actual shared
database RPCs cover the restored paths without approving real customer requests.
