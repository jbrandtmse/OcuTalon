# Story 33.1 Task 0: changing the instance time zone at run time (measured)

- **Date:** 2026-11-03, 20:13 to 20:21 UTC
- **Target:** MCP server `ocutalon-slot-c`, namespace `OCUTALON`. `iris_server_info` reported: `IRIS for UNIX (Ubuntu Server LTS for ARM64 Containers) 2026.3.0AI (Build 154U) Thu Sep 24 2026`.
- **Repo:** the Epic 33 worktree. Nothing was changed there (`git status --short` is empty).
- **Scratch sources:** the stage scratch folder (outside the repository) holds `Probe.cls`, `Service.cls`, `Production.cls` and `Zone.cls`. They were loaded into slot C, used, and deleted.

## Verdict

**Changing the zone at run time works.** `$SYSTEM.Process.TimeZone(<IANA name>)`, called inside a job that inherited the container's `TZ`, makes the code that `OcuTalon.Bridge.Time` and `OcuTalon.Data.Time` already run convert in the named zone straight away. That code is `$ZDATETIMEH(utc,3,7)`, `$ZDATETIME(h,-3)` and `$ZDATETIMEH(local,3,1)`.

- **DST:** all 12 instants on both sides of the 2026 changes in Berlin, Los Angeles and Sydney came out right.
- **Speed:** a long-running background job and a running business host both picked up a changed zone on their next pass. That took 0.07 to 1.16 s, always within one loop interval. Nothing was restarted.
- **No restart fallback is needed.** Neither the "process zone with a restart" option nor the veto item applies.

## Environment facts (observed)

