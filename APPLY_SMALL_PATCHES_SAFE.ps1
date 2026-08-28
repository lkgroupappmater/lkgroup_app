$ErrorActionPreference = "Stop"

function Read-Utf8File([string]$Path) {
    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }
    return [System.IO.File]::ReadAllText(
        (Resolve-Path $Path),
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Write-Utf8File([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText(
        (Resolve-Path $Path),
        $Text,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Remove-BlockByMarkers(
    [string]$Text,
    [string]$StartMarker,
    [string]$EndMarker
) {
    $start = $Text.IndexOf($StartMarker)
    if ($start -lt 0) {
        return $Text
    }

    $end = $Text.IndexOf($EndMarker, $start)
    if ($end -lt 0) {
        throw "End marker not found: $EndMarker"
    }

    $end += $EndMarker.Length

    while ($end -lt $Text.Length -and
           ($Text[$end] -eq "`r" -or $Text[$end] -eq "`n")) {
        $end++
    }

    return $Text.Remove($start, $end - $start)
}

Write-Host ""
Write-Host "LKGroup safe patch - latest master compatible"
Write-Host "------------------------------------------------"

# ============================================================
# 1) quote_request_screen.dart
# ============================================================
$q = "lib/screens/quote_request_screen.dart"
$qText = Read-Utf8File $q

# 1-A. Remove the local fake-login field.
# Uses ASCII-only source markers. Safe when already removed.
$fakeLoginStart = "  // Simulated login state"
$fakeLoginEnd   = "  bool _isLoggedIn = false;"

if ($qText.Contains($fakeLoginStart)) {
    $qText = Remove-BlockByMarkers $qText $fakeLoginStart $fakeLoginEnd
    Write-Host "[OK] Removed simulated login field."
}
elseif ($qText.Contains("bool _isLoggedIn = false;")) {
    throw "Unexpected quote_request_screen.dart layout near _isLoggedIn."
}
else {
    Write-Host "[SKIP] Simulated login field already removed."
}

# 1-B. Replace only the special-quote login condition.
$oldCondition = "    if (!_isLoggedIn) {"
$newCondition = "    if (Supabase.instance.client.auth.currentUser == null) {"

if ($qText.Contains($oldCondition)) {
    $qText = $qText.Replace($oldCondition, $newCondition)
    Write-Host "[OK] Special quote now checks real Supabase session."
}
elseif ($qText.Contains($newCondition)) {
    Write-Host "[SKIP] Real Supabase login condition already applied."
}
else {
    throw "Expected special-quote login condition was not found."
}

# 1-C. Remove the test checkbox UI by stable English comment markers.
# Start: // Mock login toggle for testing
# End: the Row block immediately before the parent ListView closes.
$toggleMarker = "          // Mock login toggle for testing"
if ($qText.Contains($toggleMarker)) {
    $start = $qText.IndexOf($toggleMarker)
    $tailMarker = "          ),`r`n        ],"
    $end = $qText.IndexOf($tailMarker, $start)

    if ($end -lt 0) {
        # Git may have LF-only line endings.
        $tailMarker = "          ),`n        ],"
        $end = $qText.IndexOf($tailMarker, $start)
    }

    if ($end -lt 0) {
        throw "Could not locate the end of the test-login Row block."
    }

    # Include the Row's closing '),' but leave the ListView children closing '],'.
    $rowCloseLength = "          ),".Length
    $qText = $qText.Remove($start, ($end + $rowCloseLength) - $start)

    Write-Host "[OK] Removed test-login checkbox UI."
}
else {
    Write-Host "[SKIP] Test-login checkbox UI already removed."
}

# Final quote assertions.
if ($qText.Contains("bool _isLoggedIn = false;")) {
    throw "Safety check failed: _isLoggedIn still exists."
}
if ($qText.Contains("// Mock login toggle for testing")) {
    throw "Safety check failed: test-login block still exists."
}
if (-not $qText.Contains(
    "if (Supabase.instance.client.auth.currentUser == null) {"
)) {
    throw "Safety check failed: real Supabase login check missing."
}

Write-Utf8File $q $qText

# ============================================================
# 2) cargo_management_screen.dart
# ============================================================
$c = "lib/screens/cargo_management_screen.dart"
$cText = Read-Utf8File $c

$oldAvatar = "              leading: const CircleAvatar(child: Icon(Icons.person)),"
$newAvatar = @'
              leading: CircleAvatar(
                backgroundImage: widget.user.avatarUrl != null &&
                        widget.user.avatarUrl!.trim().isNotEmpty
                    ? NetworkImage(widget.user.avatarUrl!)
                    : null,
                child: widget.user.avatarUrl == null ||
                        widget.user.avatarUrl!.trim().isEmpty
                    ? const Icon(Icons.person)
                    : null,
              ),
'@

if ($cText.Contains($oldAvatar)) {
    $cText = $cText.Replace($oldAvatar, $newAvatar.TrimEnd("`r", "`n"))
    Write-Host "[OK] Cargo-management profile image connected."
}
elseif ($cText.Contains("backgroundImage: widget.user.avatarUrl")) {
    Write-Host "[SKIP] Cargo-management profile image already connected."
}
else {
    throw "Expected CircleAvatar line was not found in cargo_management_screen.dart."
}

if (-not $cText.Contains("backgroundImage: widget.user.avatarUrl")) {
    throw "Safety check failed: cargo avatar patch missing."
}

Write-Utf8File $c $cText

Write-Host "------------------------------------------------"
Write-Host "Safe patch completed successfully."
Write-Host ""
Write-Host "Next:"
Write-Host "  flutter clean"
Write-Host "  flutter pub get"
Write-Host "  flutter analyze"
