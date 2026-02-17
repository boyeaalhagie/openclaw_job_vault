# OpenClaw Job Vault (Windows)
# Press Ctrl+Alt+J → auto-starts gateway/browser if needed → captures the active tab → saves locally

$ErrorActionPreference = "Stop"

# -------------------------
# Config — change $StorageRoot to wherever you want captures saved
# -------------------------
$Profile     = "openclaw"
$GatewayPort = 18789
$StorageRoot = "C:\Users\boyea\OneDrive - Milwaukee School of Engineering\Desktop\OpenClaw Job Vault"

# -------------------------
# Auto-start gateway + browser if not running
# -------------------------
function Ensure-Gateway() {
  $listening = netstat -an 2>$null | Select-String "127.0.0.1:$GatewayPort.*LISTENING"
  if (-not $listening) {
    Start-Process -FilePath "openclaw" -ArgumentList "gateway","--port",$GatewayPort -WindowStyle Hidden
    Start-Sleep -Seconds 8
  }
}

function Ensure-Browser() {
  try {
    $status = & openclaw browser --browser-profile $Profile status 2>&1
    if ($status -match "running:\s*true") { return }
  } catch {}
  & openclaw browser --browser-profile $Profile start 2>$null
  Start-Sleep -Seconds 5
}

Ensure-Gateway
Ensure-Browser

# -------------------------
# Helpers
# -------------------------
function Safe-Slug([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return "untitled" }
  $t = $s.Trim()
  $t = $t -replace '[\\/:*?"<>|]', ''
  $t = $t -replace '\s+', ' '
  $t = $t -replace '[^\w\s-]', ''
  $t = $t -replace '\s', '-'
  if ($t.Length -gt 90) { $t = $t.Substring(0, 90) }
  if ([string]::IsNullOrWhiteSpace($t)) { return "untitled" }
  return $t
}

function Get-ActiveTab() {
  # Get all tabs from OpenClaw
  try {
    $raw = & openclaw browser --browser-profile $Profile tabs --json 2>$null
    if (-not $raw) { return $null }
    $parsed = $raw | ConvertFrom-Json
    $tabs = if ($parsed.tabs) { $parsed.tabs } else { @($parsed) }
    $pages = @($tabs | Where-Object { $_.url -and $_.url -ne "about:blank" -and $_.type -eq "page" })
    if ($pages.Count -eq 0) { return $null }
  } catch { return $null }

  # Read Chrome window title to find which tab is actually active
  $chromeProc = Get-Process chrome -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowTitle -ne "" } | Select-Object -First 1

  if ($chromeProc) {
    $winTitle = $chromeProc.MainWindowTitle -replace '\s*[-–]\s*Google Chrome$', ''
    foreach ($p in $pages) {
      if ($p.title -eq $winTitle) { return $p }
    }
  }

  # Fallback: return the last page tab
  return $pages[-1]
}

# -------------------------
# Identify the active tab
# -------------------------
$tab = Get-ActiveTab
if (-not $tab) {
  Write-Host "Could not read active tab from OpenClaw." -ForegroundColor Red
  exit 1
}

$targetId = $tab.targetId
$url      = $tab.url
$title    = if ($tab.title) { $tab.title } else { "Untitled" }

# -------------------------
# Create bundle folder directly in StorageRoot
# -------------------------
$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$slug  = Safe-Slug $title
$bundleDirName = "$stamp - $slug"

New-Item -ItemType Directory -Force -Path $StorageRoot | Out-Null
$bundleDir = Join-Path $StorageRoot $bundleDirName
New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null

$logPath = Join-Path $bundleDir "cli.log"
"[$(Get-Date -Format o)] Save JD start" | Out-File -Encoding utf8 $logPath
"Title: $title" | Out-File -Encoding utf8 -Append $logPath
"URL: $url" | Out-File -Encoding utf8 -Append $logPath
"TargetId: $targetId" | Out-File -Encoding utf8 -Append $logPath

# Save URL
$url | Out-File -Encoding utf8 (Join-Path $bundleDir "page_url.txt")

# Snapshot (target the specific tab by ID)
try {
  $snapArgs = @("browser","--browser-profile",$Profile,"snapshot","--format","ai","--target-id",$targetId)
  $snapOut = & openclaw @snapArgs 2>&1
  $snapOut | Out-File -Encoding utf8 (Join-Path $bundleDir "snapshot.txt")
  "Snapshot: OK" | Out-File -Encoding utf8 -Append $logPath
} catch {
  "Snapshot: FAIL - $($_.Exception.Message)" | Out-File -Encoding utf8 -Append $logPath
}

# PDF (target the specific tab by ID)
$pdfFinalPath = Join-Path $bundleDir "job.pdf"
try {
  $pdfArgs = @("browser","--browser-profile",$Profile,"pdf","--target-id",$targetId)
  $pdfOut = & openclaw @pdfArgs 2>&1
  $pdfOut | Out-File -Encoding utf8 -Append $logPath

  $m = [regex]::Match($pdfOut, "PDF:(.+)$", "Multiline")
  if ($m.Success) {
    $pdfTempPath = $m.Groups[1].Value.Trim()
    if (Test-Path $pdfTempPath) {
      Copy-Item $pdfTempPath $pdfFinalPath -Force
      "PDF: OK ($pdfTempPath)" | Out-File -Encoding utf8 -Append $logPath
    } else {
      "PDF: FAIL - temp path not found: $pdfTempPath" | Out-File -Encoding utf8 -Append $logPath
    }
  } else {
    "PDF: FAIL - could not parse PDF path from output" | Out-File -Encoding utf8 -Append $logPath
  }
} catch {
  "PDF: FAIL - $($_.Exception.Message)" | Out-File -Encoding utf8 -Append $logPath
}

# Metadata
$meta = @{
  saved_at  = (Get-Date).ToString("o")
  profile   = $Profile
  title     = $title
  url       = $url
  target_id = $targetId
}
$meta | ConvertTo-Json -Depth 6 | Out-File -Encoding utf8 (Join-Path $bundleDir "meta.json")
"Meta: OK" | Out-File -Encoding utf8 -Append $logPath

Write-Host ""
Write-Host "Saved: $title" -ForegroundColor Green
Write-Host "  -> $bundleDir" -ForegroundColor Gray
Write-Host ""
