$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot

function Read-Utf8($path) { Get-Content $path -Raw -Encoding UTF8 }
function Write-Utf8($path, $text) { Set-Content $path $text -Encoding UTF8 }

# 1. pdf dependency
$pub = Join-Path $project 'pubspec.yaml'
$t = Read-Utf8 $pub
if ($t -notmatch '(?m)^\s*pdf:\s*\^') {
  $t = $t -replace "(?m)^(\s*intl:\s*\^[^\r\n]+)", "`$1`r`n  pdf: ^3.11.3"
  Write-Utf8 $pub $t
}

# 2. Statement dialog: add PDF export helper and second save button.
$sp = Join-Path $project 'lib/screens/statement_preview_dialog.dart'
$s = Read-Utf8 $sp

if ($s -notmatch "document_pdf_export.dart") {
  $s = $s -replace "import '../services/statement_service.dart';", "import '../services/statement_service.dart';`r`nimport '../services/document_pdf_export.dart';"
}

if ($s -notmatch "Future<void> _savePdf\(") {
  $anchor = "  @override`r`n  Widget build(BuildContext context) {"
  if (-not $s.Contains($anchor)) {
    $anchor = "  @override`n  Widget build(BuildContext context) {"
  }
  $method = @'
  Future<void> _savePdf() async {
    final image = _template;
    if (image == null || _freight == null) return;
    setState(() => _saving = true);
    try {
      final png = await _renderPng();
      final logical = _logicalSize(image);
      final pdf = await DocumentPdfExport.statementTwoUp(
        png,
        sourceWidth: logical.width,
        sourceHeight: logical.height,
      );
      final prefix = RouteCatalog.filePrefixFor(widget.routeLabel);
      final safeReceipt = widget.receiptNumber.replaceAll(
        RegExp(r'[^A-Za-z0-9_-]+'),
        '_',
      );
      final saved = await FilePicker.saveFile(
        dialogTitle: '명세서 출력용 PDF 저장 위치 선택',
        fileName:
            '${prefix.isEmpty ? 'STATEMENT' : prefix}_STATEMENT_$safeReceipt.pdf',
        bytes: pdf,
        mimeType: 'application/pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved == null ? 'PDF 저장을 취소했습니다.' : '출력용 PDF를 저장했습니다.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('출력용 PDF 저장 실패: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

'@
  $s = $s.Replace($anchor, $method + $anchor)
}

# Replace bottom action row with 3 buttons.
$pattern = "(?s)Padding\(\s*padding: const EdgeInsets\.all\(8\),\s*child: Row\(\s*children: \[\s*Expanded\(\s*child: OutlinedButton\(.*?label: const Text\('고화질 이미지 저장'\),\s*\),\s*\),\s*\],\s*\),\s*\),"
$replacement = @'
Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('닫기'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: image == null || _freight == null || _saving
                          ? null
                          : _save,
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('이미지 저장'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: image == null || _freight == null || _saving
                          ? null
                          : _savePdf,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('출력용 PDF'),
                    ),
                  ),
                ],
              ),
            ),
'@
$s2 = [regex]::Replace($s, $pattern, $replacement, 1)
if ($s2 -eq $s) {
  Write-Warning '명세서 하단 버튼 자동 교체를 찾지 못했습니다. PDF 메서드는 추가되었습니다.'
} else {
  $s = $s2
}
Write-Utf8 $sp $s

# 3. Quotation dialog: add PDF export + split image/PDF buttons.
$qp = Join-Path $project 'lib/screens/quotation_preview_dialog.dart'
$q = Read-Utf8 $qp
if ($q -notmatch "document_pdf_export.dart") {
  $q = $q -replace "import '../services/quote_freight_calculator.dart';", "import '../services/quote_freight_calculator.dart';`r`nimport '../services/document_pdf_export.dart';"
}

if ($q -notmatch "Future<void> _savePdf\(") {
  $anchor = "  @override`r`n  Widget build(BuildContext context) {"
  if (-not $q.Contains($anchor)) {
    $anchor = "  @override`n  Widget build(BuildContext context) {"
  }
  $method = @'
  Future<void> _savePdf() async {
    setState(() => _saving = true);
    try {
      final png = await _renderHighResolutionPng();
      final pdf = await DocumentPdfExport.quotation(png);
      final prefix = RouteCatalog.filePrefixFor(widget.routeLabel);
      final fileName =
          '${prefix.isEmpty ? 'QUOTATION' : prefix}_QUOTATION_${_issuedAt.year}${_two(_issuedAt.month)}${_two(_issuedAt.day)}.pdf';

      final uri = await FilePicker.saveFile(
        dialogTitle: '견적서 출력용 PDF 저장 위치 선택',
        fileName: fileName,
        bytes: pdf,
        mimeType: 'application/pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uri == null ? 'PDF 저장을 취소했습니다.' : '출력용 견적서 PDF를 저장했습니다.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('견적서 PDF 저장 실패: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

'@
  $q = $q.Replace($anchor, $method + $anchor)
}

$patternQ = "(?s)Padding\(\s*padding: const EdgeInsets\.all\(8\),\s*child: Row\(\s*children: \[\s*Expanded\(\s*child: OutlinedButton\(.*?label: const Text\('고화질 이미지 저장'\),\s*\),\s*\),\s*\],\s*\),\s*\),"
$replacementQ = @'
Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('닫기'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: image == null || _saving ? null : _savePng,
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('이미지 저장'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: image == null || _saving ? null : _savePdf,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('출력용 PDF'),
                    ),
                  ),
                ],
              ),
            ),
'@
$q2 = [regex]::Replace($q, $patternQ, $replacementQ, 1)
if ($q2 -eq $q) {
  Write-Warning '견적서 하단 버튼 자동 교체를 찾지 못했습니다. PDF 메서드는 추가되었습니다.'
} else {
  $q = $q2
}
Write-Utf8 $qp $q

Write-Host ''
Write-Host 'Patch101 적용 완료' -ForegroundColor Green
Write-Host '- 견적서: 이미지 저장 / 출력용 PDF 분리'
Write-Host '- 명세서: 이미지 저장 / 출력용 PDF 분리'
Write-Host '- 명세서 PDF: 일반 크기 A4 상하 2부'
Write-Host '- 너무 긴 명세서: 찌그러뜨리지 않고 고객용/보관용을 각각 A4 페이지로 분리'
Write-Host '- PDF 외곽 여백 8pt로 최소화'
Write-Host ''
Write-Host '다음 실행: flutter pub get'
Write-Host '           flutter analyze'
Write-Host '           flutter run'
