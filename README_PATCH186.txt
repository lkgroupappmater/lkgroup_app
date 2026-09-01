Patch186 - one-bug hotfix only

Purpose:
Fix duplicate variable definition:
  The name 'labelW' is already defined
  statement_preview_dialog.dart around line 834

This patch changes ONLY the adjustment-area local variable:
  labelW -> adjustmentLabelW

It also changes only the three matching adjustment-row usages in the same block.
No other UI, logic, freight, discount, Excel, SQL, or menu code is changed.

After applying:
  flutter analyze

No SQL.
No Edge deploy.
No V00 reupload.
No recalculation.
