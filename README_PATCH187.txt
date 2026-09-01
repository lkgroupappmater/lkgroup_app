Patch187 - repair the statement variable damage from Patch186

What happened:
Patch186 collided with TWO different width variables in the same method:
- adjustment area: width 46%
- final total area: width 38%

This repair normalizes them safely:
- adjustment area -> adjustmentColumnLabelW = totalW * .46
- final total area -> labelW = totalW * .38

It repairs only statement_preview_dialog.dart and verifies both sections.

NO menu change.
NO discount logic change.
NO Excel change.
NO SQL.
NO Edge deploy.
NO V00 upload.
NO recalculation.

After:
  .\APPLY_PATCH_187.ps1
  flutter analyze
