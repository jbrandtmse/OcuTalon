# Epic 0 notes for the README

Facts from Epic 0 that Story 10.2 quotes in the README. Each is read from the output of a unit of the pipeline, with its source beside it, and never estimated by hand.

## The first start (AD-23)

The demo-path unit (`live:demo-path`, Story 0.8) times the first start of the real package in a fresh throwaway and prints one line:

`FIRST-START engine=<arch> build=<s>s ready=<s>s`

- `ready` is what a judge waits for: from `docker compose up` of a built image until Docker reports `healthy`. It covers the after-start install and the ready marker.
- `build` is the image build. It uses the machine's layer cache, so on the runner it is not a judge's cold build and is not quoted.
- When `ready` is over 720 s, the log also holds `WARN first start <s> s is over 12 minutes: raise it to the author (AD-23)`.

| UTC date | Commit | Host and Docker engine | build s | ready s | Source |
| --- | --- | --- | --- | --- | --- |
| 2026-10-20 | `a375972` plus the Story 0.8 working tree (the implement stage; the lead commits) | Apple silicon laptop, Docker Desktop, engine aarch64 (server 29.7.2) | 1 | 53 | `ci/iris.sh live demo-path`, first local run; three more runs the same hour gave ready 47, 53 and 47 |
| | | | | | QA: this story's head on the x64 runner (engine x86_64), from the `ci` run's `iris (browser)` log |
| | | | | | Lead: Epic 0's merge head on the x64 runner, at the epic close. **This row is the README's figure.** |

Until an x64 row exists: about 3 minutes `(inference)`, from Story 0.7's ready stack of 174 s on the runner (first real run, run 39338702672).

How to read a figure: `gh run list --commit <sha>`, then `gh run view <ci run> --log | grep -E 'FIRST-START|WARN first start|STEP [1-6] |DEMO-PATH|UNIT live:demo-path|GROUP browser'`. Add the `iris (browser)` job's duration and the run's wall-clock beside the row.

## The rule

A ready time over about 12 minutes is raised to the author through the Contest Planner. The author decides on AD-23's code-in-image option (moving the compiled code database into the image, which is a spine update). It is a decision, not a test failure, so the unit warns and still runs the specs. A start that is not ready within the unit's wait (900 s, and never beyond the run's deadline) fails the unit instead, and the log names the seconds waited.
