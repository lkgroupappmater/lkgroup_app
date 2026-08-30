$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot

function Read-Utf8($path) { Get-Content $path -Raw -Encoding UTF8 }
function Write-Utf8($path,$text) { Set-Content $path $text -Encoding UTF8 }

# ============================================================
# 1. 견적서: Preview와 고화질 저장을 같은 문서 crop 기준으로 통일
# ============================================================
$qPath = Join-Path $project 'lib/screens/quotation_preview_dialog.dart'
$q = Read-Utf8 $qPath

$qLogicalStart = $q.IndexOf("  Size _logicalSize(ui.Image image) {")
$qPreviewStart = $q.IndexOf("  Widget _preview(ui.Image image) {", $qLogicalStart)
$qRenderStart = $q.IndexOf("  Future<Uint8List> _renderHighResolutionPng() async {", $qPreviewStart)
$qTwoStart = $q.IndexOf("  String _two(int v)", $qRenderStart)
if ($qLogicalStart -lt 0 -or $qPreviewStart -lt 0 -or $qRenderStart -lt 0 -or $qTwoStart -lt 0) {
  throw 'quotation preview/render markers not found'
}

$qLogical = @'
  Size _logicalSize(ui.Image image) {
    final extra = (_detailRows - _config.baseRows) * _config.rowHeight;
    return Size(image.width.toDouble(), image.height.toDouble() + extra);
  }

  Rect _documentRect(ui.Image image) {
    final logical = _logicalSize(image);
    // 기존 Excel 연결 그림의 바깥쪽 캡처 여백만 제거합니다.
    // 문서 내부 셀/QR/도장/Remark 영역은 건드리지 않습니다.
    final x = image.width * .0105;
    final y = image.height * .0157;
    return Rect.fromLTRB(x, y, logical.width - x, logical.height - y);
  }

'@

