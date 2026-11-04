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
| 2026-10-20 | `fcdd9e9` (Story 0.8's head) | self-hosted x64 runner `ocutalon-ci-2` (Rule 21), Docker engine x86_64, two jobs at once | 0 | 150 | `ci` run 39359136309, job `iris (browser)`, line `FIRST-START engine=x86_64 build=0s ready=150s`; no `WARN` line |
| 2026-10-20 | `916ff92` (Story 0.10's build commit) | self-hosted x64 runner `ocutalon-ci-1` (Rule 21), Docker engine x86_64, two jobs at once | 1 | 177 | `ci` run 39411120021, job `iris (browser)`, line `FIRST-START engine=x86_64 build=1s ready=177s`; no `WARN` line |
| 2026-10-21 | `b6459b8` (Epic 0's head, merged as `67989bb`) | self-hosted x64 runner `ocutalon-ci-1` (Rule 21: 4 vCPU, 8 GB), Docker engine x86_64, two jobs at once | 1 | 160 | `ci` run 39545049306, job `iris (browser)` 119041216742, line `FIRST-START engine=x86_64 build=1s ready=160s`; no `WARN` line (read from the run's log at Story 10.2's plan). **This row is the README's figure.** |

Story 0.8's x64 figure is measured: `ready` 150 s (about 2.5 minutes), well under the 720 s threshold. Its `iris (browser)` job took 8 min 43 s (the `browser` group 505 s: `live:demo-path` 161 s, `live:sign-in` 173 s, `live:bundle-folder` 171 s), and the whole `ci` run 23 min 39 s from creation to the last job. `build` is 0 s because the runner's layer cache already held every layer, so it is not quoted. The README's figure is the row for Epic 0's merge head (read at Story 10.2's plan); this row is the earlier reading it is compared with.

Story 0.10's x64 figure is measured: `ready` 177 s (about 3 minutes), 27 s more than Story 0.8's 150 s. The first start now also loads the story's new classes, creates the demo namespace OCUORDERS and starts its production (`STEP Demo` took 1.3 s, and the whole first start 6 s more, on the developer machine); how much of the 27 s that is, against runner variance between two single runs on two runner services, was not measured `(inference)`. Its `iris (browser)` job took 9 min 40 s (the `browser` group 556 s: `live:demo-path` 189 s, `live:sign-in` 182 s, `live:bundle-folder` 184 s), and the whole `ci` run 25 min 22 s from creation to the last job. `build` is 1 s because the runner's layer cache already held the layers, so it is not quoted.

How to read a figure: `gh run list --commit <sha>`, then `gh run view <ci run> --log | grep -E 'FIRST-START|WARN first start|STEP [1-6] |DEMO-PATH|UNIT live:demo-path|GROUP browser'`. Add the `iris (browser)` job's duration and the run's wall-clock beside the row.

## The rule

A ready time over about 12 minutes is raised to the author through the Contest Planner. The author decides on AD-23's code-in-image option (moving the compiled code database into the image, which is a spine update). It is a decision, not a test failure, so the unit warns and still runs the specs. A start that is not ready within the unit's wait (up to 900 s for the start's log and up to 60 s more for the health check, never beyond the run's deadline) fails the unit instead, and the log names the seconds waited.
