# Install OcuTalon with IPM

This page installs OcuTalon into an IRIS instance you already run, with the InterSystems Package Manager (IPM). On a fresh instance it first loads IPM 0.10.10 and points it at the community package registry. The install itself takes two commands of the same text, one after the other. The first one ends early on purpose and tells you what to do next. The second one gives a running OcuTalon with demo mode off. The page opens with the install from the community package registry; the install from the package folder, for developers, comes after it.

## What you need

- An InterSystems IRIS for AI Hub instance, build 154, with no IPM in %SYS or with IPM 0.10.10 there. Build 109, which the Early Access portal now offers in place of build 154, works the same way: the registry install on this page was run on fresh IRIS for Health instances of both builds.
- An instance that can reach the community package registry, which serves IPM and the `ocutalon` package.
- Network access from the instance to PyPI (pypi.org and files.pythonhosted.org) and to Hugging Face (huggingface.co and its download hosts under hf.co, in our test installs us.aws.cdn.hf.co and cas-server.xethub.hf.co): the second command downloads OcuTalon's Python packages, about 250 MB once installed, and the embedding model, about 90 MB. In our test installs, the whole second command took about 1 to 1.5 minutes on an Apple silicon Mac and about 3 minutes on a shared x64 Linux build server. On the Mac, the downloads took about 20 seconds of that.
- The second command puts these packages in the instance's shared Python folder, mgr/python in the IRIS install directory. Where that folder already holds older versions of certifi, charset_normalizer, idna, requests, typing_extensions or urllib3, which IPM installs for itself, the second command replaces them with the versions OcuTalon pins. IPM's own packages work with these versions.

OcuTalon needs no other package: the one package `ocutalon` holds the bridge too.

## Install from the package registry

### Load IPM and point it at the registry

A fresh AI Hub instance has no IPM in %SYS: there, `zpm "version"` answers `<SYNTAX>`. In an IRIS terminal in %SYS, load IPM 0.10.10 from the community package registry:

```
s r=##class(%Net.HttpRequest).%New(),r.Server="pm.community.intersystems.com",r.SSLConfiguration="ISC.FeatureTracker.SSL.Config" d r.Get("/packages/zpm/0.10.10/installer"),$system.OBJ.LoadStream(r.HttpResponse.Data,"c")
```

The line fetches IPM's installer for version 0.10.10 and runs it. Its output is several hundred lines. On build 154 it ended with these lines:

```
[%SYS|ZPM]	Activate SUCCESS2026-11-05 21:00:10 0 IPM.Installer: Installation succeeded at 2026-11-05 21:00:10
2026-11-05 21:00:10 0 %Installer: Elapsed time 27.335204s

Time spent 27.340316
Load finished successfully.
```

On an instance that already has IPM 0.10.10 in %SYS, the line loads the installer and installs nothing new. Then, still in %SYS, run these two commands:

```
zpm "enable -map -ns USER"
zpm "enable -community"
```

`zpm "enable -map -ns USER"` maps IPM into USER. This is its output on build 154, with the terminal's colour codes removed:

```
Version of IPM in current namespace:
%SYS> zpm 0.10.10
Mapping %IPM package in %SYS equivalently to USER
Mapping %IPM.* routines in %SYS equivalently to USER
Done.

%SYS>  zpm 0.10.10
HSLIB> zpm 0.10.5-SNAPSHOT
HSSYS> zpm 0.10.5-SNAPSHOT
       Installed In: HSLIB
USER>  zpm 0.10.10
       Installed In: %SYS
```

`enable -community` first deletes the repositories configured in %SYS (`repo -delete-all` in its output), then adds the community registry and maps it into USER (`Mapping IPM repository in %SYS equivalently to USER`). Run the two commands in this order. Without `enable -map -ns USER` first, `enable -community` maps IPM into USER but skips USER's repositories (`Skipping repository mapping of USER - IPM not mapped from source namespace.`), and the install in USER then stops with `ERROR! No repositories are configured and enabled in this namespace.` The two commands give the same result when USER already had IPM mapped from %SYS. If IPM was installed in USER itself, they leave USER's repositories as they are: then also run `zpm "enable -community"` in an IRIS terminal in USER before the install. There it first deletes the repositories configured in USER. This is the output of `enable -community` on build 154, with the terminal's colour codes removed:

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
Compilation started on 11/05/2026 21:01:44
Compiling class OcuTalon.Install.Ipm
Compiling routine OcuTalon.Install.Ipm.1
Compilation finished successfully in 0.016s.

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
Compilation started on 11/06/2026 18:35:08
Compiling class OcuTalon.Install.Ipm
Compiling routine OcuTalon.Install.Ipm.1
Compilation finished successfully in 0.004s.

