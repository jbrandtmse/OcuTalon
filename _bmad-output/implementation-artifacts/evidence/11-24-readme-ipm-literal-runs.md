# Story 11.24: the README's IPM install, run literally

Evidence for AC1 (literal install on a fresh build 154 and a fresh build 109 instance), AC2 (one sequence, both cases) and AC3 (the guide's samples). Recorded 2026-11-05 by the implement stage, on arm64, in lane-B throwaway containers started from the plain AI Hub images (one container at a time, web port published on the loopback interface only, each container removed after its run). The commands were extracted from the fenced blocks of README.md's "Install it with IPM" section in the working tree, which held the approved text, before that text was committed, in this order: blocks 1 and 2 pasted into one terminal session in %SYS, block 3 into a session in USER, block 4 into a session in USER. The four blocks below are identical to the fenced blocks of that section in README.md as committed in dc1d0f09 (git blob 715253dd460d09ea7793a7344a7ff90b150dc34c). Each run's block quotes selected lines, not the whole output: colour codes are removed, tabs are shown as one space, a line that is the end of a longer output line is quoted from the text shown, and a `USER install:` prefix names the session, not output.

## The commands, as extracted from README.md

Block 1 (%SYS):

```
s r=##class(%Net.HttpRequest).%New(),r.Server="pm.community.intersystems.com",r.SSLConfiguration="ISC.FeatureTracker.SSL.Config" d r.Get("/packages/zpm/0.10.10/installer"),$system.OBJ.LoadStream(r.HttpResponse.Data,"c")
```

Block 2 (%SYS, same session as block 1):

```
zpm "enable -map -ns USER"
zpm "enable -community"
```

Block 3 (USER):

```
zpm "install ocutalon"
```

Block 4 (USER, the second line runs in OCUTALON after the first):

```
zn "OCUTALON"
zpm "install ocutalon"
```

## Run 1: build 154, case 1 (fresh instance, no IPM, USER unmapped)

- Image: `irishealth-community:2026.3.0AI.154.0`
- `$ZVersion`: IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2026.3.0AI (Build 154U)
- Durations: container ready 49 s; blocks 1 and 2 in %SYS 34 s; block 3 in USER 89 s; block 4 in USER 62 s.
- Lines printed (first `Load finished successfully.` is the installer class import; the IPM install itself ended with the `Installation succeeded` line and a second `Load finished successfully.`, not repeated below):

```
Load finished successfully.
IPM.Installer: Installation succeeded at 2026-11-05 21:00:10
Mapping IPM repository in %SYS equivalently to USER
ERROR! OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.
[OCUTALON|ocutalon] Reload START (/usr/irissys/ipm/ocutalon/1.0.1/)
[OCUTALON|ocutalon] Activate SUCCESS
```

- `GET /ocutalon/` on the published web port: HTTP 200.
- Result: PASS (stop line in USER, `Activate SUCCESS` in OCUTALON, HTTP 200).

## Run 2: build 109, case 1 (fresh instance, no IPM, USER unmapped)

- Image: `irishealth-community:2027.1.0AI.109.0`
- `$ZVersion`: IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2027.1.0AI (Build 109U)
- Durations: container ready 29 s; blocks 1 and 2 in %SYS 29 s; block 3 in USER 78 s; block 4 in USER 73 s.
- Lines printed:

```
Load finished successfully.
IPM.Installer: Installation succeeded at 2026-11-05 21:04:05
Mapping IPM repository in %SYS equivalently to USER
ERROR! OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.
[OCUTALON|ocutalon] Reload START (/usr/irissys/ipm/ocutalon/1.0.1/)
[OCUTALON|ocutalon] Activate SUCCESS
```

- `GET /ocutalon/` on the published web port: HTTP 200.
- Result: PASS.

## Run 3: build 154, case 2 (USER mapped first, then the whole README block)

- Image: `irishealth-community:2026.3.0AI.154.0`
- `$ZVersion`: IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2026.3.0AI (Build 154U)
- Durations: container ready 60 s; setup (block 1 and a single `zpm "enable -community"` in %SYS) 41 s; failing USER install 1 s; then the whole README block: blocks 1 and 2 in %SYS 8 s; block 3 in USER 138 s; block 4 in USER 77 s.
- Setup, the state the previous README left (block 1, then only `zpm "enable -community"`), printed:

```
Mapping %IPM package in %SYS equivalently to USER
Skipping repository mapping of USER - IPM not mapped from source namespace.
USER install: ERROR! No repositories are configured and enabled in this namespace.
```

- After the setup, the whole README block (blocks 1 to 4, in order) printed:

```
Load finished successfully.
Mapping IPM repository in %SYS equivalently to USER
ERROR! OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.
[OCUTALON|ocutalon] Reload START (/usr/irissys/ipm/ocutalon/1.0.1/)
[OCUTALON|ocutalon] Activate SUCCESS
```

- The IPM line on this run installed nothing new: it printed only the installer class import and its `Load finished successfully.` (no `Installation succeeded` line).
- `GET /ocutalon/` on the published web port: HTTP 200.
- Result: PASS (the old single-command state fails with `No repositories`; the README block repairs it and both installs succeed).

## Run 4: build 154, IPM installed in USER itself (DW-760: the guide's USER command)

Recorded 2026-11-05 by the implement stage's rework pass, on arm64, in a lane-B throwaway container started from the plain image, under the same hygiene as Runs 1 to 3. The README blocks are the four above, unchanged. Block 1 here is the same line as in Run 1, but it is first run in a USER session, so IPM is installed in USER itself and not in %SYS. The step after the README blocks is the command the guide's new sentence gives, `zpm "enable -community"` in an IRIS terminal in USER.

- Image: `irishealth-community:2026.3.0AI.154.0`
- `$ZVersion`: IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2026.3.0AI (Build 154U)
- Durations: container ready 69 s; block 1 in USER 17 s; blocks 1 and 2 in %SYS 21 s; `enable -community` in USER 3 s; block 3 in USER 44 s; block 4 in USER 47 s.
- Step 1, block 1 in a USER session: IPM was installed in USER itself.

```
Load finished successfully.
[USER|ZPM] Activate SUCCESS2026-11-05 21:57:41 0 IPM.Installer: Installation succeeded at 2026-11-05 21:57:41
```

  After it, `zpm "version"` in a %SYS session printed `IPM is not enabled in namespace %SYS.` (the list it gave showed `USER>  zpm 0.10.10`, HSLIB and HSSYS with their own 0.10.5-SNAPSHOT), so %SYS had no IPM of its own. In USER, `zpm "repo -list"` printed `No repositories found.`

- Step 2, README blocks 1 and 2 in one %SYS session. Block 1 installed IPM in %SYS (`Installation succeeded at 2026-11-05 21:58:08`, then `Load finished successfully.`); block 2 printed:

```
Skipping IPM mapping of USER - IPM already installed.
Skipping repository mapping of USER - IPM not mapped from source namespace.
```

  Afterwards, in USER, `zpm "repo -list"` printed `No repositories found.` (USER's repositories were left as they were).

- Step 3, `zpm "enable -community"` in a USER session. The output begins, after the version line, with:

```
RUNNING command: "repo -delete-all"
Command "repo -delete-all" finished successfull
RUNNING command: "repo -reset-defaults"
```

  and lists the community registry (`https://pm.community.intersystems.com`, enabled, available). Afterwards `zpm "repo -list"` in USER listed that registry.

- Step 4, block 3 in USER printed the OCUTALON stop line; block 4 in USER ended with the reload and the activation:

```
ERROR! OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.
[OCUTALON|ocutalon] Reload START (/usr/irissys/ipm/ocutalon/1.0.1/)
[OCUTALON|ocutalon] Activate SUCCESS
```

- `GET /ocutalon/` on the published web port: HTTP 200.
- Result: PASS. The two %SYS commands left USER's repositories as they were, `enable -community` in USER deleted the repositories first (`repo -delete-all`) and set up the registry, and the install then worked, as the guide's sentence says.

## Task 0 table (plan stage, 2026-11-05, four fresh lane-B throwaways, arm64, plain images)

| Case | Build | IPM line | Enable step | USER install | OCUTALON install | `GET /ocutalon/` |
|------|-------|----------|-------------|--------------|------------------|------------------|
| 1 (fresh) | 154 | installs IPM 0.10.10 (23.0 s) | `enable -map -ns USER`, then `enable -community`: "Mapping IPM repository in %SYS equivalently to USER" | stops with the OCUTALON line | Activate SUCCESS | 200 |
| 1 (fresh) | 109 | installs IPM 0.10.10 (14.0 s) | same | same | same | 200 |
| 2 (old README state) | 154 | installs IPM 0.10.10; a single `enable -community` then prints "Skipping repository mapping of USER - IPM not mapped from source namespace." | the whole block again (IPM line, map step, `enable -community`) maps the repositories of USER | before the block: "ERROR! No repositories are configured and enabled in this namespace."; after it: stops with the OCUTALON line | Activate SUCCESS | 200 |
| 2 (old README state) | 109 | same as 154 | same | same | Activate SUCCESS | 200 |

Plan-stage durations in seconds, 154 case 1 / 154 case 2 / 109 case 1 / 109 case 2: container ready 73 / 31 / 38 / 13; %SYS block 27 (IPM line alone) / 6 / 19 / 6; USER run 90 / 53 / 58 / 96; OCUTALON run 57 / 54 / 47 / 56.

On both builds a fresh image has no `%IPM.Main` in %SYS, USER or HSCUSTOM and `zpm "version"` in %SYS answers `<SYNTAX>`; HSLIB and HSSYS carry their own IPM (0.10.5-SNAPSHOT on 154, 0.10.10 on 109). The registry's pinned 0.10.10 installer and its latest installer were the same bytes that day.

## Sample blocks of docs/install-ipm.md refreshed from Run 1

The guide's samples came from the plan stage's run. After Run 1 each sample block was compared line by line with Run 1's real output (colour codes and banner removed, trailing spaces trimmed, tabs kept). Blocks that differed were replaced with Run 1's lines; prose is unchanged.

- Changed: the tail of the IPM load output (installation time stamps, elapsed time, time spent); the USER sample (compilation start time and duration); the OCUTALON sample (compilation start time and duration, the `STEP Bridge.Installer` duration, the production start time stamps and the `STEP Production` duration).
- Unchanged (identical to Run 1): the `enable -map -ns USER` output block and the `enable -community` output block.
- After the refresh `docker/tests/test-readme.sh` and `docker/tests/test-cpf.sh` pass.
