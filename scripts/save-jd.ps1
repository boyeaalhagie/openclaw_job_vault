# OpenClaw Job Vault - Agent Launcher
# Ctrl+Alt+J -> capture page -> send to AI agent for intelligent extraction

$ErrorActionPreference = "Continue"

# -------------------------
# Config - edit these paths to match your setup
# -------------------------
$Profile     = "openclaw"
$GatewayPort = 18789

# Auto-detect project root (parent of scripts/)
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }

# Storage folder for captures + CSV (change this to wherever you want)
$StorageRoot = Join-Path ([Environment]::GetFolderPath("Desktop")) "OpenClaw Job Vault"

# -------------------------
# Load .env
# -------------------------
$envFile = Join-Path $ProjectRoot ".env"
if (Test-Path $envFile) {
  foreach ($line in (Get-Content $envFile)) {
    if ($line -match '^([^#]\w+)=(.+)$') {
      Set-Item -Path "Env:$($matches[1])" -Value $matches[2]
    }
  }
}

# -------------------------
# Ensure gateway + browser are running
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
  try {
    $raw = & openclaw browser --browser-profile $Profile tabs --json 2>$null
    if (-not $raw) { return $null }
    $parsed = $raw | ConvertFrom-Json
    $tabs = if ($parsed.tabs) { $parsed.tabs } else { @($parsed) }
    $pages = @($tabs | Where-Object { $_.url -and $_.url -ne "about:blank" -and $_.type -eq "page" })
    if ($pages.Count -eq 0) { return $null }
  } catch { return $null }

  $chromeProc = Get-Process chrome -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowTitle -ne "" } | Select-Object -First 1

  if ($chromeProc) {
    $winTitle = $chromeProc.MainWindowTitle -replace '\s*[-\u2013]\s*Google Chrome$', ''
    foreach ($p in $pages) {
      if ($p.title -eq $winTitle) { return $p }
    }
  }

  return $pages[-1]
}

# -------------------------
# Identify active tab
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
# Create bundle folder + capture
# -------------------------
$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$slug  = Safe-Slug $title
$bundleDirName = "$stamp - $slug"

New-Item -ItemType Directory -Force -Path $StorageRoot | Out-Null
$bundleDir = Join-Path $StorageRoot $bundleDirName
New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null

# Save URL
$url | Out-File -Encoding utf8 (Join-Path $bundleDir "page_url.txt")

# Snapshot
$snapshotPath = Join-Path $bundleDir "snapshot.txt"
try {
  $snapArgs = @("browser","--browser-profile",$Profile,"snapshot","--format","ai","--target-id",$targetId)
  $snapOut = & openclaw @snapArgs 2>&1
  $snapOut | Out-File -Encoding utf8 $snapshotPath
} catch {}

# PDF
try {
  $pdfArgs = @("browser","--browser-profile",$Profile,"pdf","--target-id",$targetId)
  $pdfOut = & openclaw @pdfArgs 2>&1
  $m = [regex]::Match($pdfOut, "PDF:(.+)$", "Multiline")
  if ($m.Success) {
    $pdfTempPath = $m.Groups[1].Value.Trim()
    if (Test-Path $pdfTempPath) {
      Copy-Item $pdfTempPath (Join-Path $bundleDir "job.pdf") -Force
    }
  }
} catch {}

Write-Host "Captured: $title" -ForegroundColor Cyan
Write-Host "Agent is extracting job details..." -ForegroundColor Cyan

# -------------------------
# Send to OpenClaw agent for intelligent extraction
# -------------------------
$csvPath = Join-Path $StorageRoot "jobs.csv"
$metaPath = Join-Path $bundleDir "meta.json"

$msg = "Read the file at $snapshotPath. Extract: job_title, company, description (2-3 sentences), requirements (comma-separated), salary (or Not listed), location. Use write tool to create $metaPath with JSON: saved_at ($stamp), title (<job_title> at <company>), url ($url), job_title, company, description, requirements, salary, location. Reply with the job title and company."

$sid = [guid]::NewGuid().ToString()

try {
  $agentArgs = @("agent", "--agent", "main", "--local", "--session-id", $sid, "--message", $msg, "--json", "--timeout", "180")
  $agentRaw = & openclaw @agentArgs 2>$null
  $agentText = ($agentRaw | Out-String).Trim()

  if ($agentText -match '(?s)(\{.*\})') {
    $parsed = $matches[1] | ConvertFrom-Json
    if ($parsed.payloads -and $parsed.payloads.Count -gt 0) {
      $reply = $parsed.payloads[0].text
      Write-Host ""
      Write-Host $reply -ForegroundColor Green
      Write-Host ""
    }
  }
} catch {
  Write-Host "Agent error: $($_.Exception.Message)" -ForegroundColor Red
}

# -------------------------
# Build CSV row from agent's meta.json output
# -------------------------
if (Test-Path $metaPath) {
  try {
    $meta = Get-Content $metaPath -Raw | ConvertFrom-Json

    $jobTitle     = if ($meta.job_title)    { $meta.job_title }    else { "" }
    $company      = if ($meta.company)      { $meta.company }      else { "" }
    $description  = if ($meta.description)  { $meta.description }  else { "" }
    $requirements = if ($meta.requirements) { $meta.requirements } else { "" }
    $salary       = if ($meta.salary)       { $meta.salary }       else { "Not listed" }
    $location     = if ($meta.location)     { $meta.location }     else { "" }

    if (-not (Test-Path $csvPath)) {
      "Date,Job Title,Company,Description,Requirements,Salary,Location,URL" | Out-File -Encoding utf8 $csvPath
    }

    $csvLine = @(
      $stamp,
      "`"$($jobTitle -replace '"','""')`"",
      "`"$($company -replace '"','""')`"",
      "`"$($description -replace '"','""')`"",
      "`"$($requirements -replace '"','""')`"",
      "`"$($salary -replace '"','""')`"",
      "`"$($location -replace '"','""')`"",
      "`"$url`""
    ) -join ","
    $csvLine | Out-File -Encoding utf8 -Append $csvPath

    Write-Host "CSV updated: $csvPath" -ForegroundColor Green
  } catch {
    Write-Host "CSV write failed: $($_.Exception.Message)" -ForegroundColor Red
  }
} else {
  Write-Host "Agent did not create meta.json - CSV not updated." -ForegroundColor Yellow
}
