# Install OcuTalon with IPM

This page installs OcuTalon into an IRIS instance you already run, with the InterSystems Package Manager (IPM). The install takes two commands of the same text. The first one ends early on purpose and tells you what to do next. The second one gives a running OcuTalon with demo mode off.

## What you need

- An InterSystems IRIS for AI Hub instance, build 154, with IPM 0.10.10 loaded and enabled for the namespace you start from (the examples use USER).
- The OcuTalon package folder. That is the `src` folder of the OcuTalon repository, with the web page built once on any machine that has Node.js 24.15 or later:

  ```
  npm --prefix web ci
  npm --prefix web run build
  ```

  The instance needs no Node.js. Copy the `src` folder to a place the instance can read. The examples below call it `/opt/ocutalon-ipm/src`; use your own folder in its place.

OcuTalon needs no other package: the one package `ocutalon` holds the bridge too.

## The first command

Open an IRIS terminal in any namespace (USER here) and load the package:

```
zpm "load /opt/ocutalon-ipm/src"
```

This run ends early by design. It creates the namespace OCUTALON with its four databases and the mappings OcuTalon needs, maps IPM into it, and then stops with an error that is the next instruction. It does not load any OcuTalon code. This is the output of that run on a new instance, with the terminal's colour codes removed:

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

The last line, `ERROR! OcuTalon created namespace OCUTALON. Now run: zn "OCUTALON" then the same install command.`, is not a failure to fix. It is the stop of this first run. Running the first command again in USER or %SYS gives the same stop and changes nothing. In OCUTALON the same command is the second run.

## The second command

Do what the last line says. Switch to OCUTALON and run the same command:

```
zn "OCUTALON"
zpm "load /opt/ocutalon-ipm/src"
```

This run loads and compiles OcuTalon, installs the web page, and runs the installer steps one after another. Each step prints one `STEP <name> OK` line. A step that fails prints `STEP <name> FAILED <text>` and the command ends with `ERROR! <text>`; the code stays installed, and the same command runs the steps again. When the last line is `Activate SUCCESS`, OcuTalon runs. This is the output of that run, with the colour codes removed:

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

The installer marks the OcuTalon production to start with the instance, so it comes back after an instance restart. It changes no service of the instance and no namespace or database it did not create.

If a step fails after the code has loaded, the command reports the failure and names the step (`STEP <name> FAILED: the new OcuTalon code is installed. Run the same install command again.`, then IPM's `ERROR!` line), the new code stays installed, and running the same command again finishes the install; a failure while IPM loads or compiles the code is rolled back and the previous version keeps running.

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

This gives the same OcuTalon as the two commands above.

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
