# Install OcuTalon with IPM

This page installs OcuTalon into an IRIS instance you already run, with the InterSystems Package Manager (IPM). The install takes two commands of the same text, one after the other. The first one ends early on purpose and tells you what to do next. The second one gives a running OcuTalon with demo mode off. The page opens with the install from the community package registry; the install from the package folder, for developers, comes after it.

## What you need

- An InterSystems IRIS for AI Hub instance, build 154, with IPM 0.10.10 loaded in %SYS and enabled for USER (the examples start there). Build 109, which the Early Access portal now offers in place of build 154, has not been tested with the IPM install yet.
- For the registry install: an instance that can reach the community package registry.

OcuTalon needs no other package: the one package `ocutalon` holds the bridge too.

## Install from the package registry

### Point IPM at the registry

In an IRIS terminal in %SYS, run:

```
zpm "enable -community"
```

The command first deletes the repositories configured in %SYS (`repo -delete-all` in its output), then adds the community registry. This is its output, with the terminal's colour codes removed:

```
Version of IPM in current namespace:
%SYS> zpm 0.10.10

RUNNING command: "repo -delete-all"
Command "repo -delete-all" finished successfull

RUNNING command: "repo -reset-defaults"
WARNING: Using -password via the CLI is insecure. Use -password-stdin or -password-env.
registry
	Source: 			https://pm.community.intersystems.com
	Enabled?			Yes
	Available?			Yes
	Use for Snapshots?		Yes
	Use for Prereleases?		Yes
	Is Read-Only?			No
	Default Deployment Registry? 	No

registry
	Source: 			https://pm.community.intersystems.com
	Enabled?			Yes
	Available?			Yes
	Use for Snapshots?		Yes
	Use for Prereleases?		Yes
	Is Read-Only?			No
	Default Deployment Registry? 	No

Command "repo -reset-defaults" finished successfull

RUNNING command: "enable -map -repos -globally"
Version of IPM in current namespace:
%SYS> zpm 0.10.10
Skipping IPM mapping of %SYS - IPM already installed.
Mapping %IPM package in %SYS equivalently to HSCUSTOM
Mapping %IPM.* routines in %SYS equivalently to HSCUSTOM
Skipping IPM mapping of HSLIB - IPM already installed.
Mapping %IPM package in %SYS equivalently to HSSYS
Mapping %IPM.* routines in %SYS equivalently to HSSYS
Mapping %IPM package in %SYS equivalently to HSSYSLOCALTEMP
Mapping %IPM.* routines in %SYS equivalently to HSSYSLOCALTEMP
Mapping %IPM package in %SYS equivalently to USER
Mapping %IPM.* routines in %SYS equivalently to USER
Skipping repository mapping of %SYS - IPM not mapped from source namespace.
Skipping repository mapping of HSCUSTOM - IPM not mapped from source namespace.
Skipping repository mapping of HSLIB - IPM not mapped from source namespace.
Skipping repository mapping of HSSYS - IPM not mapped from source namespace.
Skipping repository mapping of HSSYSLOCALTEMP - IPM not mapped from source namespace.
Mapping IPM repository in %SYS equivalently to USER
Done.

%SYS>           zpm 0.10.10
HSLIB>          zpm 0.10.5-SNAPSHOT
HSCUSTOM>       zpm 0.10.10
                Installed In: %SYS
HSSYS>          zpm 0.10.10
                Installed In: %SYS
HSSYSLOCALTEMP> zpm 0.10.10
                Installed In: %SYS
USER>           zpm 0.10.10
                Installed In: %SYS
https://pm.community.intersystems.com - 1.0.0
Command "enable -map -repos -globally" finished successfull
```

### The first command

Open an IRIS terminal in USER and run:

```
zpm "install ocutalon"
```

OcuTalon needs an Interoperability-enabled namespace to start from, and USER is one on both IRIS for Health and IRIS build 154. In a namespace without Interoperability, such as %SYS, IPM refuses the package before it changes anything and prints this line:

```
ERROR! This module requires an interoperability-enabled namespace. %SYS is not interoperability-enabled.
```

If you see it, run the command in USER instead.

The run in USER ends early by design. It creates the namespace OCUTALON with its four databases and the mappings OcuTalon needs, maps IPM and IPM's repository definitions into it, and then stops with an error that is the next instruction. It leaves no OcuTalon code installed: IPM removes the one class it compiles for this run when the run stops. This is the output of that run on a new instance, with the terminal's colour codes and banner removed:

