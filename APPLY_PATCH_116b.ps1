$ErrorActionPreference = "Stop"

function Read-Utf8([string]$Path) { Get-Content -Raw -Encoding UTF8 $Path }
function Write-Utf8([string]$Path, [string]$Text) { Set-Content -Path $Path -Value $Text -Encoding UTF8 }

$project = (Get-Location).Path
$catalogSource = Join-Path $PSScriptRoot "lib\core\document_text_catalog.dart"
$catalogTarget = Join-Path $project "lib\core\document_text_catalog.dart"
if (([System.IO.Path]::GetFullPath($catalogSource)) -ne ([System.IO.Path]::GetFullPath($catalogTarget))) {
  Copy-Item $catalogSource $catalogTarget -Force
} else {
  Write-Host "확인: document_text_catalog.dart 이미 프로젝트 위치에 있음"
}
$batchSource = Join-Path $PSScriptRoot "lib\screens\batch_statement_pdf_dialog.dart"
$batchTarget = Join-Path $project "lib\screens\batch_statement_pdf_dialog.dart"
if (([System.IO.Path]::GetFullPath($batchSource)) -ne ([System.IO.Path]::GetFullPath($batchTarget))) {
  Copy-Item $batchSource $batchTarget -Force
} else {
  Write-Host "확인: batch_statement_pdf_dialog.dart 이미 프로젝트 위치에 있음"
}

# ---------- quotation ----------
$q = Join-Path $project "lib\screens\quotation_preview_dialog.dart"
Copy-Item $q "$q.bak_before_patch116" -Force
$src = Read-Utf8 $q
if (!$src.Contains("document_text_catalog.dart")) {
  $src = $src.Replace("import '../core/route_catalog.dart';", "import '../core/route_catalog.dart';`r`nimport '../core/document_text_catalog.dart';")
}
if (!$src.Contains("DocumentTextCatalog.quotation(routeLabel, issuedAt)")) {
  $src = $src.Replace("    final leftW = w * .70;", "    final docText = DocumentTextCatalog.quotation(routeLabel, issuedAt);`r`n    final leftW = w * .70;")
}
$src = [regex]::Replace(
  $src,
  "(?s)_text\(c,\s*RouteCatalog\.remarkFor\(routeLabel\)\.isEmpty.*?Rect\.fromLTWH\(10, sumTop \+ 38, leftW \* \.58 - 20, 112\),\s*14\);",
  "_text(c, docText.remark,`r`n        Rect.fromLTWH(10, sumTop + 38, leftW * .58 - 20, 112),`r`n        docText.remarkFontSize, maxLines: 6, lineHeight: 1.16);",
  1
)
$src = [regex]::Replace(
  $src,
  "(?s)final noteTop = payTop \+ 150;\s*_text\(\s*c,\s*'\* 운임은 USD 기준이며 표시된 기타 통화는 현재 앱 적용 환율 기준입니다\..*?center: true,\s*\);",
  "final noteTop = payTop + 150;`r`n    _text(c, '', Rect.fromLTWH(15, noteTop, w - 30, 42), 1);",
  1
)
$src = [regex]::Replace(
  $src,
  "(?s)final routeNotice = RouteCatalog\.keyFor\(routeLabel\) == 'kr_la_sea'.*?_text\(\s*c,\s*routeNotice\.isEmpty.*?Rect\.fromLTWH\(signW \+ 18, signTop \+ 6, w - signW \* 2 - 36, signH - 12\),\s*13,",
  "_text(`r`n      c,`r`n      docText.footerText,`r`n      Rect.fromLTWH(signW + 18, signTop + 6, w - signW * 2 - 36, signH - 12),`r`n      docText.footerFontSize,",
  1
)
Write-Utf8 $q $src
Write-Host "수정 완료: 가견적서 Remark/하단 안내문"

