$ErrorActionPreference = "Stop"

$path = "lib/screens/cargo_management_screen.dart"
if (!(Test-Path $path)) { throw "파일을 찾을 수 없습니다: $path" }

$text = Get-Content $path -Raw -Encoding UTF8

# 1) state: pending deletion list
$old = @'
  List<Map<String, dynamic>> _results = const [];
  final Set<String> _selectedIds = <String>{};
  bool _searched = false;
  bool _busy = false;
'@
$new = @'
  List<Map<String, dynamic>> _results = const [];
  List<Map<String, dynamic>> _pendingDeletions = const [];
  final Set<String> _selectedIds = <String>{};
  bool _searched = false;
  bool _busy = false;
'@
if (!$text.Contains($old)) { throw "state patch target not found" }
$text = $text.Replace($old, $new)

# 2) initState: load pending
$old = @'
    _selectedIds.addAll(widget.initialSelectedIds);
    if (widget.initialSelectedIds.isNotEmpty) _loadSelected();
  }
'@
$new = @'
    _selectedIds.addAll(widget.initialSelectedIds);
    if (widget.initialSelectedIds.isNotEmpty) _loadSelected();
    if (_isManager) _loadPendingDeletions();
  }
'@
if (!$text.Contains($old)) { throw "initState patch target not found" }
$text = $text.Replace($old, $new)

# 3) insert deletion methods before _reloadCurrentRows
$marker = @'
  Future<void> _reloadCurrentRows() async {
'@
$methods = @'
  Future<void> _loadPendingDeletions() async {
    if (!_isManager) return;
    try {
      final rows =
          await ShipmentService.instance.getPendingShipmentDeletions();
      if (!mounted) return;
      setState(() => _pendingDeletions = rows);
    } catch (error) {
      _message('화물 삭제 대기 목록 불러오기 실패: $error');
    }
  }

  Future<void> _requestDeletion(Map<String, dynamic> item) async {
    final id = '${item['id']}';
    final box = '${item['box_number'] ?? ''}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('화물 삭제'),
        content: Text(
          '$box 화물을 삭제 대기로 이동하시겠습니까?\n\n'
          '삭제 대기 중에는 아래 "화물 삭제 대기"에서 취소하거나 바로 삭제할 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('삭제 대기'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ShipmentService.instance.requestShipmentDeletion(id);
      _selectedIds.remove(id);
      setState(() {
        _results = _results
            .where((row) => '${row['id']}' != id)
            .toList(growable: false);
      });
      await _loadPendingDeletions();
      _message('$box 화물을 삭제 대기로 이동했습니다.');
    } catch (error) {
      _message('화물 삭제 대기 처리 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelDeletion(Map<String, dynamic> item) async {
    final id = '${item['id']}';
    setState(() => _busy = true);
    try {
      await ShipmentService.instance.cancelShipmentDeletion(id);
      await _loadPendingDeletions();
      _message('화물 삭제를 취소했습니다.');
      if (_searched) await _search();
    } catch (error) {
      _message('삭제 취소 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteNow(Map<String, dynamic> item) async {
    final id = '${item['id']}';
    final box = '${item['box_number'] ?? ''}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('화물 바로 삭제'),
        content: Text(
          '$box 화물을 바로 삭제하시겠습니까?\n\n'
          '바로 삭제 후에는 앱에서 복구할 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('바로 삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ShipmentService.instance.deleteShipmentNow(id);
      await _loadPendingDeletions();
      _message('$box 화물을 바로 삭제했습니다.');
    } catch (error) {
      _message('화물 바로 삭제 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _pendingDeletionCard(Map<String, dynamic> item) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '박스번호 ${item['box_number'] ?? ''}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.navyPrimary,
                ),
              ),
              const SizedBox(height: 6),
              _infoRow('운송 경로', '${item['route'] ?? ''}'),
              _infoRow('년도', '${item['shipment_year'] ?? ''}'),
              _infoRow('항차', _voyageLabel(item['voyage'])),
              _infoRow('송장번호', '${item['invoice_number'] ?? ''}'),
              _infoRow('이름', '${item['consignee_name'] ?? ''}'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _busy ? null : () => _cancelDeletion(item),
                      child: const Text('삭제 취소'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : () => _deleteNow(item),
                      child: const Text('바로 삭제'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

'@
if (!$text.Contains($marker)) { throw "deletion method insert target not found" }
$text = $text.Replace($marker, $methods + $marker)

# 4) add delete button to each searched cargo card, only manager roles
$old = @'
                    if (_isAdmin || _isStaff)
                      _infoRow('구획 (Zone)', '${item['unloading_zone'] ?? ''}'),
                  ],
'@
$new = @'
                    if (_isAdmin || _isStaff)
                      _infoRow('구획 (Zone)', '${item['unloading_zone'] ?? ''}'),
                    if (_isManager) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed:
                              _busy ? null : () => _requestDeletion(item),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('삭제'),
                        ),
                      ),
                    ],
                  ],
'@
if (!$text.Contains($old)) { throw "shipment card delete button target not found" }
$text = $text.Replace($old, $new)

# 5) bottom pending section, after selected edit block and before ListView close.
$old = @'
              ElevatedButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save),
                label: Text(_canSaveDirectly ? '화물 정보 저장' : '화물 정보 수정 요청'),
              ),
            ],
          ],
        ),
      );
'@
$new = @'
              ElevatedButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save),
                label: Text(_canSaveDirectly ? '화물 정보 저장' : '화물 정보 수정 요청'),
              ),
            ],
            if (_isManager) ...[
              const SizedBox(height: 24),
              const Text(
                '화물 삭제 대기',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 6),
              if (_pendingDeletions.isEmpty)
                const Text(
                  '삭제 대기 중인 화물이 없습니다.',
                  style: TextStyle(color: AppColors.textSecondary),
                )
              else
                ..._pendingDeletions.map(_pendingDeletionCard),
            ],
          ],
        ),
      );
'@
if (!$text.Contains($old)) { throw "pending section target not found" }
$text = $text.Replace($old, $new)

Set-Content $path $text -Encoding UTF8
Write-Host "cargo_management_screen.dart delete-pending patch applied"
