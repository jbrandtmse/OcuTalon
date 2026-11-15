# Story 36.5: upgrade from v1.0.9 (Contest Planner ruling ~04:30Z Nov 14, Q1)

Run 2026-11-14 04:13Z-04:27Z on a lane-B throwaway (tag e36h1), from a clean checkout of OCT-epic36-s365 at 40428606 with its own web build (initial total 878.98 kB).
Command, phase by phase: `release/upgrade-harness.sh build|settings|seed|upgrade|restart|storage|report|down --rehearsal --previous v1.0.9 --record <temp file>`. No --rc, nothing under release/records, no tag, no branch, no push.

## Verdict: STOP on check 1 (one extra file); checks 2 and 3 pass

### Check 1: served web folder against the 40428606 build output: ONE EXTRA FILE

The `/ocutalon` application serves `/durable/iris/csp/ocutalon-web/`. After `upgrade` (and again after `restart`) it holds 28 files; the build output holds 27. `diff build served`:

```
26a27
> ./main-JCJUH3RN.js
```

`main-JCJUH3RN.js` is v1.0.9's main bundle (v1.0.9's index.html names it). The served index.html and main-7H5B5DGS.js are byte-identical to the build's (md5 562fe499..., 14953db7...). Cause (read from the code): `src/module.xml` `<FileCopy Name="ocutalon/csp/" Target="${dataDir}csp/ocutalon-web/"/>` copies the new bundle over the durable folder and deletes nothing; `Install.Step.Web.RemoveOldBundle` (STALEFILES) only clears the OLD folder `csp/ocutalon/`. So every upgrade whose main hash changes leaves the previous main behind; the behaviour predates Story 36.5. No v1.0.9 chunk file is left (v1.0.9's chunk names all recur in the new build).

### Check 2: deep link and reload of /settings, /history and /usage: PASS

On the upgraded stack (README account), each page opened by address in a new page and then reloaded: its GET answered 200, the h1 rendered, and there was no console error, page error, failed request or 4xx/5xx script response:

```
CHECK #/settings errors=0 failed=0 []
CHECK #/history errors=0 failed=0 []
CHECK #/usage errors=0 failed=0 []
  3 passed (2.9s)
```

### Check 3: the harness rows: PASS (approval included)

# OcuTalon 1.0.9

## Upgrade harness

Result: pass
Mode: rehearsal
Required: yes
Candidate: 1.0.9 at 404286065a184be544cab931b4eacae145473de0
Previous: explicit v1.0.9 at 9b38cd395a4e1a8cc707ad82423307b8623adda7, version 1.0.9, built as 1.0.9-pre.1
Run: 2026-11-14T04:13:40Z to 2026-11-14T04:27:27Z, tag e36h1
Merge retries: 0

| Record | Result | Detail |
| --- | --- | --- |
| previous build | pass | 12 checks passed |
| upgrade | pass | 13 checks passed |
| conversation | pass | 3 checks passed |
| reminder | pass | 2 checks passed; R1 fired on-time (due 190 s after the candidate was ready) |
| approval | pass | 6 checks passed |
| watch | pass | 2 checks passed |
| settings | pass | 9 checks passed |
| restart | pass | 10 checks passed |
| storage | pass | 2 checks passed |
| private globals | pass | 2 checks passed |
| pairing | pass | 5 checks passed |
| memory | pass | 2 checks passed |
| document | pass | 4 checks passed |
