# Codex Handoff

This document captures the project state and development context that can be preserved in Git. It does not claim to preserve hidden Codex internal state; it records the useful project context recoverable from the current session, code, tests, and Git history.

## Current Project Status

`Windows-BlueScreen-Diagnostic` is a public GitHub repository owned by `xiaohuang11211`.

The project is a Windows PowerShell 5.1 read-only diagnostic/evidence collection tool for Windows blue screen and hardware-related failure investigations. It currently generates:

- A detailed technical report: `BlueScreen_Report.txt`
- A Chinese user-readable summary: `Chinese_Summary_CN.txt`
- A script error file only when real module failures occur: `Script_Errors.txt`
- A copied `Minidump\` folder only when minidumps exist

Current version:

```text
0.1.0
```

Current remote:

```text
origin https://github.com/xiaohuang11211/Windows-BlueScreen-Diagnostic.git
```

## Completed Work

- Created the project from scratch under `E:\huang\jiance\Windows-BlueScreen-Diagnostic`.
- Initialized Git on branch `main`.
- Created a public GitHub repository and pushed the project.
- Implemented `src/BlueScreen_Check.ps1` for Windows 10 / 11 and Windows PowerShell 5.1.
- Implemented targeted event log queries with `Get-WinEvent -FilterHashtable`.
- Implemented system, PowerShell, administrator, CPU, motherboard, BIOS, memory, GPU, disk, PnP, dump configuration, Minidump, MEMORY.DMP, and event evidence collection.
- Implemented status separation: `OK`, `NO_EVENTS`, `WARNING`, `FAILED`, `NOT_AVAILABLE`, `SKIPPED`.
- Implemented `Script_Errors.txt` for actual module failures.
- Implemented Minidump safety: copy latest five minidumps only; never move/delete originals.
- Implemented MEMORY.DMP safety: record metadata only; never copy it.
- Implemented Chinese human-readable summary `Chinese_Summary_CN.txt`.
- Implemented build, test, clean, package, init, and dev-check automation.
- Implemented GitHub Actions CI for Windows PowerShell 5.1.
- Implemented `.gitignore` to keep reports, dump files, zips, dist, logs, and local artifacts out of Git.
- Verified local tests and real execution multiple times.

## Current Work In Progress

The immediate work is context synchronization for a second computer running Codex. This handoff file and `AGENTS.md` were added for that purpose.

There is no active feature branch. Work is on `main`.

## Important Decisions

- The tool is strictly read-only evidence collection, not repair.
  Reason: the user explicitly required no registry/BIOS/driver/system repair changes.

- The main target is Windows PowerShell 5.1, not PowerShell 7.
  Reason: Windows 10/11 include Windows PowerShell 5.1 by default.

- Event log queries use `Get-WinEvent -FilterHashtable`.
  Reason: avoids loading huge logs and filtering with `Where-Object`, reducing runtime and memory usage.

- Missing events must be `NO_EVENTS`, not `FAILED`.
  Reason: no matching event means the source was queried successfully and no evidence was found.

- Missing providers/directories/commands should be `NOT_AVAILABLE`, not "normal".
  Reason: absence of a provider or directory is not the same as confirmed health.

- Actual query exceptions should be `FAILED`.
  Reason: failed queries cannot be interpreted as no problem.

- Chinese summary content is encoded as UTF-8 Base64 inside the `.ps1`.
  Reason: direct Chinese text inside `.ps1` caused mojibake/parser failures under Windows PowerShell 5.1 in this environment.

- `Kernel-Power 41` must not be interpreted as proof of a bad power supply.
  Reason: it only means Windows observed an unclean shutdown/restart.

- The project currently uses no external package dependencies.

## Current Architecture

```text
Windows-BlueScreen-Diagnostic/
  src/
    BlueScreen_Check.ps1
  scripts/
    common.ps1
    init.ps1
    test.ps1
    build.ps1
    clean.ps1
    package.ps1
  tests/
  .github/workflows/
    ci.yml
  docs/
    CODEX_HANDOFF.md
  Run_BlueScreen_Check.bat
  build.bat
  test.bat
  dev-check.bat
  README.md
  CHANGELOG.md
  VERSION
  .gitignore
  LICENSE
  AGENTS.md
