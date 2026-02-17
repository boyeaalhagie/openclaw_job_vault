# OpenClaw Job Vault (Windows) — Part A

**Goal (only):** Press a keyboard shortcut → OpenClaw captures the current page (PDF + snapshot + metadata) → **saves that capture bundle to a local storage folder** (outside the repo, so captures never get pushed to GitHub).

> Project location (everything lives here):
`C:\Users\boyea\OneDrive - Milwaukee School of Engineering\Desktop\openclaw_job_vault`

> Storage location (where captures are kept — configurable in `save-jd.ps1`):
`C:\Users\boyea\OneDrive - Milwaukee School of Engineering\Desktop\OpenClaw Job Captures`

---

## 1) What you are building (MVP)

When you press **Ctrl + Alt + J** (from anywhere):

1. Auto-start the OpenClaw **gateway** and **browser** if they aren't running.
2. Read the **currently selected tab** from the **OpenClaw-managed browser profile** (`openclaw`).
3. Create a **bundle folder** under this repo's `captures/` (gitignored).
4. Save:
   - `job.pdf` (page rendered to PDF via OpenClaw)
   - `snapshot.txt` (OpenClaw snapshot output)
   - `page_url.txt` (URL)
   - `meta.json` (timestamp/title/url)
   - `cli.log` (debug output)
5. Copy that bundle to your **local storage folder**.

That's it. One shortcut, zero manual steps.

---

## 2) Repo layout

Inside:
`C:\Users\boyea\OneDrive - Milwaukee School of Engineering\Desktop\openclaw_job_vault`

```
openclaw_job_vault/
  scripts/
    save-jd.ps1
    OpenClawJobVault.ahk
  captures/                # auto-created, gitignored — never pushed
  README.md                # (this file)
  .gitignore
```

### `.gitignore`

```
captures/
**/cli.log
```

---

## 3) Prerequisites (Windows)

### A) OpenClaw installed and working
You must be able to run:
```bash
openclaw browser --browser-profile openclaw status
```

### B) OpenClaw browser profile enabled and usable

Ensure OpenClaw uses the managed `openclaw` browser profile.

Config file:
`C:\Users\boyea\.openclaw\openclaw.json` (typical on Windows)

Set at minimum:

```json
{
  "gateway": {
    "mode": "local"
  },
  "browser": {
    "enabled": true,
    "defaultProfile": "openclaw",
    "headless": false
  }
}
```

> The gateway and browser are auto-started by the script when you press the hotkey. No manual commands needed.

> **MVP rule:** browse jobs inside the **OpenClaw-managed browser** (orange badge) so the CLI can reliably target your active tab.

### C) AutoHotkey v2

Install AutoHotkey v2 so `.ahk` scripts can run.

---

## 4) Save-JD script (PowerShell)

`scripts/save-jd.ps1`

