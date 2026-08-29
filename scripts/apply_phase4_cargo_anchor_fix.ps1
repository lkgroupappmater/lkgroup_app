$ErrorActionPreference = 'Stop'

$path = "lib/screens/cargo_management_screen.dart"
if (!(Test-Path $path)) { throw "파일을 찾을 수 없습니다: $path" }
$text = Get-Content -Raw -Encoding UTF8 $path

if (!$text.Contains("import 'statement_preview_dialog.dart';")) {
  $needle = "import 'quote_request_management_screen.dart';"
  if (!$text.Contains($needle)) { throw "import anchor not found" }
  $text = $text.Replace($needle, "$needle`r`nimport 'statement_preview_dialog.dart';")
}

if (!$text.Contains("Future<void> _showStatement()")) {
  $needle = "  Future<void> _save() async {"
  if (!$text.Contains($needle)) { throw "_save method anchor not found" }
  $method = @'
  Future<void> _showStatement() async {
    if (_isPartner) {
      _message('협력/파트너 계정은 명세서를 조회할 수 없습니다.');
      return;
    }
    if (_selectedIds.isEmpty) {
      _message('명세서를 확인할 화물을 선택해 주세요.');
      return;
    }

    final selected = _results
        .where((row) => _selectedIds.contains('${row['id']}'))
        .toList(growable: false);
    if (selected.isEmpty) return;

    final receipt = '${selected.first['receipt_number'] ?? ''}'.trim();
    if (receipt.isEmpty) {
      _message('선택한 화물에 영수번호가 없습니다.');
      return;
    }
    if (selected.any((row) =>
        '${row['receipt_number'] ?? ''}'.trim() != receipt)) {
      _message('명세서는 같은 영수번호(고객)의 화물끼리 선택해 주세요.');
      return;
    }

    final route = '${selected.first['route'] ?? ''}';
    final year = (selected.first['shipment_year'] as num?)?.toInt();
    final voyage = '${selected.first['voyage'] ?? ''}';
    if (route.isEmpty || year == null || voyage.isEmpty) {
      _message('명세서의 운송경로/년도/항차 정보를 확인할 수 없습니다.');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => StatementPreviewDialog(
        routeLabel: route,
        year: year,
        voyage: voyage,
        receiptNumber: receipt,
      ),
    );
  }

'@
  $text = $text.Replace($needle, $method + $needle)
}

# 실제 최신 cargo_management_screen 구조:
# 선택 화물 수정 영역의 ElevatedButton label은
# '화물 정보 저장' / '화물 정보 수정 요청' 이다.
# 그 버튼 다음에 명세서 보기 버튼을 삽입한다.
if (!$text.Contains("label: const Text('명세서 보기')")) {
  $needle = @'
              ElevatedButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save),
                label: Text(_canSaveDirectly ? '화물 정보 저장' : '화물 정보 수정 요청'),
              ),
'@
  if (!$text.Contains($needle)) {
    # CRLF/LF 차이를 피한 regex fallback
    $pattern = "(?ms)(\s+ElevatedButton\.icon\(\s*onPressed: _busy \? null : _save,\s*icon: const Icon\(Icons\.save\),\s*label: Text\(_canSaveDirectly \? '화물 정보 저장' : '화물 정보 수정 요청'\),\s*\),)"
    $m = [regex]::Match($text, $pattern)
    if (!$m.Success) { throw "actual cargo save button block anchor not found" }
    $insert = $m.Groups[1].Value + @'

              const SizedBox(height: 8),
              if (!_isPartner)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _showStatement,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('명세서 보기'),
                ),
'@
    $text = $text.Substring(0,$m.Index) + $insert + $text.Substring($m.Index+$m.Length)
  } else {
    $replacement = $needle + @'
              const SizedBox(height: 8),
              if (!_isPartner)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _showStatement,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('명세서 보기'),
                ),
'@
    $text = $text.Replace($needle, $replacement)
  }
}

Set-Content -Path $path -Value $text -Encoding UTF8
Write-Host "PHASE 4 cargo anchor fix complete."
Write-Host "Now run: flutter analyze"
