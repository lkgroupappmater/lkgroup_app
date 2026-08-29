$ErrorActionPreference = 'Stop'
$p='lib/screens/additional_feature_development_screen.dart'
$t=Get-Content -Raw -Encoding UTF8 $p

# 일반 field에도 선택적으로 실시간 rebuild 지원
$old=@'
  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
'@
$new=@'
  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    bool livePreview = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: livePreview ? (_) => setState(() {}) : null,
      decoration: InputDecoration(
'@
if(-not $t.Contains($old)){ throw '_field anchor not found' }
$t=$t.Replace($old,$new)

# BASE preview 전체를 Stack overlay 방식으로 교체
$start=$t.IndexOf('  Widget _basePreview() {')
$end=$t.IndexOf('  Widget _templateOverrideEditor() {',$start)
if($start -lt 0 -or $end -lt 0){ throw '_basePreview block not found' }

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
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '명세서 BASE 전체 미리보기',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              '입력 중인 문서 타이틀 / 영수번호 Prefix / Remark가 아래 BASE 미리보기에 즉시 반영됩니다.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 1.42,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/statement_forms/$formKey.png',
                          fit: BoxFit.contain,
                          alignment: Alignment.topCenter,
                          errorBuilder: (_, __, ___) => const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              '선택한 BASE의 앱 미리보기 이미지를 찾지 못했습니다.',
                            ),
                          ),
                        ),
                        if (documentTitle.isNotEmpty)
                          Positioned(
                            left: constraints.maxWidth * .20,
                            right: constraints.maxWidth * .20,
                            top: constraints.maxHeight * .012,
                            height: constraints.maxHeight * .065,
                            child: Container(
                              color: Colors.white,
                              alignment: Alignment.center,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '$documentTitle xxth 거래 명세서',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (receiptPrefix.isNotEmpty)
                          Positioned(
                            right: constraints.maxWidth * .018,
                            top: constraints.maxHeight * .105,
                            width: constraints.maxWidth * .14,
                            height: constraints.maxHeight * .045,
                            child: Container(
                              color: Colors.white,
                              alignment: Alignment.center,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  receiptPrefix,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (remark.isNotEmpty)
                          Positioned(
                            left: constraints.maxWidth * .08,
                            right: constraints.maxWidth * .08,
                            bottom: constraints.maxHeight * .035,
                            height: constraints.maxHeight * .05,
                            child: Container(
                              color: Colors.white,
                              alignment: Alignment.centerLeft,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Remark : $remark',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

'@
$t=$t.Substring(0,$start)+$block+$t.Substring($end)

# receipt / remark 필드 입력 시 live rebuild
$t=$t.Replace(
"_field(_receiptPrefixController, '영수번호 Prefix')",
"_field(_receiptPrefixController, '영수번호 Prefix', livePreview: true)"
)
$t=$t.Replace(
"_field(_remarkController, 'Remark')",
"_field(_remarkController, 'Remark', livePreview: true)"
)

Set-Content -Path $p -Value $t -Encoding UTF8
Write-Host 'Patch100 완료: BASE 미리보기 실시간 오버레이 적용'
Write-Host 'flutter analyze 실행하세요.'