```powershell
# OpenClaw Job Vault (Windows)
# Press Ctrl+Shift+S → auto-starts gateway/browser if needed → captures page → saves locally
# Project root:
# C:\Users\boyea\OneDrive - Milwaukee School of Engineering\Desktop\openclaw_job_vault

$ErrorActionPreference = "Stop"

# -------------------------
# Config — change $StorageRoot to wherever you want captures saved
# -------------------------
$Profile    = "openclaw"
$GatewayPort = 18789

$ProjectRoot  = "C:\Users\boyea\OneDrive - Milwaukee School of Engineering\Desktop\openclaw_job_vault"
$CapturesRoot = Join-Path $ProjectRoot "captures"
$StorageRoot  = "C:\Users\boyea\OneDrive - Milwaukee School of Engineering\Desktop\OpenClaw Job Vault"

# Ensure captures folder exists
New-Item -ItemType Directory -Force -Path $CapturesRoot | Out-Null

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

function Safe-Slug([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return "untitled" }
  $t = $s.Trim()
  $t = $t -replace '[\\/:*?"<>|]', ''       # invalid filename chars
  $t = $t -replace '\s+', ' '               # normalize whitespace
  $t = $t -replace '[^\w\s-]', ''           # remove odd symbols
  $t = $t -replace '\s', '-'                # spaces -> dashes
  if ($t.Length -gt 90) { $t = $t.Substring(0, 90) }
  if ([string]::IsNullOrWhiteSpace($t)) { return "untitled" }
  return $t
}

function Get-ActiveTab() {
  # Both `tab --json` and `tabs --json` return {"tabs": [...]}
  # We unwrap .tabs and pick the best candidate.

  # Preferred: openclaw browser tab --json
  try {
    $raw = & openclaw browser --browser-profile $Profile tab --json 2>$null
    if ($raw) {
      $parsed = $raw | ConvertFrom-Json
      $list = if ($parsed.tabs) { $parsed.tabs } else { @($parsed) }
      if ($list.Count -gt 0) { return ($list | Select-Object -First 1) }
    }
  } catch {}

  # Fallback: openclaw browser tabs --json
  try {
    $rawTabs = & openclaw browser --browser-profile $Profile tabs --json 2>$null
    if (-not $rawTabs) { return $null }
    $parsed = $rawTabs | ConvertFrom-Json
    $tabs = if ($parsed.tabs) { $parsed.tabs } else { @($parsed) }

    # Filter out blank/internal pages
    $pages = $tabs | Where-Object { $_.url -and $_.url -ne "about:blank" -and $_.type -eq "page" }

    $selected = $pages | Where-Object { $_.selected -eq $true } | Select-Object -First 1
    if ($selected) { return $selected }

    $focused = $pages | Where-Object { $_.focused -eq $true } | Select-Object -First 1
    if ($focused) { return $focused }

    if ($pages) { return ($pages | Select-Object -First 1) }

    return ($tabs | Select-Object -First 1)
  } catch {}

  return $null
}

# -------------------------
# Capture
# -------------------------
$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

$tab = Get-ActiveTab
if (-not $tab) {
  Write-Host "❌ Could not read active tab from OpenClaw." -ForegroundColor Red
  Write-Host "Make sure the OpenClaw browser is running:" -ForegroundColor Yellow
  Write-Host "openclaw browser --browser-profile openclaw start" -ForegroundColor Yellow
  exit 1
}

# Field names vary by build; try common ones
$url = $tab.url
if (-not $url) { $url = $tab.href }
if (-not $url) { $url = $tab.location }

$title = $tab.title
if (-not $title) { $title = $tab.name }
if (-not $title) { $title = "Untitled" }

$slug = Safe-Slug $title
$bundleDirName = "$stamp - $slug"
$bundleDir = Join-Path $CapturesRoot $bundleDirName
New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null

$logPath = Join-Path $bundleDir "cli.log"
"[$(Get-Date -Format o)] Save JD start" | Out-File -Encoding utf8 $logPath

# Save URL
$pageUrlPath = Join-Path $bundleDir "page_url.txt"
$url | Out-File -Encoding utf8 $pageUrlPath
"URL: $url" | Out-File -Encoding utf8 -Append $logPath

# Snapshot
$snapshotPath = Join-Path $bundleDir "snapshot.txt"
try {
  $snapOut = & openclaw browser --browser-profile $Profile snapshot --format ai 2>&1
  $snapOut | Out-File -Encoding utf8 $snapshotPath
  "Snapshot: OK" | Out-File -Encoding utf8 -Append $logPath
} catch {
  "Snapshot: FAIL - $($_.Exception.Message)" | Out-File -Encoding utf8 -Append $logPath
}

# PDF
$pdfFinalPath = Join-Path $bundleDir "job.pdf"
try {
  $pdfOut = & openclaw browser --browser-profile $Profile pdf 2>&1
  $pdfOut | Out-File -Encoding utf8 -Append $logPath

  # Many builds output: PDF:<path>
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
$metaPath = Join-Path $bundleDir "meta.json"
$meta = @{
  saved_at = (Get-Date).ToString("o")
  profile  = $Profile
  title    = $title
  url      = $url
  bundle_dir = $bundleDir
}
$meta | ConvertTo-Json -Depth 6 | Out-File -Encoding utf8 $metaPath
"Meta: OK" | Out-File -Encoding utf8 -Append $logPath

# -------------------------
# Copy bundle to local storage folder
# -------------------------
try {
  New-Item -ItemType Directory -Force -Path $StorageRoot | Out-Null
  $storageDest = Join-Path $StorageRoot $bundleDirName
  "Copy: START -> $storageDest" | Out-File -Encoding utf8 -Append $logPath

  Copy-Item -Path $bundleDir -Destination $storageDest -Recurse -Force
  "Copy: OK" | Out-File -Encoding utf8 -Append $logPath

  Write-Host ""
  Write-Host "✅ Saved Job Vault bundle" -ForegroundColor Green
  Write-Host "Repo:    $bundleDir"
  Write-Host "Storage: $storageDest"
  Write-Host ""
} catch {
  "Copy: FAIL - $($_.Exception.Message)" | Out-File -Encoding utf8 -Append $logPath
  Write-Host ""
  Write-Host "⚠️ Capture saved in repo but copy to storage failed." -ForegroundColor Yellow
  Write-Host "Repo: $bundleDir"
  Write-Host "Check: $logPath"
  Write-Host ""
  exit 2
}
```

