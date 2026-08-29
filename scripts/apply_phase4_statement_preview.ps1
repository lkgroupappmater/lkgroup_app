$ErrorActionPreference = 'Stop'

# pubspec assets
$path = "pubspec.yaml"
$text = Get-Content -Raw -Encoding UTF8 $path
if (!$text.Contains("assets/statement_forms/")) {
  if ($text.Contains("    - assets/quotation_forms/")) {
    $text = $text.Replace(
      "    - assets/quotation_forms/",
      "    - assets/quotation_forms/`r`n    - assets/statement_forms/"
    )
  } else {
    throw "pubspec quotation asset anchor not found"
  }
}
Set-Content -Path $path -Value $text -Encoding UTF8

# cargo management: import + statement button
$path = "lib/screens/cargo_management_screen.dart"
$text = Get-Content -Raw -Encoding UTF8 $path

if (!$text.Contains("import 'statement_preview_dialog.dart';")) {
  $needle = "import 'quote_request_management_screen.dart';"
  $text = $text.Replace($needle, "$needle`r`nimport 'statement_preview_dialog.dart';")
}

if (!$text.Contains("Future<void> _showStatement()")) {
  $needle = "  Future<void> _save() async {"
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
    if (selected.any(
      (row) => '${row['receipt_number'] ?? ''}'.trim() != receipt,
    )) {
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
  if (!$text.Contains($needle)) { throw "cargo save method anchor not found" }
  $text = $text.Replace($needle, $method + $needle)
}

# 화물 관리 화면의 저장 버튼 바로 앞에 명세서 보기 버튼을 안전하게 삽입.
if (!$text.Contains("label: const Text('명세서 보기')")) {
  $needle = "label: const Text('저장'),"
  $idx = $text.IndexOf($needle)
  if ($idx -lt 0) { throw "cargo save button anchor not found" }
  $button = @'
label: const Text('저장'),
'@
  # 첫 저장 버튼 블록을 직접 건드리는 대신 저장 label 바로 뒤에 추가 UI는 위험하므로
  # 화면 하단 ListView의 결과 카드 앞에 독립 버튼을 넣는다.
  $anchor = "          if (_searched && _results.isEmpty)"
  if (!$text.Contains($anchor)) { throw "cargo results anchor not found" }
  $insert = @'
          if (_searched && _results.isNotEmpty && !_isPartner) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _selectedIds.isEmpty ? null : _showStatement,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('명세서 보기'),
              ),
            ),
            const SizedBox(height: 8),
          ],
'@
  $text = $text.Replace($anchor, $insert + $anchor)
}
Set-Content -Path $path -Value $text -Encoding UTF8

Write-Host "PHASE 4 statement preview patch complete."
