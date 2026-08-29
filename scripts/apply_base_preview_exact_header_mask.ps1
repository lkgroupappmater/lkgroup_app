$ErrorActionPreference = 'Stop'

$p='lib/screens/additional_feature_development_screen.dart'
$t=Get-Content -Raw -Encoding UTF8 $p

$start=$t.IndexOf('  Widget _basePreview() {')
$end=$t.IndexOf('  Widget _templateOverrideEditor() {',$start)
if($start -lt 0 -or $end -lt 0){
  throw '_basePreview block not found'
}

$block=@'
  Widget _basePreview() {
    final routeKey = (_isCreate || _isDraft)
        ? _baseRouteKey
        : '${widget.route?['route_key'] ?? ''}';

    if (routeKey == null || routeKey.isEmpty) {
      return const SizedBox.shrink();
    }

    final formKey = RouteCatalog.formRouteKeyFor(routeKey);
    final documentTitle = _documentTitleController.text.trim();
    final receiptPrefix = _receiptPrefixController.text.trim();
    final remark = _remarkController.text.trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '명세서 BASE 전체 미리보기',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            AspectRatio(
              // statement_forms PNG 실제 문서 영역:
              // 1488px × 약 761px (y≈671~1432)
              aspectRatio: 1488 / 761,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/statement_forms/$formKey.png',
                          fit: BoxFit.cover,
                          alignment: Alignment.bottomCenter,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                '선택한 BASE의 앱 미리보기 이미지를 찾지 못했습니다.',
                              ),
                            ),
                          ),
                        ),

                        // 선택 BASE에 이미 들어 있던 제목/이전 overlay가 다시 보이지 않도록
                        // 제목 영역 전체를 한 번 깨끗하게 지운 뒤 현재 document_title만 그린다.
                        Positioned(
                          left: constraints.maxWidth * .155,
                          right: constraints.maxWidth * .165,
                          top: 0,
                          height: constraints.maxHeight * .155,
                          child: Container(
                            color: Colors.white,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                documentTitle.isEmpty
                                    ? '운송 경로 타이틀 xxth 거래 명세서'
                                    : '$documentTitle xxth 거래 명세서',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // 우측 번호칸은 제목 마스크와 별도로 현재 Prefix만 표시.
                        Positioned(
                          right: 0,
                          top: 0,
                          width: constraints.maxWidth * .165,
                          height: constraints.maxHeight * .155,
                          child: Container(
                            color: const Color(0xFFE6F2FB),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                receiptPrefix,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),

                        if (remark.isNotEmpty)
                          Positioned(
                            left: constraints.maxWidth * .055,
                            right: constraints.maxWidth * .245,
                            top: constraints.maxHeight * .395,
                            height: constraints.maxHeight * .13,
                            child: Container(
                              color: Colors.white,
                              alignment: Alignment.centerLeft,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Remark : $remark',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

'@

$t=$t.Substring(0,$start)+$block+$t.Substring($end)
Set-Content -Path $p -Value $t -Encoding UTF8

Write-Host ''
Write-Host 'Patch104 완료'
Write-Host '- BASE 미리보기 실제 문서 crop 고정'
Write-Host '- 기존/중복 타이틀 영역 전체 마스크'
Write-Host '- 현재 document_title만 1회 표시'
Write-Host '- 영수번호 영역 별도 정렬'
Write-Host 'flutter analyze 실행하세요.'