```

USER>

Building dependency graph...Done.
[USER|ocutalon]	Initialize START
Compilation started on 11/03/2026 07:21:52
Compiling class OcuTalon.Install.Ipm
Compiling routine OcuTalon.Install.Ipm.1
Compilation finished successfully in 0.004s.

[ocutalon]	Initialize FAILURE
ERROR! OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.
USER>
```

The last line, `ERROR! OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.`, is not a failure to fix. It is the stop of this first run. Running the first command again in USER gives the same stop and changes nothing. In OCUTALON the same command is the second run.

OCUTALON shares the repositories of the namespace where you ran the first command, so a repository added or removed in either namespace changes both.

### The second command

Do what the last line says. Switch to OCUTALON and run the same command:

```
zn "OCUTALON"
zpm "install ocutalon"
```

This run loads and compiles OcuTalon, installs the web page, and runs the installer steps one after another. Each step prints one `STEP <name> OK` line, and a step can add `WARN <name> <text>` lines after it; a warning does not fail the step. A step that fails prints `STEP <name> FAILED <text>` and the command ends with `ERROR! <text>`; the code stays installed, and the same command runs the steps again. When the last line is `Activate SUCCESS`, OcuTalon runs. This is the output of that run, with the colour codes and the terminal banner removed:

```

OCUTALON>

Building dependency graph...Done.
[OCUTALON|ocutalon]	Initialize START
Compilation started on 11/03/2026 07:21:55
Compiling class OcuTalon.Install.Ipm
Compiling routine OcuTalon.Install.Ipm.1
Compilation finished successfully in 0.002s.

[OCUTALON|ocutalon]	Initialize SUCCESS
[OCUTALON|ocutalon]	Reload START (/tmp/ocutalon-repo/ocutalon-0.1.0/)
[OCUTALON|ocutalon]	Reload SUCCESS
[ocutalon]	Module object refreshed.
[OCUTALON|ocutalon]	Validate START
[OCUTALON|ocutalon]	Validate SUCCESS
[OCUTALON|ocutalon]	Compile START
[OCUTALON|ocutalon]	Compile SUCCESS
[OCUTALON|ocutalon]	Activate START
[OCUTALON|ocutalon]	Configure START
STEP Bridge.Installer OK 0.1s
STEP Public OK 0.0s
STEP Roles OK 0.0s
STEP Users OK 0.0s
STEP Web OK 0.0s
STEP SSL OK 0.0s
STEP Tasks OK 0.1s
STEP Demo OK 0.1s
STEP Provider OK 0.1s
STEP Audit OK 0.0s
STEP Telegram OK 0.0s
STEP Memory OK 0.1s
07:22:35.460:Ens.Director: Production 'OcuTalon.Production' starting...
07:22:35.567:Ens.Director: Production 'OcuTalon.Production' started.
STEP Production OK 1.2s
STEP Reconcile OK 0.2s
STEP PrivateData OK 0.1s
STEP Ready OK 0.0s
[OCUTALON|ocutalon]	Configure SUCCESS
[OCUTALON|ocutalon]	Activate SUCCESS
OCUTALON>
```

Until the package is published, these outputs come from the same package installed from a local IPM repository.

The installer marks the OcuTalon production to start with the instance, so it comes back after an instance restart. It changes no service of the instance and no namespace or database it did not create.

