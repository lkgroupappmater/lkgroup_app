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

            // statement_forms PNG는 원본 linked-image 캡처 특성상 위쪽에
            // 큰 흰 여백이 포함되어 있다.
            // 여기서는 파일 자체를 수정하지 않고, bottom 기준 cover crop으로
            // 실제 명세서 영역만 카드 폭에 크게 보여준다.
            AspectRatio(
              aspectRatio: 1.78,
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

                        // 문서 타이틀: 실제 명세서 상단 중앙 제목 영역에 표시.
                        if (documentTitle.isNotEmpty)
                          Positioned(
                            left: constraints.maxWidth * .18,
                            right: constraints.maxWidth * .18,
                            top: constraints.maxHeight * .015,
                            height: constraints.maxHeight * .115,
                            child: Container(
                              color: Colors.white,
                              alignment: Alignment.center,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '$documentTitle xxth 거래 명세서',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // 영수번호 Prefix: 실제 문서 우측 상단 번호칸.
                        if (receiptPrefix.isNotEmpty)
                          Positioned(
                            right: constraints.maxWidth * .010,
                            top: constraints.maxHeight * .018,
                            width: constraints.maxWidth * .145,
                            height: constraints.maxHeight * .095,
                            child: Container(
                              color: Colors.white,
                              alignment: Alignment.center,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  receiptPrefix,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ),

                        if (remark.isNotEmpty)
                          Positioned(
                            left: constraints.maxWidth * .055,
                            right: constraints.maxWidth * .055,
                            bottom: constraints.maxHeight * .020,
                            height: constraints.maxHeight * .065,
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
Write-Host 'Patch102 완료'
Write-Host '- BASE 미리보기 상단 흰 여백 제거'
Write-Host '- 실제 명세서만 카드 폭에 확대'
Write-Host '- 타이틀/영수번호 위치를 crop 기준으로 재정렬'
Write-Host 'flutter analyze 실행하세요.'