- The slot C container has no `TZ`. `$SYSTEM.Util.GetEnviron("TZ")` returned `""` in the MCP process, in every `JOB`, and in the business host (`OnInit`). `$SYSTEM.Process.TimeZone()` returned `-1` (undefined) in the business host. So the zone these jobs inherit here is UTC. The online demo uses US Eastern, which comes from the spine and was not measured here.
- No production was running in `OCUTALON` before I started: `GetProductionStatus` gave name `""` and state `2` (Stopped). `^Ens.Configuration("csp","LastProduction")` was `OCUTALONPKG.FoundationProduction`.
- tzdata is in the image. `/usr/share/zoneinfo` exists, and so do `/usr/share/zoneinfo/Europe/Berlin` and `/etc/localtime`.
- Python facts, from inside a `JOB`: Embedded Python 3.12.3, `zoneinfo.TZPATH` starts with `/usr/share/zoneinfo`, `available_timezones()` returns 498 zones, and the `tzdata` pip package is not installed (it isn't needed, because the system tzdata is used). `%SYS.Python` works in a background job.

## Candidate A: `$SYSTEM.Process.TimeZone(name)` (sets the process `TZ` at run time)

### A1. DST correctness

**What ran:** `Probe.Static()`, started with `Job ##class(OcuTalon.Scratch.E33T0.Probe).Static()::5` as job 2143042. The job started with `TZ=""`. For each case it ran:

- `Do $SYSTEM.Process.TimeZone(zone)`
- the real `OcuTalon.Bridge.Time.ToLocal`, `LocalDate`, `DayStartUtc` and `DayEndUtc`
- the real `OcuTalon.Data.Time.ToLocal` and `FromLocal(expectedLocal)`
- `$SYSTEM.Util.IsDST`

**Results:** in every row, Bridge.ToLocal and Data.ToLocal both equalled the expected local time, and Embedded Python `zoneinfo` gave the same.

| zone | UTC | expected local | Bridge.ToLocal / Data.ToLocal | IsDST | DayStartUtc .. DayEndUtc of that local date |
|---|---|---|---|---|---|
| Europe/Berlin | 2026-03-29T00:59:59Z | 03-29T01:59:59 | 03-29T01:59:59 | 0 | 03-28T23:00:00Z .. 03-29T22:00:00Z (23 h) |
| Europe/Berlin | 2026-03-29T01:00:00Z | 03-29T03:00:00 | 03-29T03:00:00 | 1 | same |
| Europe/Berlin | 2026-10-25T00:59:59Z | 10-25T02:59:59 | 10-25T02:59:59 | 1 | 10-24T22:00:00Z .. 10-25T23:00:00Z (25 h) |
| Europe/Berlin | 2026-10-25T01:00:00Z | 10-25T02:00:00 | 10-25T02:00:00 | 0 | same |
| America/Los_Angeles | 2026-03-08T09:59:59Z | 03-08T01:59:59 | 03-08T01:59:59 | 0 | 03-08T08:00:00Z .. 03-09T07:00:00Z (23 h) |
| America/Los_Angeles | 2026-03-08T10:00:00Z | 03-08T03:00:00 | 03-08T03:00:00 | 1 | same |
| America/Los_Angeles | 2026-11-01T08:59:59Z | 11-01T01:59:59 | 11-01T01:59:59 | 1 | 11-01T07:00:00Z .. 11-02T08:00:00Z (25 h) |
| America/Los_Angeles | 2026-11-01T09:00:00Z | 11-01T01:00:00 | 11-01T01:00:00 | 0 | same |
| Australia/Sydney | 2026-04-04T15:59:59Z | 04-05T02:59:59 | 04-05T02:59:59 | 1 | 04-04T13:00:00Z .. 04-05T14:00:00Z (25 h) |
| Australia/Sydney | 2026-04-04T16:00:00Z | 04-05T02:00:00 | 04-05T02:00:00 | 0 | same |
| Australia/Sydney | 2026-10-03T15:59:59Z | 10-04T01:59:59 | 10-04T01:59:59 | 0 | 10-03T14:00:00Z .. 10-04T13:00:00Z (23 h) |
| Australia/Sydney | 2026-10-03T16:00:00Z | 10-04T03:00:00 | 10-04T03:00:00 | 1 | same |

- `LocalDate` equalled the date part in every row.
- `GetEnviron("TZ")` showed the zone just set, so `Process.TimeZone` writes the process's `TZ` environment variable.
- `FromLocal(expected)` returned the original UTC in every row outside the repeated (overlap) hour.

### A1a. Side finding: `Data.Time.FromLocal` and the repeated hour

`FromLocal` chooses between the two instants of the repeated hour (the hour the fall-back change repeats) depending on what the process converted just before. Its own doc comment says "read at its first instant".

In `Static()`, `FromLocal` of a repeated-hour time returned the second instant (standard time) in all 3 zones. Python fold 0 gives the first instant:

- Berlin `10-25T02:59:59` gave `01:59:59Z`. Python gave `00:59:59Z`.
- LA `11-01T01:59:59` gave `09:59:59Z`. Python gave `08:59:59Z`.
- Sydney `04-05T02:59:59` gave `16:59:59Z`. Python gave `15:59:59Z`.

`Probe.Ambig()` (job 2143191) called `FromLocal` of the repeated-hour time after different preceding calls:

| zone, local | fresh | after winter ToLocal | after summer ToLocal | after winter FromLocal | after summer FromLocal | Python fold 0 |
|---|---|---|---|---|---|---|
| America/New_York 2026-11-01T01:30:00 | 05:30Z | 05:30Z | 05:30Z | **06:30Z** | 05:30Z | 05:30Z |
| Europe/Berlin 2026-10-25T02:30:00 | **01:30Z** | **01:30Z** | **01:30Z** | **01:30Z** | 00:30Z | 00:30Z |

The result depends on what the process did before. This looks like libc `mktime`'s guess of whether DST is in effect (inference). It is not caused by changing the zone at run time, but the story touching `Data.Time` should know about it. `Test.Schedule.ReminderZone` asserts the New York first-instant case, which passes only because of the order of the calls before it (inference).

### A2. A running background job picks up a change (no restart)

**What ran:**

- `Probe.Loop("apply",300,1)` as job 2143192. Once a second it reads the candidate source (`$Get(^OcuTalonScratchE33T0("zone"))`). If the value differs from the zone it last applied, it calls `Do $SYSTEM.Process.TimeZone(zone)`. Then it logs `Bridge.Time.ToLocal` and `Data.Time.ToLocal` of `2026-01-15T12:00:00Z` (winter) and `2026-07-15T12:00:00Z` (summer), `Data.Time.Zone()`, and Python `zoneinfo` of the stored name.
- `Probe.Loop("noapply",300,0)` as job 2143193. It is the same loop but never calls `Process.TimeZone`.
- The zone was changed from the MCP process with `Set ^OcuTalonScratchE33T0("zone")=...`.

| change (written at, UTC) | apply job, first sample with the new zone | delay | winter / summer local |
|---|---|---|---|
| start: `""` | 20:16:01.927 | n/a | 12:00 / 12:00 (inherited UTC) |
| Europe/Berlin @ 20:16:10.913 | 20:16:10.986 | 0.07 s | 13:00 / 14:00 |
| Australia/Sydney @ 20:16:44.889 | 20:16:45.240 | 0.35 s | 23:00 / 22:00 |
| America/Los_Angeles @ 20:17:09.086 | 20:17:09.359 | 0.27 s | 04:00 / 05:00 |
| `""` @ 20:17:32.259 | 20:17:32.474 | 0.22 s | 12:00 / 12:00 (`Process.TimeZone("")`, which is UTC) |
| `Mars/Olympus` (invalid) @ 20:17:50.322 | 20:17:50.607 | 0.29 s | 12:00 / 12:00, **silently UTC, with no error** |

- In every sample, Bridge.Time and Data.Time agreed, and `Data.Time.Zone()` reported the applied name.
- The **noapply** job stayed at 12:00 / 12:00 and `Zone()=UTC` throughout. Without a process-level apply, the inherited zone never changes. Python `zoneinfo` with the name passed in explicitly did follow the stored name in that job (14:00, 22:00, 05:00).
- The invalid name raised `ZoneInfoNotFoundError` in Python, but `Process.TimeZone` accepted it and converted as UTC.

### A3. A running business host picks up a change (no restart)

**Setup:** no production was running, so I started my own scratch production `OcuTalon.Scratch.E33T0.Production`. It has one item, `ZoneProbe`: class `OcuTalon.Scratch.E33T0.Service`, `Ens.InboundAdapter`, `CallInterval=2`. Its `OnProcessInput` runs the same `Sample` as the apply job.

- Item job: 2143225, started 20:16:17.
- `OnInit` read `TZ` env `""` and `Process.TimeZone()` `-1`.

| change | host sample with the new zone | delay |
|---|---|---|
| Europe/Berlin (set before start) | 20:16:17.108, first sample: 13:00 / 14:00 | n/a |
| Australia/Sydney @ 20:16:44.889 | 20:16:45.250: 23:00 / 22:00 | 0.36 s |
| America/Los_Angeles @ 20:17:09.086 | 20:17:09.333: 04:00 / 05:00 | 0.25 s |
| `""` @ 20:17:32.259 | 20:17:33.420: 12:00 / 12:00 | 1.16 s |
| Mars/Olympus @ 20:17:50.322 | 20:17:51.480: 12:00 / 12:00 (silently UTC) | 1.16 s |

The production was then stopped (`StopProduction(30,1)`). Background jobs and production jobs inherit the process environment the same way: A4 below and the AD-18 build-154 measurement both show it (inference that the mechanism is identical).

### A4. A job that inherited a non-empty `TZ` can override it and put it back

Slot C's container has no `TZ`, so I made one job inherit a named zone from its parent:

1. `Probe.Parent()` (job 2143536) ran `Process.TimeZone("America/New_York")`, then `JOB`bed `Probe.Child()` (job 2143537).
2. The child **started with `TZ=America/New_York`**, so it inherited the parent's environment, and `Data.Time.ToLocal(2026-07-15T12:00:00Z)` gave `08:00:00`.
3. The child ran `Process.TimeZone("Europe/Berlin")`. The call returned the inherited `America/New_York`, and ToLocal gave `14:00:00`.
4. Putting the returned zone back restored `TZ=America/New_York`, and ToLocal gave `08:00:00`.

The same applies to a production job that inherited the container's `TZ=America/New_York` (inference). The old zone can be put back exactly because `Process.TimeZone(new)` returns it.

### A5. Cost per call

Measured in a `JOB`, 20,000 iterations each (2,000 for the Python and SQL lines), on one ARM64 container:

| operation | us per call |
|---|---|
| `Bridge.Time.ToLocal`, zone fixed | 0.50 |
| global `$Get` of the zone + compare + `ToLocal` (apply only on change) | 0.56 |
| `Process.TimeZone(same name)` on every call + `ToLocal` | 0.67 |
| `Process.TimeZone(alternating names)` + `ToLocal` (a real switch every call) | 3.86 |
| bare global `$Get` | 0.04 |
| persistent bridge table row, `NameGetStored(1)` | 0.21 |
| persistent bridge table row, `%OpenId(1,0)` + `.Name` | 2.45 |
| embedded SQL `SELECT Name ... WHERE ID=1` | 6.01 |
| host setting via `Ens.Director.GetItemSettingValue(prod||item,"Host",setting)` | 8.45 |
| Embedded Python `zoneinfo` conversion | 6.14 |

**Image needs:** nothing new. The system tzdata at `/usr/share/zoneinfo` is already there.

**Verdict A: works.** The named zone and DST are both correct. A running job and a running host apply a change on their next conversion without a restart. It costs under 1 us when the zone has not changed.

## Candidate B: Embedded Python `zoneinfo.ZoneInfo(name)`

**What ran:** `Probe.PyLocal(utc, zone)` and `Probe.PyUtc(local, zone)`, both `[Language = python]`, in the same jobs:

```python
datetime.strptime(utc, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).astimezone(ZoneInfo(zone))
```

**Results:**

- All 12 DST cases came out right.
- The stored name was picked up within one loop pass even in the noapply job, because the name is an argument and there is no process state.
- The repeated hour is handled the same way every time (fold 0 gives the first instant).
- An invalid name raises `ZoneInfoNotFoundError`.
- It costs 6.14 us per call and imports fine in a background job.

**Drawbacks:**

- The spine forbids `[Language = python]` methods ("`.py` resources ... imported with `%SYS.Python.Import`"), so this would need a `.py` resource for the bridge and another for the product.
- `ToLocal`, `LocalDate`, `DayStartUtc`, `DayEndUtc`, `FromLocal` and `ForMessage` would all have to be rewritten around Python.
- It is about 12 times slower than candidate A.

**Verdict B: it works, but it is not the recommended run-time source.** It is useful as the **validator** of a zone name before the name is stored (or use the file check in the recommendation).

## Candidate C: `$ZTIMEZONE` and `%SYSTEM.Util.UTCtoLocalWithZTIMEZONE`

**What ran:** in `Static()`, with the process zone cleared (`Process.TimeZone("")`), I set `$ZTIMEZONE` to 0, -60 and 480. For `2026-01-15T12:00:00Z` and `2026-07-15T12:00:00Z` I then read:

- `Bridge.Time.ToLocal`
- `$ZDT($ZDTH(h,-3),3)`
- `UTCtoLocalWithZTIMEZONE(h)`

**Results:**

- `$HOROLOG` moved: at `$ZTIMEZONE=-60` it read 21:14:57 against UTC 20:14:57, and at 480 it read 12:14:57.
- **Every conversion of an explicit timestamp stayed at 12:00:00** for all three values. That includes `UTCtoLocalWithZTIMEZONE`, which on this build is just `$ZDATETIMEH(ts,-3)` (irislib source).
- `$ZTIMEZONE` is also a fixed offset, with no DST rules.

**Verdict C: does not work.** It changes only `$H`.

## Candidate D: other ways to hold the value (what the bridge can store and read)

**D1. A host setting (production item setting).**

- **What ran:** the scratch service declared `InstanceZone` (SETTINGS category Bridge). I wrote a System Default Settings row for `OcuTalon.Scratch.E33T0.Production||ZoneProbe||*||InstanceZone` = `Europe/Berlin`, restarted the scratch production (item job 2143736), and at 20:20:17.300 changed the row to `Australia/Sydney`.
- **Results:**
  - The host's **in-memory property `..InstanceZone` stayed `Europe/Berlin`** in every sample until the stop at 20:20:46, which is 18+ s later. Applying it would take an item restart, or an Update that restarts the item (the restart part is inference).
  - **`Ens.Director.GetItemSettingValue(...)`** (what `Bridge.Ext.Accessor.ValueFor` calls) returned `Australia/Sydney` on the host's next pass at 20:20:17.986, **0.69 s** later. It costs 8.45 us per call, needs an active or named production, and only reads item settings.
- **Verdict D1:** the live lookup works, but it costs 15 to 40 times as much as a table read and depends on the production. It is not usable from a page or REST job when no production is active.

**D2. A bridge table row.**

- **What ran:** a scratch persistent class `OcuTalon.Scratch.E33T0.Zone` with property `Name`.
- **Results:** reading `NameGetStored(1)` costs 0.21 us. A saved row is ordinary global data, visible to every process at once (inference from the global measurement in A2, which saw a change within 0.07 to 0.36 s, bounded by the 1 s sample interval).
- **Verdict D2:** works, and it is the cheapest form that the spine allows. The spine's Settings row says "Bridge values from host settings and bridge tables; ... never read globals directly".

**D3. A Config Store entry (AD-19).**

- **Not measured.** From the irislib source: entries need a registered descriptor class for the area and type (`%SYS.ConfigStore.DescriptorManager.GetDescriptorClass`, via `ConfigStore.DescriptorProjection`). Editing needs the `%Admin_ConfigStore` resource, and `Use`/`GetDetails` call `AuditUsage`.
- **Verdict D3:** it is meant for connection configurations and is heavy for one zone name. Not recommended (inference).

## Recommendation for the spine

The single run-time source is a **bridge value held in a bridge table**. The process zone is applied from it on each conversion.

- **What and where:** one zone name (an IANA name such as `Europe/Berlin`, or empty for "use the container's `TZ`") is stored as a row or property of a bridge persistent class in `OcuTalon.Bridge.*`. An example is a one-row `OcuTalon.Bridge.Data.<Settings>`, or a property on an existing bridge settings table. `OcuTalon.Bridge.Time` owns it through two methods:
  - **`Zone()`** reads the stored name with `<Prop>GetStored(id)`, costing 0.21 us and no object open.
  - **`SetZone(name)`** is the one writer.
- **Who writes it:** the settings page, through the product's settings API, calls `Bridge.Time.SetZone(name)` and audits it as a `Settings` entry (AD-17). `SetZone` must check the name before it stores it, because `Process.TimeZone` accepts an unknown name and **silently converts as UTC** (measured). The check is a name pattern (letters, `/`, `_`, `-`, `+` and digits, with no `..`) plus `##class(%File).Exists("/usr/share/zoneinfo/"_name)`, or the Python `zoneinfo` check through a `.py` resource. Empty means "use the container's `TZ`".
- **How both classes read it and convert:**
  - `OcuTalon.Bridge.Time` gets one method, `Apply()`, called at the top of every zone-dependent method: `ToLocal`, `LocalDate`, `DayStartUtc` and `DayEndUtc`. `Apply()` reads `Zone()` and compares it with the zone this process last applied, kept process-private: a `%`-variable or a process-private global, not a persistent global.
    - When they differ and the name is not empty, it calls `$SYSTEM.Process.TimeZone(name)`. On the process's first apply it keeps the return value, which is the inherited `TZ` (`-1` means none).
    - When the stored name becomes empty after a non-empty apply, it puts the inherited `TZ` back: `-1` becomes `""`, as `Test.Bridge.ZoneCase.PutZone` does today (measured in A4).
    - When the process has never applied a zone and the stored name is empty, it does nothing. That keeps today's behaviour, and the `ZoneCase` tests that set the process zone directly keep working while the bridge value is empty.
  - `OcuTalon.Data.Time` calls `##class(OcuTalon.Bridge.Time).Apply()` at the top of `ToLocal`, `FromLocal` and `ForMessage`, and its `Zone()` returns `Bridge.Time.Zone()` when that is non-empty. The dependency runs from OcuTalon to the bridge, which AD-2 allows.
  - After `Apply()` the existing conversions are unchanged (`$ZDATETIMEH(utc,3,7)`, `$ZDATETIME(h,-3)` and `$ZDATETIMEH(local,3,1)`), so the agreement test across DST stays valid. `NowUtc`, `Seconds`, `AddSeconds`, `PlusSeconds`, `SecondsUntil`, `MsSince` and `DaysCutoff` don't depend on the zone and need no `Apply()`.
- **How fast a change applies:** on the next conversion in every job, in production hosts, background jobs, and web or REST processes alike, with no restart of IRIS, the production or the job. Measured: 0.07 to 0.36 s in a job sampling every second, and 0.25 to 1.16 s in a host with `CallInterval=2`. A job that converts nothing simply applies the zone on its next conversion. That is far inside the one-minute bound.
- **Cost and caching:** there is no time-based cache and none is needed. Reading on every call costs about 0.06 us above a bare `ToLocal` (0.56 against 0.50 us; a table `GetStored` read is 0.21 us). Only an actual zone switch costs about 3.9 us, and that happens once per process per change.
- **Effects and notes for the story:**
  - `Process.TimeZone` is process-wide, so `$HOROLOG` and every local-time function in that job follow the instance zone. That is the intent. `$ZTIMESTAMP` doesn't depend on `TZ` (inference, from IRIS documentation; not measured in isolation).
  - Tests that set a zone should set the bridge value, or keep it empty and keep using `ZoneCase`.
  - The `FromLocal` repeated-hour order dependence (A1a) is separate from this decision. A story that relies on "first instant" should pin it, for example by trying both offsets explicitly, or call it out.
- **No fallback:** because a run-time way works, the "process zone with a restart" fallback, its settings-page and Visual Trace labels, and the veto item are not needed.

## Cleanup done (slot C, `OCUTALON`)

- **Jobs:** all scratch jobs (2143042, 2143191, 2143192, 2143193, 2143536, 2143537, 2143743) ended. The loops stopped on `^OcuTalonScratchE33T0("stop")` at 20:17:58. `^$JOB` shows none of them, and none of the running processes is in a `Scratch` routine.
- **Scratch production:** stopped twice, at 20:17:58 and 20:20:46, each time with `StopProduction(30,1)`. Afterwards `GetProductionStatus` gave name `""` and state `2`, as before. I deleted `Ens.Config.Production` `OcuTalon.Scratch.E33T0.Production`, which left 0 item rows. I deleted the System Default Settings row `OcuTalon.Scratch.E33T0.Production||ZoneProbe||*||InstanceZone`, which left 0 rows for that production. I restored `^Ens.Configuration("csp","LastProduction")` to `OCUTALONPKG.FoundationProduction`, because `StartProduction` had changed it. I deleted the 20 `Ens_Util.Log` rows 90 to 109, all from my two starts and stops (checked one by one). `^Ens.Runtime` is not defined.
- **Classes:** I killed the `OcuTalon.Scratch.E33T0.Zone` extent, then deleted `OcuTalon.Scratch.E33T0.Probe`, `.Service`, `.Production` and `.Zone`. Checked: 0 class definitions starting with `OcuTalon.Scratch`, no compiled class, and no `^rOBJ` routine.
- **Global:** killed `^OcuTalonScratchE33T0`. `$Data` is 0.
- **Unchanged:** no instance-wide setting, container `TZ`, clock or CPF was touched. Zone changes happened only inside my own scratch jobs and the scratch host. No throwaway container was used (`ci/iris.sh` was not run).
- **Repository:** untouched. `git status --short` in the worktree is empty.