[OCUTALON|ocutalon]	Initialize SUCCESS
[OCUTALON|ocutalon]	Reload START (/tmp/ocutalon-repo/ocutalon-1.0.1/)
STEP Python replaced certifi 2025.1.31 with 2026.10.23
STEP Python replaced charset_normalizer 2.1.1 with 3.5.2
STEP Python replaced idna 3.15 with 3.20
STEP Python replaced requests 2.32.3 with 2.34.2
STEP Python replaced typing_extensions 4.12.2 with 4.16.0
STEP Python replaced urllib3 2.6.3 with 2.8.0
[OCUTALON|ocutalon]	requirements.txt START
[OCUTALON|ocutalon]	requirements.txt SUCCESS
[OCUTALON|ocutalon]	Reload SUCCESS
[ocutalon]	Module object refreshed.
[OCUTALON|ocutalon]	Validate START
[OCUTALON|ocutalon]	Validate SUCCESS
[OCUTALON|ocutalon]	Compile START
[OCUTALON|ocutalon]	Compile SUCCESS
[OCUTALON|ocutalon]	Activate START
[OCUTALON|ocutalon]	Configure START
STEP Bridge.Installer OK 0.2s
STEP Public OK 0.0s
STEP Roles OK 0.0s
STEP Users OK 0.1s
STEP Web OK 0.1s
STEP SSL OK 0.0s
STEP Tasks OK 0.1s
STEP Demo OK 0.1s
STEP Provider OK 0.1s
STEP Audit OK 0.0s
STEP Telegram OK 0.0s
STEP Memory OK 4.7s
18:36:12.729:Ens.Director: Production 'OcuTalon.Production' starting...
18:36:13.147:Ens.Director: Production 'OcuTalon.Production' started.
STEP Production OK 1.6s
STEP Reconcile OK 0.2s
STEP PrivateData OK 0.5s
STEP Ready OK 0.0s
[OCUTALON|ocutalon]	Configure SUCCESS
[OCUTALON|ocutalon]	Activate SUCCESS
OCUTALON>
```

The installer marks the OcuTalon production to start with the instance, so it comes back after an instance restart. It changes no service of the instance and no namespace or database it did not create.

If a step fails after the code has loaded, the command reports the failure and names the step (`STEP <name> FAILED: the new OcuTalon code is installed. Run the same install command again.`, then IPM's `ERROR!` line), the new code stays installed, and running the same command again finishes the install; a failure while IPM loads or compiles the code is rolled back and the previous version keeps running.

## Install from the package folder (for developers)

This install needs the OcuTalon package folder. That is the `src` folder of the OcuTalon repository, with the web page built once on any machine that has Node.js 24.15 or later:

```
npm --prefix web ci
npm --prefix web run build
```

The instance needs no Node.js. Copy the `src` folder to a place the instance can read. The examples below call it `/opt/ocutalon-ipm/src`; use your own folder in its place.

It also needs IPM 0.10.10 in %SYS, enabled for USER, as [Load IPM and point it at the registry](#load-ipm-and-point-it-at-the-registry) gives.

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

OCUTALON>

Building dependency graph...Done.
[OCUTALON|ocutalon]	Initialize START
Compilation started on 11/06/2026 18:21:47
Compiling class OcuTalon.Install.Ipm
Compiling routine OcuTalon.Install.Ipm.1
Compilation finished successfully in 0.003s.

[OCUTALON|ocutalon]	Initialize SUCCESS
[OCUTALON|ocutalon]	Reload START (/opt/ocutalon-ipm/src/)
STEP Python replaced certifi 2025.1.31 with 2026.10.23
STEP Python replaced charset_normalizer 2.1.1 with 3.5.2
STEP Python replaced idna 3.15 with 3.20
STEP Python replaced requests 2.32.3 with 2.34.2
STEP Python replaced typing_extensions 4.12.2 with 4.16.0
STEP Python replaced urllib3 2.6.3 with 2.8.0
[OCUTALON|ocutalon]	requirements.txt START
[OCUTALON|ocutalon]	requirements.txt SUCCESS
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
STEP Memory OK 3.9s
18:22:46.081:Ens.Director: Production 'OcuTalon.Production' starting...
18:22:46.173:Ens.Director: Production 'OcuTalon.Production' started.
STEP Production OK 1.1s
STEP Reconcile OK 0.2s
STEP PrivateData OK 0.2s
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
