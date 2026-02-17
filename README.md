# OpenClaw Job Vault

AI agent that saves job postings as PDFs and logs them to a CSV for tracking.

**The problems:** 

1. Job portals store your application but not the job posting itself. Once a listing is closed or removed, the description is gone -- and you have no way to review it when you get an interview. 

2. Students also end up manually tracking every role they applied to in spreadsheets, which nobody keeps up with.

**The solution:** Press one hotkey while you're on a job posting. The agent saves a permanent PDF copy and automatically extracts the job details (title, company, requirements, salary, location) into a CSV tracker. By the time you finish applying, everything is already stored.

---

## Usage

You browse jobs in Chrome. When you're on a job posting:

1. Press **Ctrl + Alt + J**.
2. Keep applying. The agent works in the background.
3. By the time you're done, the agent has:
   - Captured the full page (snapshot + PDF)
   - Read the posting and extracted: job title, company, description, requirements, salary, location
   - Saved everything to a timestamped folder
   - Appended a row to `jobs.csv`

**No switching windows. No copy-pasting into spreadsheets. Just apply and move on.**

---

## How it works

1. Press **Ctrl + Alt + J** while on a job posting.
2. The launcher script captures the page (snapshot + PDF) via OpenClaw CLI.
3. The OpenClaw agent uses its `read` tool to read the snapshot, reasons about the content, and uses its `write` tool to create `meta.json` with extracted fields.
4. The script reads the agent's output and appends a row to `jobs.csv`.

The agent's behavior is defined in `agent/prompt.md`. Edit that file to change what the agent extracts or how it reasons -- no code changes needed.

---

## Project structure

```
openclaw_job_vault/
  agent/
    prompt.md                # agent instructions (the "brain")
  scripts/
    save-jd.ps1              # launcher - captures page, sends to agent
    OpenClawJobVault.ahk     # global hotkey (Ctrl+Alt+J)
  .env.example               # template for API key
  .gitignore
  README.md
```

### Output (saved to Desktop by default)

```
~/Desktop/OpenClaw Job Vault/
  jobs.csv                                       # running log of all saved jobs
  2026-02-17_14-30-00 - Software-Engineer-Intern/
    snapshot.txt       # page text
    job.pdf            # page as PDF
    page_url.txt       # original URL
    meta.json          # agent-extracted structured data
```

---

## Setup

### 1. Install dependencies

```bash
# OpenClaw CLI
npm install -g openclaw@latest

# AutoHotkey v2 (for the global hotkey)
winget install AutoHotkey.AutoHotkey
```

### 2. Configure OpenClaw

Create or edit `~/.openclaw/openclaw.json`:

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

### 3. Add your OpenAI API key

```bash
cp .env.example .env
```

Edit `.env` and paste your key:

```
OPENAI_API_KEY=sk-your-actual-key
```

Get a key at [platform.openai.com/api-keys](https://platform.openai.com/api-keys). The agent uses GPT-4o for reasoning.

### 4. Set up the hotkey

Double-click `scripts/OpenClawJobVault.ahk`. It auto-adds itself to Windows Startup so the hotkey is always available after login.

### 5. (Optional) Change the storage folder

By default, captures are saved to `~/Desktop/OpenClaw Job Vault/`. To change this, edit the `$StorageRoot` variable near the top of `scripts/save-jd.ps1`.

---

## Usage

1. Browse jobs in Chrome (the OpenClaw browser auto-starts on first use).
2. Find a posting, start applying.
3. Press **Ctrl + Alt + J** while you're on the page.
4. Keep applying -- the agent captures and extracts in the background.
5. When you're done for the day, open `jobs.csv` to see everything you saved.

---

## Testing

### Verify OpenClaw works

```bash
openclaw browser --browser-profile openclaw start
openclaw browser --browser-profile openclaw open https://example.com
openclaw browser --browser-profile openclaw snapshot --format ai
```

### Verify the agent works

```bash
openclaw agent --agent main --local --message "Reply with: hello" --timeout 30
```

### Full end-to-end test

Open a job posting in the OpenClaw browser, then:

```powershell
powershell -ExecutionPolicy Bypass -File ".\scripts\save-jd.ps1"
```

Check that a bundle folder and `jobs.csv` appear in the storage folder.

---

## Architecture

```
Ctrl+Alt+J
    |
    v
save-jd.ps1 (launcher)
    |-- ensures gateway + browser are running
    |-- identifies active browser tab
    |-- captures snapshot + PDF via OpenClaw CLI
    |-- sends snapshot path to OpenClaw agent
    |
    v
OpenClaw Agent (GPT-4o)
    |-- reads snapshot using `read` tool
    |-- reasons about content
    |-- extracts structured fields
    |-- writes meta.json using `write` tool
    |
    v
save-jd.ps1 (continued)
    |-- reads agent's meta.json
    |-- appends row to jobs.csv
    |-- done
```

The agent's behavior is defined in `agent/prompt.md`. Edit that file to change what the agent extracts or how it reasons -- no code changes needed.

---

## CSV columns

| Column | Description |
|---|---|
| Date | Timestamp (YYYY-MM-DD_HH-mm-ss) |
| Job Title | Position name |
| Company | Employer |
| Description | 2-3 sentence summary |
| Requirements | Key qualifications (comma-separated) |
| Salary | Compensation or "Not listed" |
| Location | City/state, remote, hybrid |
| URL | Original job posting link |

---

## License

MIT