If a step fails after the code has loaded, the command reports the failure and names the step (`STEP <name> FAILED: the new OcuTalon code is installed. Run the same install command again.`, then IPM's `ERROR!` line), the new code stays installed, and running the same command again finishes the install; a failure while IPM loads or compiles the code is rolled back and the previous version keeps running.

## Install from the package folder (for developers)

This install needs the OcuTalon package folder. That is the `src` folder of the OcuTalon repository, with the web page built once on any machine that has Node.js 24.15 or later:

```
npm --prefix web ci
npm --prefix web run build
```

The instance needs no Node.js. Copy the `src` folder to a place the instance can read. The examples below call it `/opt/ocutalon-ipm/src`; use your own folder in its place.

### The first command

Open an IRIS terminal in USER and load the package:

```
zpm "load /opt/ocutalon-ipm/src"
```

The advice about the namespace above holds here too. This is the output of that run on a new instance, with the terminal's colour codes removed:

```

Node: be3ea7777581, Instance: IRIS

USER>

Building dependency graph...Done.
[USER|ocutalon]	Initialize START
Compilation started on 10/31/2026 00:34:20
Compiling class OcuTalon.Install.Ipm
Compiling routine OcuTalon.Install.Ipm.1
Compilation finished successfully in 0.002s.

[ocutalon]	Initialize FAILURE
ERROR! OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.
USER>
```

The last line, `ERROR! OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.`, is the stop of this first run, as above.

### The second command

Switch to OCUTALON and run the same command:

```
zn "OCUTALON"
zpm "load /opt/ocutalon-ipm/src"
```

It runs the same installer steps as the second command of the registry install. This is the output of that run, with the colour codes removed:

```

Node: be3ea7777581, Instance: IRIS

OCUTALON>

Building dependency graph...Done.
[OCUTALON|ocutalon]	Initialize START
Compilation started on 10/31/2026 00:34:34
Compiling class OcuTalon.Install.Ipm
Compiling routine OcuTalon.Install.Ipm.1
Compilation finished successfully in 0.002s.

[OCUTALON|ocutalon]	Initialize SUCCESS
[OCUTALON|ocutalon]	Reload START (/opt/ocutalon-ipm/src/)
[OCUTALON|ocutalon]	Reload SUCCESS
[ocutalon]	Module object refreshed.
[OCUTALON|ocutalon]	Validate START
[OCUTALON|ocutalon]	Validate SUCCESS
[OCUTALON|ocutalon]	Compile START
[OCUTALON|ocutalon]	Compile SUCCESS
[OCUTALON|ocutalon]	Activate START
[OCUTALON|ocutalon]	Configure START
STEP Bridge.Installer OK 0.1s
STEP Public OK 0.0s
STEP Roles OK 0.0s
STEP Users OK 0.0s
STEP Web OK 0.0s
STEP SSL OK 0.0s
STEP Tasks OK 0.0s
STEP Demo OK 0.1s
STEP Provider OK 0.1s
STEP Audit OK 0.0s
STEP Telegram OK 0.0s
STEP Memory OK 0.1s
00:35:06.032:Ens.Director: Production 'OcuTalon.Production' starting...
00:35:06.142:Ens.Director: Production 'OcuTalon.Production' started.
STEP Production OK 1.1s
STEP Reconcile OK 0.1s
STEP PrivateData OK 0.1s
STEP Ready OK 0.0s
[OCUTALON|ocutalon]	Configure SUCCESS
[OCUTALON|ocutalon]	Activate SUCCESS
OCUTALON>
```

## The `iris merge` alternative

If you would rather create the namespace yourself, merge the package's configuration file into the instance, enable IPM for OCUTALON, and run the install command there:

```
iris merge <instance> /opt/ocutalon-ipm/src/cpf/ocutalon.cpf
```

Then, in an IRIS terminal:

```
zn "%SYS"
zpm "enable -map -ns OCUTALON"
zn "OCUTALON"
zpm "load /opt/ocutalon-ipm/src"
```

The install command then runs the same installer steps as the second command above.

## Demo mode

Demo mode is off after the install. To switch it on, open a terminal in OCUTALON as a user with the role OcuTalonAdmin or %All and run:

```
do ##class(OcuTalon.Core.Admin).SetDemoMode(1)
```

It creates the namespace OCUORDERS with its databases OCUORDERS_CODE and OCUORDERS_DATA next to the instance's other databases, maps OcuTalon's public package and global into it, and starts the Orders production there. Reload the OcuTalon page in a minute to see the change. To switch it off again, which removes OCUORDERS and both databases:

```
do ##class(OcuTalon.Core.Admin).SetDemoMode(0)
```

## The model key

Set `ANTHROPIC_API_KEY` in the environment that IRIS starts with. OcuTalon reads it from there and never stores it in IRIS. Without a key, OcuTalon still runs, every decision uses fixed rules, and the page shows a notice that says so.

## The README account

Open `http://localhost:52773/ocutalon/` (use your instance's web port) and sign in with the README account:

- User name: `ocutalon`
- Password: `ocutalon`

Change this password after your first sign-in. Open a terminal in the %SYS namespace, run the line below with your new password in place of `<new password>` (keep the quotation marks), then `halt`:

```
kill p set p("Password")="<new password>" write ##class(Security.Users).Modify("ocutalon",.p)
```

It prints `1` when the password was changed; if it prints anything else, the password was not changed. If your new password contains a double quotation mark, write it twice. Sign in again with the new password. The user name stays `ocutalon`.
