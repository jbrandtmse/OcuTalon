# OcuTalon

## Try it in two minutes

Start with the online demo, at https://demo.ocutalon.com (nothing to install, and no Early Access image needed). Its sign-in details are on the splash screen.

To run OcuTalon on your own machine instead:

1. Load the IRIS for Health AI Hub Early Access build 154 image into Docker ([where to get it](#get-the-image)).
2. Clone this repository and run `./install.sh` in its folder ([what it does](#start-it-with-the-install-script)).
3. Sign in at http://localhost:52773/ocutalon/ with user name `ocutalon` and password `ocutalon` ([more on signing in](#sign-in)).
4. Follow the demo guide at the top of the page.

## What's interesting

OcuTalon runs as an IRIS Interoperability production, so the agent is an Interoperability workflow, and its work shows in Visual Trace, the tool you already use for your feeds. For each item that arrives, an IRIS AI Hub agent makes one attention decision, with its reasons and cost. Nothing risky runs without your yes: you get a dry run with counts first, you approve in the web chat, and every answer lands in the IRIS audit log. It was built this way so that you can audit and debug your assistant in the same place as the rest of your integrations.

## Contest task → where to see it

| Contest task or criterion | What release 1 has | Where to see it |
| --- | --- | --- |
| An IRIS Interoperability workflow | OcuTalon is an Interoperability production: every item and every decision is a production message you can follow in Visual Trace. Break the feed also sends 50 orders through a second production, Orders, which OcuTalon watches. | Online demo: the trace link under a reply opens Visual Trace. Repository: [src/ocutalon](src/ocutalon). |
| An IRIS AI Hub agent | Each item gets one attention decision from an AI Hub agent running Claude Haiku 5.5, with its reasons, confidence, tokens and cost. Every model request and tool call is an agent step in Visual Trace. | Online demo: "Decision details" under a reply. Repository: [src/ocutalon/cls/OcuTalon/Agent](src/ocutalon/cls/OcuTalon/Agent). |
| A decision-making task | The attention decision: Ignore, Digest, Tell now or Act. Anything risky waits for your approval, and content that did not come from you can only look, notify and save. A recorded evaluation set scores the decisions. | Online demo: the outcome on each reply and the Recent decisions list. Repository: [eval](eval) and [src/bridge](src/bridge). |
| Complexity | An agent inside a production, a cause worked out from the failed messages, and a repair and resend fixed to exact targets that runs only after an approval. The first answer to an approval request wins. | Online demo: steps 3 to 5 of the demo guide. Repository: [src/ocutalon](src/ocutalon) and [src/bridge](src/bridge). |
| Clarity of Instructions | This README, one install script, a plain `docker compose up -d`, and the online demo's splash screen and demo guide. | Online demo: the splash screen and the demo guide. Repository: [install.sh](install.sh) and [Install it yourself](#install-it-yourself). |
| Developer Experience | One script finds the image, starts OcuTalon and says where to sign in, with the exact fix when a check fails. Checks and tests run in CI on pushes and pull requests. | Repository: [install.sh](install.sh), [.github/workflows/ci.yml](.github/workflows/ci.yml) and [ci](ci). |
| Applicability | Ask OcuTalon in plain words to watch a production. It picks up new failures, groups the ones with one cause into an incident, and never gives a false all-clear. Reminders fire on time and survive restarts. | Online demo: step 1 of the demo guide, which watches the Orders production. A local install can watch any production its service user may read. |
| Usability | A two-minute demo guide with one-click prompts. Causes are in plain English. You answer Approve or Reject in the chat or on the page's Simulated phone. | Online demo: the demo guide and Break the feed. |

Watch the 35-second teaser: https://youtu.be/wycbyfnXFMU

## What OcuTalon does

OcuTalon is a personal assistant that runs inside InterSystems IRIS. For every item that reaches it, OcuTalon makes one attention decision. The decision has one of four outcomes:

- **Ignore**: Recorded; nobody notified.
- **Digest**: Saved for later; nobody notified now.
- **Tell now**: Needs you now.
- **Act**: OcuTalon took or requested an action.

Each decision shows its reasons, its confidence and its cost.

- **Chat on a live page.** You talk to OcuTalon in a web page that updates as things happen. A reply shows its decision and a link that opens it in Visual Trace.
- **Break the feed.** In demo mode the page has a Break the feed button. It makes a simulated partner send 50 orders in a changed date format into the Orders production, where they fail for real. OcuTalon groups the failures into one incident, explains the cause in plain English and proposes a fix with a dry run: how many orders it would resend, with an example. Nothing is resent until you press Approve in the chat or on the page's Simulated phone. Reject leaves everything as it was. After an approval, OcuTalon reports how many orders went through.
- **Watching a production.** Ask in plain words, for example "Watch the Orders production and only tell me if something needs me." To stop, say "Stop watching Orders."
- **Reminders.** Ask in plain words, for example "Remind me in 1 minute to stretch." A reminder arrives on time, survives a restart, and can be listed and cancelled in the chat.
- **No key, still works.** Without a model key, OcuTalon starts and every decision uses fixed rules. The page says so.

## Install it yourself

### What you need

- [Docker Desktop](https://docs.docker.com/desktop/) (macOS, or Windows with a [WSL 2](https://learn.microsoft.com/windows/wsl/install) shell), or [Docker Engine](https://docs.docker.com/engine/install/) with the Compose plugin (Linux).
- Docker Compose 2.24 or later. `docker compose version` shows yours; [how to install it](https://docs.docker.com/compose/install/).
- git, to clone this repository.
- An arm64 or x64 CPU.

macOS and Linux are what OcuTalon's author and its automated tests use. On Windows, work in a WSL 2 shell; the automated tests do not cover that.

### Get the image

OcuTalon runs on IRIS for Health AI Hub Early Access build 154 (`irishealth-community:2026.3.0AI.154.0`). Download it from the InterSystems Early Access Program portal: https://evaluation.intersystems.com/Eval/early-access/AIHub

Choose the file that ends in `docker.tar.gz` for your CPU: arm64 for Apple silicon and ARM Linux, x64 for Intel or AMD. `docker info --format '{{.Architecture}}'` tells which one Docker runs: `aarch64` for arm64, `x86_64` for x64.

Then load it:

```
docker load -i <the archive file>
```

### Start it with the install script

```
git clone https://github.com/jbrandtmse/OcuTalon.git
cd OcuTalon
./install.sh
```

The script checks that Docker and Docker Compose work and that a build 154 image for your CPU is loaded. It gives the image the name OcuTalon builds from, creates `.env` from `.env.example` when there is none, and starts OcuTalon with `docker compose up -d`. It shows a progress line every 10 seconds, waits up to 15 minutes, and prints the address and the sign-in details. When a check fails, it says what is wrong and the exact fix, and changes nothing.

When OcuTalon is ready, it prints:

```
OcuTalon is ready after <time>.

  Open:      http://localhost:52773/ocutalon/
  User:      ocutalon
  Password:  ocutalon
```

### Start it by hand

Without the script, give the loaded image the name OcuTalon builds from, then start it. `docker load` printed the loaded image's name; for the IRIS for Health archive it is `docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.3.0AI.154.0`.

```
docker tag <the name docker load printed> ocutalon-iris-base:2026.3.0AI.154.0
cp .env.example .env
docker compose up -d
```

The `cp` step is optional: without `.env`, OcuTalon starts with no model key ([Set a model key](#set-a-model-key)). Skip it when `.env` already exists, because `cp` would replace that file and the key in it.

### The IRIS (non-Health) image

OcuTalon also runs on the plain IRIS AI Hub build 154 image (`iris-community:2026.3.0AI.154.0`). It differs from IRIS for Health only by the HealthShare libraries and the HSCUSTOM namespace. It is supported and verified on ARM64. OcuTalon's automated tests use only the IRIS for Health image.

`./install.sh` uses the plain IRIS image when no IRIS for Health image for your CPU is loaded. By hand, give it the same name, then start as above:

```
docker tag <the name docker load printed for the iris-community image> ocutalon-iris-base:2026.3.0AI.154.0
docker compose up -d
```

### Check that it is ready

```
docker compose ps
```

OcuTalon is ready when the STATUS of the `iris` service ends in `(healthy)`, for example `Up About a minute (healthy)`. Then open http://localhost:52773/ocutalon/.

The first start took 47 to 78 seconds in five measurements on an Apple silicon Mac, and about 3 minutes (160 seconds) on an x64 Linux machine with 4 CPUs. The install script waits up to 15 minutes. A slower machine can take longer; run `docker compose ps` again to see.

## Set a model key

OcuTalon uses Anthropic's Claude models. The default model is Claude Haiku 5.5. To give it a key:

1. Create an API key at https://console.anthropic.com.
2. Copy `.env.example` to `.env` (`./install.sh` already did). Git ignores `.env`, so the key is never committed.
3. In `.env`, set `ANTHROPIC_API_KEY=<your key>`.
4. Apply it: `docker compose up -d --force-recreate`. This is what the page means by "restart OcuTalon".

Without a key, OcuTalon still starts. Every decision uses fixed rules, and the page shows a notice that says so.

## Sign in

Open http://localhost:52773/ocutalon/ and sign in with the README account:

- User name: `ocutalon`
- Password: `ocutalon`

OcuTalon does not ask you to change the password when you first sign in.

**Change the README account's password after your first sign-in.** OcuTalon publishes its web port on every network interface of your machine, so the IRIS Management Portal can be reached from your LAN until the passwords of the default IRIS accounts and of the README account are changed. [How to change the README account's password](#change-the-readme-accounts-password). The user name stays `ocutalon`.

**Visual Trace.** A trace link on the page opens the IRIS Management Portal in a new tab. The first time, the page shows "Sign in to Visual Trace", and the portal may ask you to sign in with the same account, which holds the trace role.

## Stop, start and update

- Stop: `docker compose down`. Your data stays on a Docker volume. Do not add `-v`: that deletes the volume.
- Start again: `docker compose up -d`.
- Update: `git pull`, then `docker compose up -d --build`. Your data and the changed password stay.

## Troubleshooting

These are the usual causes and fixes. Most entries are messages that `./install.sh` prints when a check or the start fails; the last two are about the page.

**"No IRIS build 154 image is loaded in Docker"**: download the archive for your CPU ([Get the image](#get-the-image)), load it with `docker load -i <the archive file>`, then run `./install.sh`.

**"The IRIS build 154 image that is loaded is for another CPU than this machine's"**: download and load the archive for your CPU. `docker info --format '{{.Architecture}}'` tells which one Docker runs. If the message says that `ocutalon-iris-base:2026.3.0AI.154.0` exists but is for another CPU, point the name at the right image: `docker tag <the loaded image's name> ocutalon-iris-base:2026.3.0AI.154.0`.

**"Docker is not installed (the docker command was not found)"**: install Docker Desktop (macOS, or Windows with WSL 2) or Docker Engine (Linux), then run `./install.sh`.

**"Docker is installed, but it is not running, or this user cannot reach it"**: start Docker Desktop. On Linux, run `sudo systemctl start docker`. If Docker is running, add your user to the docker group with `sudo usermod -aG docker $USER`, then log out and in again.

**"Docker Compose is missing"** or **"Docker Compose ... is too old"**: install the Compose plugin, version 2.24 or later. It comes with Docker Desktop; on Linux, install the `docker-compose-plugin` package. The old `docker-compose` command (version 1) does not work with OcuTalon.

**"Docker Compose could not start OcuTalon"**: the messages above it say why. Most often the web port 52773 is taken. Set another port in `.env` with `OCUTALON_WEB_PORT=<port>`, run `docker compose up -d`, and open that port instead of 52773. To read the container's log, run `docker compose logs iris`.

**"OcuTalon stopped before it was ready"**: run `docker compose logs iris` to read what happened.

**"OcuTalon was not ready after 15 min ..."**: run `docker compose logs iris`. For what the start did, run `docker compose exec iris cat /durable/ocutalon-after-start.log`: the lines that begin with `STEP` name each install step, and a start that went well has a line that begins with `RESULT OK`. A slow machine can take longer than 15 minutes, so run `docker compose ps` again before you give up.

**The page says "OcuTalon has no model key"**: see [Set a model key](#set-a-model-key). Until you add one, every decision uses fixed rules.

**The sign-in is refused**: use user name `ocutalon` and password `ocutalon`, or the new password if you changed it. To set a new one, see [Change the README account's password](#change-the-readme-accounts-password).

## For admins and developers

### Demo mode

Demo mode is on for the Docker install. It adds the demo guide, the Simulated phone and mailbox, and Break the feed, and it runs the Orders production in the namespace OCUORDERS.

An admin switches it from a terminal in the OCUTALON namespace:

```
docker compose exec iris iris session IRIS -U OCUTALON
```

At the `OCUTALON>` prompt, run the line below with 1 to switch demo mode on or 0 to switch it off, then `halt`:

```
do ##class(OcuTalon.Core.Admin).SetDemoMode(<0 or 1>)
```

The line needs the OcuTalonAdmin role or `%All`. The container's operating system login (irisowner) holds `%All`, so it works from that terminal. The answer is one plain-English line:

- On: "Demo mode is on. The Orders production runs in namespace OCUORDERS. Reload the OcuTalon page in a minute to see the change."
- Off: "Demo mode is off. The Orders production is stopped and namespace OCUORDERS is removed. Reload the OcuTalon page in a minute to see the change."

When OCUORDERS holds something OcuTalon did not create, switching demo mode off keeps the namespace, and the answer starts with "Demo mode is off." and then says, with {what was kept} naming what OcuTalon found:

> OcuTalon left the OCUORDERS namespace in place because it holds {what was kept}. To remove it, delete the namespace OCUORDERS and its databases OCUORDERS_CODE and OCUORDERS_DATA in the Management Portal.

A change takes up to a minute to show on the page.

### Change the README account's password

Open a terminal in the %SYS namespace:

```
docker compose exec iris iris session IRIS -U %SYS
```

At the `%SYS>` prompt, run the line below with your new password in place of `<new password>` (keep the quotation marks), then `halt`:

```
kill p set p("Password")="<new password>" write ##class(Security.Users).Modify("ocutalon",.p)
```

It prints `1` when the password was changed; if it prints anything else, the password was not changed. If your new password contains a double quotation mark, write it twice. Sign in again with the new password. The user name stays `ocutalon`.

### Repository layout

- `src/ocutalon`: OcuTalon's classes: the production, its agents, the web service behind the page and the install steps.
- `src/bridge`: the bridge, the part that calls the AI Hub agents, checks each tool call before it runs, handles the approval requests and writes the audit entries.
- `web`: the web page (Angular) and its browser tests.
- `docker`: the image's files and the checks and live tests in `docker/tests`.
- `ci`: the CI scripts and the model mock.
- `eval`: the recorded evaluation set.

### Tests and CI

`bash ci/checks.sh` runs the checks that need no container, among them the check of this README. The GitHub Actions workflow in `.github/workflows/ci.yml` runs them and the web build on pushes and pull requests, and the browser tests and the IRIS tests on pushes and on pull requests from this repository's own branches.

## Credits and licences

Built with the BMAD Method and Claude Code. More about them: [the BMAD Method](https://github.com/bmad-code-org/BMAD-METHOD) and [Claude Code](https://claude.com/product/claude-code).

OcuTalon is inspired by OpenClaw and is not affiliated with or endorsed by the OpenClaw Foundation.

Third-party licence notices:

- The web page's fonts (Inter, JetBrains Mono and Montserrat, under the SIL Open Font License) and its icons (Lucide, under the ISC licence) have their licence texts in [web/public/assets/licenses](web/public/assets/licenses).
- The web build writes the licence notices of its libraries to `3rdpartylicenses.txt`, beside the built page.
- The IPM package manager in the image is under the MIT licence: [docker/ipm/LICENSE](docker/ipm/LICENSE).