$qPreview = @'
  Widget _preview(ui.Image image) {
    final logical = _logicalSize(image);
    final doc = _documentRect(image);
    final screenWidth = MediaQuery.sizeOf(context).width - 28;
    final previewWidth = screenWidth.clamp(320.0, 760.0);
    final previewHeight = previewWidth * doc.height / doc.width;

    return SizedBox(
      width: previewWidth,
      height: previewHeight,
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: doc.width,
          height: doc.height,
          child: ClipRect(
            child: Transform.translate(
              offset: Offset(-doc.left, -doc.top),
              child: SizedBox(
                width: logical.width,
                height: logical.height,
                child: CustomPaint(
                  painter: _QuotationFormPainter(
                    routeLabel: widget.routeLabel,
                    template: image,
                    boxes: widget.boxes,
                    result: widget.result,
                    rates: widget.rates,
                    issuedAt: _issuedAt,
                    config: _config,
                    detailRows: _detailRows,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

'@

$qRender = @'
  Future<Uint8List> _renderHighResolutionPng() async {
    final image = _templateImage;
    if (image == null) throw StateError('견적서 원본 폼을 불러오지 못했습니다.');

    final logical = _logicalSize(image);
    final doc = _documentRect(image);
    const exportScale = 1.75;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(exportScale, exportScale)
      ..translate(-doc.left, -doc.top);

    _QuotationFormPainter(
      routeLabel: widget.routeLabel,
      template: image,
      boxes: widget.boxes,
      result: widget.result,
      rates: widget.rates,
      issuedAt: _issuedAt,
      config: _config,
      detailRows: _detailRows,
    ).paint(canvas, logical);

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(
      (doc.width * exportScale).round(),
      (doc.height * exportScale).round(),
    );
    picture.dispose();

    final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    if (byteData == null) throw StateError('PNG 변환에 실패했습니다.');
    return byteData.buffer.asUint8List();
  }

'@

$q = $q.Substring(0,$qLogicalStart) + $qLogical + $qPreview + $qRender + $q.Substring($qTwoStart)
Write-Utf8 $qPath $q

# ============================================================
# 2. 명세서: 실제 문서 높이/crop 좌표 정상화 + Preview/저장 동일 기준
# ============================================================
$sPath = Join-Path $project 'lib/screens/statement_preview_dialog.dart'
$s = Read-Utf8 $sPath

$sLogicalStart = $s.IndexOf("  Size _logicalSize(ui.Image image) {")
$sPainterStart = $s.IndexOf("  _StatementPainter _painter(ui.Image image)", $sLogicalStart)
if ($sLogicalStart -lt 0 -or $sPainterStart -lt 0) {
  throw 'statement logical/painter markers not found'
}

$sLogical = @'
  Size _logicalSize(ui.Image image) {
    final visibleHeight = image.height * (1 - _cropRatio());
    final rowHeight = visibleHeight * .028;
    final extra = (_detailRows - _baseRows) * rowHeight;
    return Size(image.width.toDouble(), visibleHeight + extra);
  }

  Rect _documentRect(ui.Image image) {
    final logical = _logicalSize(image);
    // statement_forms는 좌우에 약 70px의 Excel 연결그림 캡처 여백이 있습니다.
    // 위쪽의 큰 공백은 sourceTop crop에서 제거하고, 저장 시 좌우 캡처 여백도 제거합니다.
    final x = image.width * .0470;
    return Rect.fromLTRB(x, 0, logical.width - x, logical.height);
  }

'@
$s = $s.Substring(0,$sLogicalStart) + $sLogical + $s.Substring($sPainterStart)

# renderPng 전체 교체
$sRenderStart = $s.IndexOf("  Future<Uint8List> _renderPng() async {")
$sSaveStart = $s.IndexOf("  Future<void> _save() async {", $sRenderStart)
if ($sRenderStart -lt 0 -or $sSaveStart -lt 0) { throw 'statement render markers not found' }

$sRender = @'
  Future<Uint8List> _renderPng() async {
    final image = _template;
    if (image == null || _freight == null) {
      throw StateError('명세서를 아직 불러오지 못했습니다.');
    }
    final logical = _logicalSize(image);
    final doc = _documentRect(image);
    const scale = 1.75;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale, scale)
      ..translate(-doc.left, -doc.top);

    _painter(image).paint(canvas, logical);

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(
      (doc.width * scale).round(),
      (doc.height * scale).round(),
    );
    picture.dispose();
    final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    if (bytes == null) throw StateError('PNG 변환에 실패했습니다.');
    return bytes.buffer.asUint8List();
  }

'@
$s = $s.Substring(0,$sRenderStart) + $sRender + $s.Substring($sSaveStart)

# Preview LayoutBuilder 부분을 문서 crop 기준으로 교체
$oldPreview = @'
                                builder: (context, constraints) {
                                  final logical = _logicalSize(image);
                                  final width =
                                      constraints.maxWidth.clamp(320.0, 760.0);
                                  return SizedBox(
                                    width: width,
                                    height: width *
                                        logical.height /
                                        logical.width,
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      alignment: Alignment.topCenter,
                                      child: SizedBox(
                                        width: logical.width,
                                        height: logical.height,
                                        child: CustomPaint(
                                          painter: _painter(image),
                                        ),
                                      ),
                                    ),
                                  );
                                },
'@
$newPreview = @'
                                builder: (context, constraints) {
                                  final logical = _logicalSize(image);
                                  final doc = _documentRect(image);
                                  final width =
                                      constraints.maxWidth.clamp(320.0, 760.0);
                                  return SizedBox(
                                    width: width,
                                    height: width * doc.height / doc.width,
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      alignment: Alignment.topCenter,
                                      child: SizedBox(
                                        width: doc.width,
                                        height: doc.height,
                                        child: ClipRect(
                                          child: Transform.translate(
                                            offset: Offset(-doc.left, -doc.top),
                                            child: SizedBox(
                                              width: logical.width,
                                              height: logical.height,
                                              child: CustomPaint(
                                                painter: _painter(image),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
'@
if (-not $s.Contains($oldPreview)) { throw 'statement preview LayoutBuilder pattern not found' }
$s = $s.Replace($oldPreview,$newPreview)

# 추가행이 있을 때 상단 source rect도 sourceTop을 반영해야 함
$s = $s.Replace(
"        Rect.fromLTWH(0, 0, w, bodyBottom),`r`n        Rect.fromLTWH(0, 0, w, bodyBottom),",
"        Rect.fromLTWH(0, sourceTop, w, bodyBottom),`r`n        Rect.fromLTWH(0, 0, w, bodyBottom),"
)
$s = $s.Replace(
"        Rect.fromLTWH(0, 0, w, bodyBottom),`n        Rect.fromLTWH(0, 0, w, bodyBottom),",
"        Rect.fromLTWH(0, sourceTop, w, bodyBottom),`n        Rect.fromLTWH(0, 0, w, bodyBottom),"
)
Write-Utf8 $sPath $s

# ============================================================
# 3. 화물 관리 결과 헤더: 전체 선택 + 전체 그룹 명세서 보기
# ============================================================
$cPath = Join-Path $project 'lib/screens/cargo_management_screen.dart'
$c = Read-Utf8 $cPath

$helperMarker = "  List<MapEntry<String, List<Map<String, dynamic>>>> _managementGroups() {"
if (-not $c.Contains($helperMarker)) { throw 'management groups marker not found' }

$overallHelpers = @'
  bool get _allSearchResultsSelected {
    if (_results.isEmpty) return false;
    return _selectedIds.containsAll(_results.map((r) => '${r['id']}'));
  }

  void _toggleAllSearchResults() {
    final ids = _results.map((r) => '${r['id']}').toSet();
    setState(() {
      if (ids.isNotEmpty && _selectedIds.containsAll(ids)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  Future<void> _showAllSearchResultStatements() async {
    if (_results.isEmpty || _isPartner) return;
    final groups = _managementGroups();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('검색 결과 명세서 (${_results.length}건)'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: groups.map((entry) {
              final rows = entry.value;
              final first = rows.first;
              final receiptCount = rows
                  .map((r) => '${r['receipt_number'] ?? ''}'.trim())
                  .where((v) => v.isNotEmpty)
                  .toSet()
                  .length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await _showGroupStatement(rows);
                  },
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text(
                    '${first['route']} · ${first['shipment_year']}년도 · '
                    '${_voyageLabel(first['voyage'])} ($receiptCount건)',
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

'@
if (-not $c.Contains("bool get _allSearchResultsSelected")) {
  $c = $c.Replace($helperMarker, $overallHelpers + $helperMarker)
}

$oldHeader = @'
              Text(
                '화물 정보 (${_results.length}건)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
'@
$newHeader = @'
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '화물 정보 (${_results.length}건)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  if (_isManager) ...[
                    Checkbox(
                      value: _allSearchResultsSelected,
                      onChanged: _results.isEmpty
                          ? null
                          : (_) => _toggleAllSearchResults(),
                      visualDensity: VisualDensity.compact,
                    ),
                    const Text(
                      '전체',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                  if (!_isPartner)
                    TextButton.icon(
                      onPressed: _results.isEmpty
                          ? null
                          : _showAllSearchResultStatements,
                      icon: const Icon(Icons.receipt_long_outlined, size: 17),
                      label: const Text('명세서 보기'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                    ),
                ],
              ),
'@
if (-not $c.Contains($oldHeader)) { throw 'cargo result header pattern not found' }
$c = $c.Replace($oldHeader,$newHeader)
Write-Utf8 $cPath $c

Write-Host ''
Write-Host 'Patch098 적용 완료' -ForegroundColor Green
Write-Host '- 견적서 preview/save 동일 문서 crop 기준'
Write-Host '- 명세서 sourceTop/실제 높이/추가행 crop 정상화'
Write-Host '- 고화질 저장 파일 외곽 캡처 여백 제거'
Write-Host '- 화물 정보 헤더 전체선택 + 명세서 보기'
Write-Host '- 삭제 대기 검색 제외는 SQL063 실행 후 적용'
Write-Host ''
Write-Host '다음: SQL063 실행 -> flutter analyze -> flutter run'
