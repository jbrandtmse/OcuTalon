# Story 36.7: stale bundle files on upgrade (DW-1320), evidence

Records only. The rehearsal against v1.0.9 and its mutation run are the lead's, at smoke (the implement stage did not run `release/upgrade-harness.sh` against a previous release). The sections marked "to fill" take the lead's output as it is.

## Measured at the implement stage (lane-B throwaways, tags e36s7i and e36s7b)

- `live:install-upgrade`: five stale files and six survivors planted under the first version; after the upgrade none of the stale files is left, each survivor is kept with its content, and the served folder without the survivors equals `/opt/ocutalon/src/ocutalon/csp` byte for byte (31 files). The start's log holds `WARN Web removed old web file main-ZZSTALE0.js`.
- `release/ipm-install.sh b`, check 25: on a real IPM install the module's Root is the folder that was loaded and `Web.BuildFolder()` is its `ocutalon/csp/`; the planted `main-ZZSTALE0.js` is removed, `zz-admin-note.txt` stays and the served `index.html` equals the loaded copy's.
- Initial web bundle with the reload handler: 883.39 kB, against 882.45 kB without it (+0.94 kB; cap 921 kB).

## The rehearsal's record section (to fill)

`release/upgrade-harness.sh build|settings|seed|upgrade|restart|storage|report|down --rehearsal --previous v1.0.9 --record <temp file>`, tag e36s7h. Expected: `Result: pass`, and the `stale files` row passes with the plant note (`main-ZZSTALE0.js was planted in the served folder before the upgrade, standing in for an earlier upgrade's leftover; every mode plants it`).

## The served and build lists (to fill)

After the upgrade and after the restart: `diff <build list> <served list>` is empty (the build list is `find src/ocutalon/csp -type f | LC_ALL=C sort`).

## The mutation run's `stale files` row (to fill)

With the `RemoveStaleBundle` call removed from `Web.Prepare`, tag e36s7m, `build`, `seed`, `upgrade`, `report`, `down`: the row fails and names `./main-JCJUH3RN.js` and `./main-ZZSTALE0.js`.
