$ErrorActionPreference = 'Stop'
$files = @('lib/screens/quotation_preview_dialog.dart','lib/screens/statement_preview_dialog.dart')
foreach ($f in $files) {
  if (!(Test-Path $f)) { throw "Missing: $f" }
  $t = [IO.File]::ReadAllText((Resolve-Path $f))
  $t = $t.Replace('int get _visibleRows => widget.boxes.length < 10 ? 10 : widget.boxes.length;', 'int get _visibleRows => widget.boxes.length < 9 ? 10 : widget.boxes.length + 1;')
  $t = $t.Replace('int get _visibleRows => _rows.length < 10 ? 10 : _rows.length;', 'int get _visibleRows => _rows.length < 9 ? 10 : _rows.length + 1;')
  # Preview: fit document width to available viewport; allow vertical scroll/zoom, keep footer buttons visible.
  $t = $t.Replace("final width =`r`n                                  (constraints.maxWidth - 16).clamp(320.0, 900.0);", "final width = (constraints.maxWidth - 8).clamp(280.0, 1800.0);")
  $t = $t.Replace("final width =`n                                  (constraints.maxWidth - 16).clamp(320.0, 900.0);", "final width = (constraints.maxWidth - 8).clamp(280.0, 1800.0);")
  $t = $t.Replace('boundaryMargin: const EdgeInsets.all(80),', 'boundaryMargin: const EdgeInsets.symmetric(horizontal: 12, vertical: 40),')
  $t = $t.Replace('padding: const EdgeInsets.all(8),', 'padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),')
  [IO.File]::WriteAllText((Resolve-Path $f), $t, (New-Object Text.UTF8Encoding($false)))
}
Write-Host 'Patch108 applied: preview width + visible footer + data rows + 1 blank row.'
