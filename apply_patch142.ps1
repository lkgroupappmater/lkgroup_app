$ErrorActionPreference = "Stop"
$path = "lib/screens/cargo_management_screen.dart"
if (!(Test-Path $path)) { throw "파일을 찾을 수 없습니다: $path" }

$src = Get-Content $path -Raw -Encoding UTF8

# 1) 잠금 토글 처리 함수 추가
$anchor = @'
  Future<void> _showGroupStatement(List<Map<String, dynamic>> rows) async {
'@
$helper = @'
  Future<void> _toggleShipmentLock(Map<String, dynamic> item) async {
    if (!_isAdmin || _busy) return;
    final id = '${item['id']}';
    final current = item['data_locked'] == true;
    setState(() => _busy = true);
    try {
      await ShipmentService.instance.updateRow(
        id,
        {'data_locked': !current},
      );
      if (!mounted) return;
      setState(() => item['data_locked'] = !current);
      _message(!current ? '화물 데이터를 잠금했습니다.' : '화물 데이터 잠금을 해제했습니다.');
    } catch (error) {
      _message('화물 잠금 처리 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showGroupStatement(List<Map<String, dynamic>> rows) async {
'@

$countAnchor = ([regex]::Matches($src, [regex]::Escape($anchor))).Count
if ($countAnchor -ne 1) { throw "안전 중단: helper 삽입 위치 발견 수=$countAnchor" }
$src = $src.Replace($anchor, $helper)

# 2) 검색 결과에 실제 사용되는 _groupShipmentCard 범위만 수정
$start = $src.IndexOf("  Widget _groupShipmentCard(Map<String, dynamic> item) {")
$end = $src.IndexOf("  Widget _shipmentCard(Map<String, dynamic> item) {")
if ($start -lt 0 -or $end -le $start) { throw "안전 중단: _groupShipmentCard 범위를 찾을 수 없습니다." }

$before = $src.Substring(0, $start)
$group = $src.Substring($start, $end - $start)
$after = $src.Substring($end)

$old = @'
                        if (_isManager)
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () async {
                                    setState(() {
                                      _selectedIds
                                        ..clear()
                                        ..add(id);
                                    });
                                    await _editCheckedGroup([item]);
                                  },
                            icon: const Icon(Icons.edit_outlined, size: 17),
                            label: const Text('편집'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                            ),
                          ),
'@

$new = @'
                        if (_isManager)
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        setState(() {
                                          _selectedIds
                                            ..clear()
                                            ..add(id);
                                        });
                                        await _editCheckedGroup([item]);
                                      },
                                icon: const Icon(Icons.edit_outlined, size: 17),
                                label: const Text('편집'),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                ),
                              ),
                              if (_isAdmin)
                                IconButton(
                                  tooltip: item['data_locked'] == true ? '잠금 해제' : '잠금',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _busy
                                      ? null
                                      : () => _toggleShipmentLock(item),
                                  icon: Icon(
                                    item['data_locked'] == true
                                        ? Icons.lock
                                        : Icons.lock_open_outlined,
                                    size: 20,
                                    color: item['data_locked'] == true
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
'@

$count = ([regex]::Matches($group, [regex]::Escape($old))).Count
if ($count -ne 1) { throw "안전 중단: 검색 결과 편집 버튼 블록 발견 수=$count" }
$group = $group.Replace($old, $new)
$src = $before + $group + $after

Set-Content $path $src -Encoding UTF8
Write-Host "Patch142 적용 완료: 검색 화물 카드 오른쪽 편집 아래 잠금 토글 추가"
