Patch188 - final one-line duplicate fix

Confirmed current file contains exactly:
  final labelW = totalW * .38;
  final labelW = totalW * .46;

inside the final-total block.

The .46 line is leftover garbage from the prior adjustment patch.
This patch removes ONLY that one duplicate line.

No UI redesign.
No discount logic change.
No menu change.
No Excel change.
No SQL.
No Edge deploy.

Run:
  .\APPLY_PATCH_188.ps1
  flutter analyze
