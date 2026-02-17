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
  ps1 := A_ScriptDir "\save-jd.ps1"
  Run 'powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "' ps1 '"'
}