# ---------- statement ----------
$s = Join-Path $project "lib\screens\statement_preview_dialog.dart"
Copy-Item $s "$s.bak_before_patch116" -Force
$src = Read-Utf8 $s
if (!$src.Contains("document_text_catalog.dart")) {
  $src = $src.Replace("import '../core/route_catalog.dart';", "import '../core/route_catalog.dart';`r`nimport '../core/document_text_catalog.dart';")
}
if (!$src.Contains("DocumentTextCatalog.statement(routeLabel, DateTime.now())")) {
  $src = $src.Replace("    final leftW = w * .70;", "    final docText = DocumentTextCatalog.statement(routeLabel, DateTime.now());`r`n    final leftW = w * .70;")
}
$src = [regex]::Replace(
  $src,
  "(?s)_text\(c,\s*RouteCatalog\.remarkFor\(routeLabel\)\.isEmpty.*?Rect\.fromLTWH\(10, sumTop \+ 38, leftW \* \.58 - 20, 112\),\s*14\);",
  "_text(c, docText.remark,`r`n        Rect.fromLTWH(10, sumTop + 38, leftW * .58 - 20, 112),`r`n        docText.remarkFontSize, maxLines: 6, lineHeight: 1.16);",
  1
)
$src = [regex]::Replace(
  $src,
  "(?s)final noteTop = payTop \+ 150;\s*_text\(\s*c,\s*'\* 입·출고지를 떠나기 전 고객님 운임 물품 및 개수 확인 부탁드립니다\..*?center: true,\s*\);",
  "final noteTop = payTop + 150;`r`n    _text(c, '', Rect.fromLTWH(15, noteTop, w - 30, 42), 1);",
  1
)
$src = [regex]::Replace(
  $src,
  "(?s)final routeNotice = RouteCatalog\.keyFor\(routeLabel\) == 'kr_la_sea'.*?_text\(\s*c,\s*routeNotice\.isEmpty.*?Rect\.fromLTWH\(signW \+ 18, signTop \+ 6, w - signW \* 2 - 36, signH - 12\),\s*13,",
  "_text(`r`n      c,`r`n      docText.footerText,`r`n      Rect.fromLTWH(signW + 18, signTop + 6, w - signW * 2 - 36, signH - 12),`r`n      docText.footerFontSize,",
  1
)