---

## 5) Hotkey binding (Windows) — AutoHotkey v2

`scripts/OpenClawJobVault.ahk`

```ahk
; OpenClaw Job Vault Hotkey (AutoHotkey v2)
; Ctrl+Alt+J -> capture current page (J = Job)
; Auto-installs to Windows Startup so it runs on login.

#Requires AutoHotkey v2.0

; --- Auto-add to Startup folder (runs once, harmless if already there) ---
startupDir := A_Startup
shortcutPath := startupDir "\OpenClawJobVault.lnk"
if !FileExist(shortcutPath) {
  shell := ComObject("WScript.Shell")
  link := shell.CreateShortcut(shortcutPath)
  link.TargetPath := A_ScriptFullPath
  link.WorkingDirectory := A_ScriptDir
  link.Description := "OpenClaw Job Vault Hotkey"
  link.Save()
}

; --- Hotkey: Ctrl+Alt+J ---
^!j:: {
  ps1 := "C:\Users\boyea\OneDrive - Milwaukee School of Engineering\Desktop\openclaw_job_vault\scripts\save-jd.ps1"
  Run 'powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "' ps1 '"'
}
```

**One-time setup:** Double-click `OpenClawJobVault.ahk` once. It will auto-add itself to Windows Startup so the hotkey is always available after login.

---

## 6) How to use (daily flow)

1. Browse job postings in the OpenClaw browser (orange badge).
2. Press **Ctrl + Alt + J**.
3. Done. The gateway and browser auto-start if needed.

Results appear in:

* Repo bundle (gitignored):
  `...\openclaw_job_vault\captures\YYYY-MM-DD_HH-mm-ss - <title>\`
* Storage copy:
  `...\Desktop\OpenClaw Job Vault\<same folder name>\`

---

## 7) Quick tests (do these once)

### Test A — OpenClaw capture works

```bash
openclaw browser --browser-profile openclaw start
openclaw browser --browser-profile openclaw open https://example.com
openclaw browser --browser-profile openclaw pdf
openclaw browser --browser-profile openclaw snapshot --format ai
```

### Test B — Full end-to-end

Open a page in the OpenClaw browser and run:

```powershell
powershell -ExecutionPolicy Bypass -File ".\scripts\save-jd.ps1"
```

Check that:
* A bundle folder appears under `captures/`
* The same folder appears under `Desktop\OpenClaw Job Vault\`

---

## 8) Definition of Done (this project)

Pressing **Ctrl + Alt + J** creates a bundle in:
`...\openclaw_job_vault\captures\...`
and copies that same bundle to:
`...\Desktop\OpenClaw Job Vault\...`

Captures never get pushed to GitHub (gitignored).

No other goals in scope.
