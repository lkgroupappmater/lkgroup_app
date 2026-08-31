$ErrorActionPreference = "Stop"
$utf8 = [System.Text.UTF8Encoding]::new($false)

function ReadText([string]$p) {
  [System.IO.File]::ReadAllText((Resolve-Path $p), $utf8)
}
function WriteText([string]$p,[string]$t) {
  [System.IO.File]::WriteAllText((Resolve-Path $p), $t, $utf8)
}
function ReplaceOnce([string]$text,[string]$old,[string]$new,[string]$label) {
  $count = ([regex]::Matches($text,[regex]::Escape($old))).Count
  if ($count -ne 1) {
    throw "안전 중단 [$label]: 대상 발견 수=$count"
  }
  return $text.Replace($old,$new)
}

$path = "lib/services/notification_service.dart"
$text = ReadText $path

$old = @'
  Future<List<Map<String, dynamic>>> fetchRecent() async {
    if (!SupabaseConfig.isConfigured || SupabaseService.client.auth.currentUser == null) {
      return const [];
    }
    final rows = await SupabaseService.client
        .from('user_notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(rows);
  }
'@

$new = @'
  Future<List<Map<String, dynamic>>> fetchRecent() async {
    if (!SupabaseConfig.isConfigured ||
        SupabaseService.client.auth.currentUser == null) {
      return const [];
    }

    // 읽지 않은 알림은 기간 제한 없이 계속 보관해서 표시합니다.
    // 이미 확인한 알림은 read_at 기준 24시간까지만 알림 목록에 표시합니다.
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 24))
        .toIso8601String();

    final rows = await SupabaseService.client
        .from('user_notifications')
        .select()
        .or('is_read.eq.false,read_at.gte.$cutoff')
        .order('created_at', ascending: false)
        .limit(50);

    return List<Map<String, dynamic>>.from(rows);
  }
'@

$text = ReplaceOnce $text $old $new "notification recent 24h"
WriteText $path $text

Write-Host ""
Write-Host "Patch159 적용 완료"
Write-Host "- 미확인 알림: 계속 표시"
Write-Host "- 확인한 알림: 확인 시각(read_at)부터 24시간만 표시"
Write-Host "- 24시간 지난 확인 알림: 알림 목록에서 자동 제외"
Write-Host "- 로그인 자동 팝업 재표시는 Patch158 동작 유지"
Write-Host ""
Write-Host "다음: flutter analyze"
