$ErrorActionPreference = "Stop"
$utf8 = [System.Text.UTF8Encoding]::new($false)

function ReadText([string]$p) { [System.IO.File]::ReadAllText((Resolve-Path $p), $utf8) }
function WriteText([string]$p,[string]$t) { [System.IO.File]::WriteAllText((Resolve-Path $p),$t,$utf8) }
function ReplaceOnce([string]$text,[string]$old,[string]$new,[string]$label) {
  $count=([regex]::Matches($text,[regex]::Escape($old))).Count
  if($count -ne 1){ throw "안전 중단 [$label]: 대상 발견 수=$count" }
  return $text.Replace($old,$new)
}

$p="lib/widgets/app_shell.dart"
$t=ReadText $p

$old=@'
  Future<void> _showUnreadPopup(List<Map<String, dynamic>> rows) async {
    if (!mounted || rows.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('알림'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows
                .take(5)
                .map((n) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text('${n['message'] ?? ''}'),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
'@

$new=@'
  Future<void> _showUnreadPopup(List<Map<String, dynamic>> rows) async {
    if (!mounted || rows.isEmpty) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('알림'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows
                .take(5)
                .map((n) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text('${n['message'] ?? ''}'),
                    ))
                .toList(),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('확인'),
          ),
        ],
      ),
    );

    // 로그인 팝업에서 사용자가 실제로 '확인'한 알림은 읽음 처리합니다.
    // 기존에는 팝업만 닫고 is_read=false 상태가 그대로라 다음 로그인 때
    // 같은 알림이 계속 다시 표시되었습니다.
    try {
      await NotificationService.instance.markAllRead();
      if (!mounted) return;
      setState(() {
        _unreadNotifications = const [];
        _popupShownForCurrentBatch = false;
      });
    } catch (_) {
      // 읽음 처리 실패가 앱 사용을 막지는 않도록 합니다.
      // 실패한 경우 DB에는 unread 상태가 남으므로 다음 새로고침에서 다시 확인 가능합니다.
    }
  }
'@

$t=ReplaceOnce $t $old $new "notification popup read once"
WriteText $p $t

Write-Host ""
Write-Host "Patch158 적용 완료"
Write-Host "- 로그인 알림 팝업에서 확인 후 읽음 처리"
Write-Host "- 같은 알림의 로그인 반복 표시 방지"
Write-Host "- 상단 알림 배지 즉시 0으로 갱신"
Write-Host "- 알림 목록(fetchRecent) 기록은 유지"
Write-Host ""
Write-Host "다음: flutter analyze"