```

## Important Files

- `src/BlueScreen_Check.ps1`
  Main diagnostic script and report generator.

- `scripts/common.ps1`
  Shared automation and static safety checks.

- `scripts/test.ps1`
  Main local/CI test entry point.

- `scripts/build.ps1`
  Creates the distributable directory.

- `scripts/package.ps1`
  Runs test/build and creates a zip package.

- `Run_BlueScreen_Check.bat`
  User-facing diagnostic launcher.

- `Chinese_Summary_CN.txt`
  Generated report file, not committed. This is the primary file a Chinese-speaking non-technical user should read first.

- `AGENTS.md`
  Long-term agent rules and project guardrails.

- `docs/CODEX_HANDOFF.md`
  This A/B computer handoff file.

## Development History

Initial user requirements were extensive and safety-focused:

- Create a new GitHub project from scratch.
- Build a Windows blue screen and hardware abnormality evidence collection tool.
- Keep source, scripts, tests, release files, and CI separated.
- Add local automation scripts and BAT wrappers.
- Add GitHub Actions CI.
- Initialize Git, commit, and push to GitHub.
- Do not delete user data or force overwrite existing repositories.
- Do not upload real dumps, real diagnostic reports, local secrets, or hardware privacy data.
- Add clear README, VERSION, CHANGELOG, LICENSE, `.gitignore`.
- Ensure PowerShell 5.1 compatibility.

Implemented commits so far:

```text
1fbe8c7 feat: initialize Windows blue screen diagnostic tool
aba9a0c fix: handle empty event log queries
0c2220e feat: add Chinese diagnostic summary
4f5f7ab fix: classify empty localized event queries
```

During local testing, the script was run on the current Windows machine that had no known blue screen history. This exposed important classification bugs:

- "No matching events" was initially recorded as `FAILED`.
- It should have been `NO_EVENTS`.
- The logic was updated to classify `NoMatchingEventsFound` as `NO_EVENTS`.

The user requested a Chinese-readable report because English status text was hard to understand. `Chinese_Summary_CN.txt` was added.

## Failed / Abandoned Approaches

- Directly writing Chinese strings inside `src/BlueScreen_Check.ps1`.
  Abandoned because Windows PowerShell 5.1/parser behavior in this environment produced mojibake and syntax errors. The working approach is UTF-8 Base64 strings decoded at runtime.

- Interpreting localized "找不到任何与指定的选择条件匹配的事件" by matching direct Chinese text in source.
  Abandoned because direct Chinese in `.ps1` caused encoding risks. Use `FullyQualifiedErrorId` such as `NoMatchingEventsFound` instead.

- Treating `Get-WinEvent` no-match exceptions as real failures.
  Abandoned because this is a normal "no evidence found" result.

- Using GitHub CLI for repository creation.
  Abandoned because `gh` was not installed on this computer. The repository was created through the GitHub web interface and then pushed using Git.

- Relying on Git direct network access.
  Git initially failed to push after the first push because command-line Git was not using the system proxy. The local repository proxy was configured to `127.0.0.1:7897`.

## Known Issues

- The Chinese summary is useful but still concise. It does not yet explain every raw event from `BlueScreen_Report.txt`.
- Storage events may appear as `WARNING`; deeper interpretation of each storage event is not yet implemented.
- `PnP Problem Devices` can appear as `WARNING`; the Chinese summary does not yet include a dedicated PnP section.
- The generated zip/package may need regeneration after documentation-only changes if a release artifact is desired.
- GitHub Actions status after the latest commits was not checked through GitHub API/browser in this handoff task.
- Real diagnostics on a computer that cannot boot into Windows remain outside the script's scope.
- The tool cannot prove a computer is healthy; it can only report evidence it can read.

## Next Steps

1. Improve `Chinese_Summary_CN.txt` with more sections:
   PnP problem devices, Recent System Critical/Error, Recent Application Critical/Error, NVIDIA SMI availability, and administrator status.

2. Add event count/details to the Chinese summary:
   Include counts and top timestamps for storage/system/application warnings without overwhelming the user.

3. Add tests for localized/no-match event handling:
   Prefer a small unit-style helper around event classification so this does not regress.

4. Add README Chinese usage section:
   Explain that normal users should read `Chinese_Summary_CN.txt` first.

5. Consider a `docs/TROUBLESHOOTING_CN.md`:
   Explain how to interpret "no events", "not available", "warning", "failed", and what to do if a computer still blue-screens despite no script findings.

6. Optionally update `CHANGELOG.md` for post-0.1.0 commits before the next release.

## User Preferences / Constraints

The user explicitly prefers:

- Direct local implementation, not just code examples.
- Actual command execution and verification.
- Chinese explanations for user-facing diagnostic interpretation.
- Public GitHub repository is acceptable.
- Strong safety boundaries.
- No fabricated test results.
- No force push.
- No deletion of user data.
- No uploading real dump/report/privacy data.
- Clear distinction between:
  - "queried successfully, no record found"
  - "system does not provide this information"
  - "script failed to query"
  - "warning evidence found"

The user asked that Codex context be saved into Git so another computer can resume with `git clone` / `git pull`.

## Environment Notes

Observed A-computer environment:

- Workspace: `E:\huang\jiance\Windows-BlueScreen-Diagnostic`
- PowerShell: Windows PowerShell 5.1
- Git available
- GitHub CLI `gh` was not installed
- Git remote:
  `https://github.com/xiaohuang11211/Windows-BlueScreen-Diagnostic.git`
- Git push needed local repo proxy:

```powershell
git config http.proxy http://127.0.0.1:7897
git config https.proxy http://127.0.0.1:7897
```

There are no required environment variables, database services, package installs, API keys, or secrets.

## Last Handoff

- Branch: `main`
- Current development state: working diagnostic tool with Chinese summary, local automation, CI, and GitHub remote.
- Recently modified area: event query classification and Chinese summary output.
- Next recommended action: improve Chinese summary coverage and add regression tests for localized no-match event classification.
- Before continuing: run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\test.ps1`.

For B-computer Codex, read these files first:

1. `AGENTS.md`
2. `docs/CODEX_HANDOFF.md`
3. `README.md`
4. `src/BlueScreen_Check.ps1`
5. `scripts/test.ps1`