if (!$src.Contains("class StatementRenderRequest")) {
$renderer = @'

class StatementRenderRequest {
  const StatementRenderRequest({
    required this.routeLabel,
    required this.year,
    required this.voyage,
    required this.receiptNumber,
  });

  final String routeLabel;
  final int year;
  final String voyage;
  final String receiptNumber;
}

class StatementDocumentRenderer {
  StatementDocumentRenderer._();

  static Future<ui.Image> _asset(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  static Future<Uint8List> _renderOne(
    StatementRenderRequest request,
    List<ui.Image> assets,
  ) async {
    final rows = await StatementService.instance.rowsForReceipt(
      route: request.routeLabel,
      year: request.year,
      voyage: request.voyage,
      receiptNumber: request.receiptNumber,
    );
    if (rows.isEmpty) {
      throw StateError('${request.receiptNumber}: 명세서 데이터가 없습니다.');
    }
    final freight = await FreightService.instance.calculate(rows);
    final arrival = await StatementService.instance.arrivalDate(
      route: request.routeLabel,
      year: request.year,
      voyage: request.voyage,
    );
    final visibleRows = rows.length + 1 < 10 ? 10 : rows.length + 1;
    final docHeight = 1120.0 + (visibleRows - 10) * 32;
    const docWidth = 1800.0;
    const scale = 1.35;

    final painter = _DigitalStatementPainter(
      routeLabel: request.routeLabel,
      rows: rows,
      freight: freight,
      receiptNumber: request.receiptNumber,
      arrivalDate: arrival,
      logo: assets[0],
      qrUsd: assets[1],
      qrKip: assets[2],
      qrThb: assets[3],
      stamp: assets[4],
      bankStrip: assets[5],
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    painter.paint(canvas, Size(docWidth, docHeight));
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (docWidth * scale).round(),
      (docHeight * scale).round(),
    );
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw StateError('명세서 PNG 생성 실패');
    return data.buffer.asUint8List();
  }

  static Future<Uint8List> renderBatchPdf(
    List<StatementRenderRequest> requests,
  ) async {
    if (requests.isEmpty) throw ArgumentError('출력할 명세서가 없습니다.');
    final assets = await Future.wait<ui.Image>([
      _asset('assets/images/company_logo_transparent.png'),
      _asset('assets/images/payment_qr_usd.png'),
      _asset('assets/images/payment_qr_kip.png'),
      _asset('assets/images/payment_qr_thb.png'),
      _asset('assets/images/company_stamp.png'),
      _asset('assets/images/bank_accounts_strip.png'),
    ]);
    try {
      final pages = <Uint8List>[];
      for (final request in requests) {
        pages.add(await _renderOne(request, assets));
      }
      return DocumentPdfExport.batchStatements(pages);
    } finally {
      for (final image in assets) {
        image.dispose();
      }
    }
  }
}
'@
  $src += $renderer
}
Write-Utf8 $s $src
Write-Host "수정 완료: 명세서 Remark/하단 안내문 + 일괄 PDF 렌더러"

# ---------- PDF exporter ----------
$pdf = Join-Path $project "lib\services\document_pdf_export.dart"
Copy-Item $pdf "$pdf.bak_before_patch116" -Force
$src = Read-Utf8 $pdf
if (!$src.Contains("batchStatements(")) {
$method = @'

  static Future<Uint8List> batchStatements(
    List<Uint8List> pngPages,
  ) async {
    final pdf = pw.Document();
    for (final bytes in pngPages) {
      final image = pw.MemoryImage(bytes);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
          build: (_) => pw.Column(
            children: [
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 10),
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              ),
              pw.Container(
                height: 24,
                alignment: pw.Alignment.center,
                child: pw.Container(height: .6, color: PdfColors.grey600),
              ),
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 10),
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return pdf.save();
  }
'@
  $pos = $src.LastIndexOf("}")
  if ($pos -lt 0) { throw "document_pdf_export.dart 종료 위치를 찾지 못했습니다." }
  $src = $src.Substring(0, $pos) + $method + "`r`n}" + $src.Substring($pos + 1)
}
Write-Utf8 $pdf $src
Write-Host "수정 완료: 체크 명세서 통합 PDF"

# ---------- cargo management ----------
$c = Join-Path $project "lib\screens\cargo_management_screen.dart"
Copy-Item $c "$c.bak_before_patch116" -Force
$src = Read-Utf8 $c
if (!$src.Contains("batch_statement_pdf_dialog.dart")) {
  $src = $src.Replace("import 'statement_preview_dialog.dart';", "import 'statement_preview_dialog.dart';`r`nimport 'batch_statement_pdf_dialog.dart';")
}
if (!$src.Contains("Future<void> _showBatchStatementPdf")) {
$method = @'

  Future<void> _showBatchStatementPdf({
    List<Map<String, dynamic>>? scopeRows,
  }) async {
    if (_isPartner) {
      _message('협력/파트너 계정은 명세서를 출력할 수 없습니다.');
      return;
    }
    if (_selectedIds.isEmpty) {
      _message('PDF로 저장할 명세서의 화물을 먼저 체크해 주세요.');
      return;
    }
    final source = scopeRows ?? _results;
    final selected = source
        .where((row) => _selectedIds.contains('${row['id']}'))
        .toList(growable: false);
    if (selected.isEmpty) {
      _message('이 항차에서 체크된 화물이 없습니다.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => BatchStatementPdfDialog(selectedRows: selected),
    );
  }

'@
  $src = $src.Replace("  Future<void> _save() async {", $method + "  Future<void> _save() async {")
}
$src = [regex]::Replace(
  $src,
  "onPressed: _busy \? null : _showStatement,\s*icon: const Icon\(Icons\.receipt_long_outlined\),\s*label: const Text\('명세서 보기'\),",
  "onPressed: _busy ? null : _showBatchStatementPdf,`r`n                  icon: const Icon(Icons.picture_as_pdf_outlined),`r`n                  label: const Text('체크 명세서 PDF'),",
  1
)
$src = $src.Replace(
  "tooltip: '명세서 보기',`r`n                      onPressed: _busy ? null : () => _showGroupStatement(rows),",
  "tooltip: '체크 명세서 PDF 저장',`r`n                      onPressed: _busy ? null : () => _showBatchStatementPdf(scopeRows: rows),"
)
$src = $src.Replace(
  "tooltip: '명세서 보기',`n                      onPressed: _busy ? null : () => _showGroupStatement(rows),",
  "tooltip: '체크 명세서 PDF 저장',`n                      onPressed: _busy ? null : () => _showBatchStatementPdf(scopeRows: rows),"
)
Write-Utf8 $c $src
Write-Host "수정 완료: 화물관리 체크 영수증 전체 PDF 저장 팝업"

Write-Host ""
Write-Host "Patch116b 적용 완료"
Write-Host "- 실제 업로드 Excel 기준 운송경로별 Remark/하단문구"
Write-Host "- 기한은 실행 시점 년/월 말 자동 표기"
Write-Host "- 체크된 고유 영수번호 명세서를 하나의 PDF로 저장"
Write-Host "- SQL 실행 없음"
