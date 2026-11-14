# Story 36.7: stale bundle files on upgrade (DW-1320), evidence

Records only. The rehearsal against v1.0.9 and its mutation run were run by the lead at smoke (the implement stage did not run `release/upgrade-harness.sh` against a previous release). Each section states what was expected, then what was measured.

## Measured at the implement stage (lane-B throwaways, tags e36s7i and e36s7b)

- `live:install-upgrade`: five stale files and six survivors planted under the first version; after the upgrade none of the stale files is left, each survivor is kept with its content, and the served folder without the survivors equals `/opt/ocutalon/src/ocutalon/csp` byte for byte (31 files). The start's log holds `WARN Web removed old web file main-ZZSTALE0.js`.
- `release/ipm-install.sh b`, check 25: on a real IPM install the module's Root is the folder that was loaded and `Web.BuildFolder()` is its `ocutalon/csp/`; the planted `main-ZZSTALE0.js` is removed, `zz-admin-note.txt` stays and the served `index.html` equals the loaded copy's.
- Initial web bundle with the reload handler: 883.39 kB, against 882.45 kB without it (+0.94 kB; cap 921 kB).

## The rehearsal's record section

`release/upgrade-harness.sh build|settings|seed|upgrade|restart|storage|report|down --rehearsal --previous v1.0.9 --record <temp file>`, tag e36s7h. Expected: `Result: pass`, and the `stale files` row passes with the plant note (`main-ZZSTALE0.js was planted in the served folder before the upgrade, standing in for an earlier upgrade's leftover; every mode plants it`).

Result (run by the lead on a lane-B throwaway, 2026-11-14, from OCT-epic36-s367 cd8a9381 with its own web build):

```text
# OcuTalon 1.0.9

## Upgrade harness

Result: pass
Mode: rehearsal
Required: yes
Candidate: 1.0.9 at cd8a938189bb86f736b0671570148a24b67f44d6
Previous: explicit v1.0.9 at 9b38cd395a4e1a8cc707ad82423307b8623adda7, version 1.0.9, built as 1.0.9-pre.1
Run: 2026-11-14T08:58:26Z to 2026-11-14T09:10:56Z, tag e36s7h
Merge retries: 0

| Record | Result | Detail |
| --- | --- | --- |
| previous build | pass | 12 checks passed |
| upgrade | pass | 13 checks passed |
| conversation | pass | 3 checks passed |
| reminder | pass | 2 checks passed; R1 fired on-time (due 184 s after the candidate was ready) |
| approval | pass | 6 checks passed |
| watch | pass | 2 checks passed |
| settings | pass | 9 checks passed |
| restart | pass | 10 checks passed |
| storage | pass | 2 checks passed |
| private globals | pass | 2 checks passed |
| stale files | pass | 3 checks passed; main-ZZSTALE0.js was planted in the served folder before the upgrade, standing in for an earlier upgrade's leftover; every mode plants it |
| pairing | pass | 5 checks passed |
| memory | pass | 2 checks passed |
| document | pass | 4 checks passed |
```

The upgrade phase's own lines: `PASS after the upgrade the served web folder holds exactly the candidate's 31 build files`; `PASS after the upgrade /ocutalon/main-ZZSTALE0.js answers 404 and /ocutalon/main-<hash>.js 200`. The install log (`/durable/ocutalon-after-start.log`): `WARN Web removed old web file main-JCJUH3RN.js` and `WARN Web removed old web file main-ZZSTALE0.js`.

On the upgraded stack (README account), /settings, /history and /usage each opened by address in a new page and then reloaded: GET 200, the h1 rendered, no console error, page error, failed request or 4xx/5xx script (`CHECK #/settings errors=0`, `#/history errors=0`, `#/usage errors=0`, 3 passed).

## The served and build lists

After the upgrade and after the restart: `diff <build list> <served list>` is empty (the build list is `find src/ocutalon/csp -type f | LC_ALL=C sort`).

Measured: the build list (31 files) and the served folder's list were identical after `upgrade` and again after `restart` (`diff` empty both times).

## The mutation run's `stale files` row

With the `RemoveStaleBundle` call removed from `Web.Prepare`, tag e36s7m, `build`, `seed`, `upgrade`, `report`, `down`: the row fails and names `./main-JCJUH3RN.js` and `./main-ZZSTALE0.js`.

Measured (tag e36s7m; the `Quit ..RemoveStaleBundle(...)` line of `Web.Prepare` replaced by `Quit sc`, restored byte-identical afterwards): `FAIL after the upgrade the served web folder differs from the candidate's build output (31 files): extra ./main-JCJUH3RN.js ./main-ZZSTALE0.js`; the record row: `| stale files | fail | after the upgrade the served web folder differs from the candidate's build output (31 files): extra ./main-JCJUH3RN.js ./main-ZZSTALE0.js |`, `RESULT fail`.
