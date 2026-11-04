#!/usr/bin/env bash
# OcuTalon install script: finds the IRIS build 154 image, starts OcuTalon and says where to sign in.
#
#   ./install.sh        (or: bash install.sh, from any folder)
#
# It checks everything before it changes anything: Docker runs, Docker Compose is 2.24 or later (the compose file's
# long env_file form needs it), .env.example is here, and a build 154 image for this machine's CPU is loaded. A failed
# check prints what is wrong and the exact fix, and exits 1.
# Then it gives the image the name the OcuTalon build starts from (a name that exists is never moved) and creates .env from
# .env.example when there is none. An iris service that is already running and healthy is left alone: the script prints
# the address and the README account at once, runs no `docker compose up` and no build, and names the command that applies
# an update (docker compose up -d --build). In every other state it runs `docker compose up -d`, shows a progress line
# every 10 s until the compose health check passes, and prints the address and the README account. The elapsed time it
# prints, and the 15 minutes it waits at most, count from the start of `docker compose up -d`, so they include the image build.
# It never removes a container, an image or a volume, and it never reads or prints .env.
#
# It runs in the shell that macOS ships (bash 3.2): no associative arrays, mapfile, ${v,,}, |&, &>>, empty "${a[@]}"
# under set -u, timeout, sed -i, grep -P, date -d or readlink -f.
# Two overrides exist for the tests only (whole seconds; anything else means the default): OCUTALON_INSTALL_POLL, the
# seconds between two polls (10), and OCUTALON_INSTALL_WAIT, the seconds to wait for a healthy container (900).
# It needs bash: run by another shell (sh is dash on Debian and Ubuntu), it stops at once with the command to use.
if [ -z "${BASH_VERSION:-}" ]; then
  echo "install.sh needs bash. Run it as ./install.sh, or as bash install.sh." >&2
  echo "Nothing was changed." >&2
  exit 1
fi
set -u

TAG=2026.3.0AI.154.0
# The name the Dockerfile's FROM receives through docker-compose.yml.
base=${IRIS_IMAGE:-ocutalon-iris-base:$TAG}
poll=${OCUTALON_INSTALL_POLL:-10}
max_wait=${OCUTALON_INSTALL_WAIT:-900}
case $poll in
  '' | *[!0-9]*) poll=10 ;;
esac
case $max_wait in
  '' | *[!0-9]*) max_wait=900 ;;
esac
if [ "${#poll}" -gt 6 ]; then poll=10; fi
if [ "${#max_wait}" -gt 6 ]; then max_wait=900; fi
poll=$((10#$poll))
max_wait=$((10#$max_wait))

# Work from the script's own folder, so the compose file and .env are found from any directory.
case $0 in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
if [ -z "$here" ]; then here=/; fi
CDPATH='' cd -- "$here" || exit 1

# die <line>...: each argument is a line of the message, on standard error; exits 1.
die() {
  printf '\n' >&2
  printf '%s\n' "$@" >&2
  exit 1
}

# norm_arch <architecture>: arm64 or amd64 for the names Docker and the machine use.
norm_arch() {
  case $1 in
    aarch64 | arm64) printf 'arm64' ;;
    x86_64 | amd64) printf 'amd64' ;;
    *) printf '%s' "$1" ;;
  esac
}

# cpu_name <normalised architecture>: the name a person knows the CPU by.
cpu_name() {
  case $1 in
    arm64) printf 'arm64' ;;
    amd64) printf 'x64' ;;
    '') printf 'an unknown CPU' ;;
    *) printf '%s' "$1" ;;
  esac
}

# fmt_time <seconds>: 45 s, or 2 min 5 s.
fmt_time() {
  if [ "$1" -ge 60 ]; then
    printf '%d min %d s' $(($1 / 60)) $(($1 % 60))
  else
    printf '%d s' "$1"
  fi
}

# short_id <image id>: the first 12 characters, without the sha256: prefix, which is how `docker image ls` lists an id.
short_id() {
  local id=${1#sha256:}
  printf '%s' "${id:0:12}"
}

# read_service: sets state and health to the iris service's container state and health check ("" for either when compose
# answers nothing, as it does when there is no container).
read_service() {
  local line
  state=""
  health=""
  line=$(docker compose ps --all --format '{{.State}} {{.Health}}' iris 2>/dev/null </dev/null) || line=""
  read -r state health <<EOF
$line
EOF
}

echo "OcuTalon install"

# --- the checks: nothing is tagged, written or started until all of them pass ---

if ! command -v docker >/dev/null 2>&1; then
  die "Docker is not installed (the docker command was not found)." \
    "Install Docker Desktop (macOS, or Windows with WSL) or Docker Engine (Linux), then run ./install.sh again." \
    "Nothing was changed."
fi

if ! daemon_out=$(docker version --format '{{.Server.Arch}}' 2>/dev/null </dev/null) || [ -z "$daemon_out" ]; then
  die "Docker is installed, but it is not running, or this user cannot reach it." \
    "Start Docker Desktop (macOS, or Windows with WSL). On Linux, run:  sudo systemctl start docker" \
    "On Linux, if Docker is running, add this user to the docker group:  sudo usermod -aG docker \$USER" \
    "Then log out and in again, and run ./install.sh again." \
    "Nothing was changed."
fi
daemon_arch=$(norm_arch "${daemon_out%%[[:space:]]*}")

if ! compose_out=$(docker compose version --short 2>/dev/null </dev/null) || [ -z "$compose_out" ]; then
  die "Docker Compose is missing: the docker compose command does not work." \
    "Install the Compose plugin, version 2.24 or later. It comes with Docker Desktop; on Linux, install the docker-compose-plugin package." \
    "The old docker-compose command (version 1) does not work with OcuTalon." \
    "Then run ./install.sh again. Nothing was changed."
fi
compose_version=${compose_out%%[[:space:]]*}
compose_numbers=${compose_version#v}
compose_major=${compose_numbers%%.*}
compose_rest=${compose_numbers#*.}
compose_minor=${compose_rest%%.*}
compose_major=${compose_major%%[!0-9]*}
compose_minor=${compose_minor%%[!0-9]*}
compose_ok=0
if [ -n "$compose_major" ] && [ -n "$compose_minor" ]; then
  if [ "$((10#$compose_major))" -gt 2 ] || { [ "$((10#$compose_major))" -eq 2 ] && [ "$((10#$compose_minor))" -ge 24 ]; }; then
    compose_ok=1
  fi
fi
if [ "$compose_ok" -ne 1 ]; then
  die "Docker Compose $compose_version is too old, or its version cannot be read. OcuTalon needs Compose 2.24 or later." \
    "Upgrade it: update Docker Desktop, or on Linux update the docker-compose-plugin package (or install Docker Engine's current Compose plugin)." \
    "Then run ./install.sh again. Nothing was changed."
fi

env_missing=0
if [ ! -e .env ] && [ ! -L .env ]; then
  env_missing=1
  if [ ! -f .env.example ]; then
    die "This folder has no .env.example, so .env cannot be created." \
      "Keep install.sh in the OcuTalon folder, beside docker-compose.yml and .env.example, and get .env.example back from the OcuTalon repository if it is missing. Then run ./install.sh again." \
      "Nothing was changed."
  fi
  if [ ! -w . ]; then
    die "This folder is read-only for you, so .env cannot be created." \
      "Make the OcuTalon folder writable for this user, then run ./install.sh again." \
      "Nothing was changed."
  fi
fi

# scan_images: sets records to one line per candidate image, in LC_ALL=C order of reference:
#   <h for IRIS for Health, n for non-Health> <reference> <image id> <architecture>
# A candidate is a local image tagged $TAG whose repository is irishealth-community or iris-community, with or without a
# registry prefix.
scan_images() {
  local listing line ref id repo tag kind arch
  records=""
  listing=$(docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}}' 2>/dev/null </dev/null | LC_ALL=C sort)
  while IFS= read -r line; do
    if [ -z "$line" ]; then continue; fi
    ref=${line% *}
    id=${line##* }
    repo=${ref%:*}
    tag=${ref##*:}
    if [ "$tag" != "$TAG" ]; then continue; fi
    case $repo in
      irishealth-community | */irishealth-community) kind=h ;;
      iris-community | */iris-community) kind=n ;;
      *) continue ;;
    esac
    arch=$(docker image inspect --format '{{.Architecture}}' "$id" 2>/dev/null </dev/null) || arch=""
    arch=$(norm_arch "${arch%%[[:space:]]*}")
    records="$records$kind $ref $id $arch
"
  done <<EOF
$listing
EOF
}

# pick <h|n>: sets pick_ref and pick_id to the first candidate of that kind whose CPU is this machine's. Returns 1 when none is.
pick() {
  local kind ref id arch
  pick_ref=""
  pick_id=""
  while read -r kind ref id arch; do
    if [ "$kind" != "$1" ]; then continue; fi
    if [ "$arch" = "$daemon_arch" ]; then
      pick_ref=$ref
      pick_id=$id
      return 0
    fi
  done <<EOF
$records
EOF
  return 1
}

# other_cpu_lines: one line for each candidate, with its CPU.
other_cpu_lines() {
  local kind ref id arch
  while read -r kind ref id arch; do
    if [ -z "$ref" ]; then continue; fi
    printf '  %s is for %s\n' "$ref" "$(cpu_name "$arch")"
  done <<EOF
$records
EOF
}

this_cpu=$(cpu_name "$daemon_arch")
scan_images
base_info=""
base_info=$(docker image inspect --format '{{.Id}} {{.Architecture}}' "$base" 2>/dev/null </dev/null) || base_info=""

build_image=$base
tag_id=""
image_lines=""
if [ -n "$base_info" ]; then
  # The name exists: it is used as it is, and never moved.
  base_id=${base_info%% *}
  base_arch=$(norm_arch "${base_info#* }")
  if [ "$base_arch" != "$daemon_arch" ]; then
    if pick h || pick n; then
      fix="A matching image is already loaded. Point the name at it:  docker tag $pick_ref $base"
    else
      fix="Download the IRIS for Health AI Hub build 154 archive for $this_cpu and load it:  docker load -i <the archive file>
Then point the name at the loaded image:  docker tag <the loaded image, ending in irishealth-community:$TAG> $base"
    fi
    die "The image $base exists, but it is for $(cpu_name "$base_arch"), and this machine's Docker runs $this_cpu." \
      "$fix" \
      "Then run ./install.sh again. Nothing was changed."
  fi
  base_kind=""
  base_ref=""
  base_short=$(short_id "$base_id")
  while read -r kind ref id arch; do
    if [ -z "$ref" ]; then continue; fi
    if [ "$(short_id "$id")" = "$base_short" ]; then
      base_kind=$kind
      base_ref=$ref
      break
    fi
  done <<EOF
$records
EOF
  case $base_kind in
    h) image_lines="Image: IRIS for Health, build 154 ($base_ref). The existing $base is that image, so it is not tagged again." ;;
    n)
      image_lines="Image: IRIS (non-Health), build 154 ($base_ref). The existing $base is that image, so it is not tagged again."
      build_image=$base_ref
      ;;
    *) image_lines="Image: the existing $base. No IRIS for Health or IRIS (non-Health) build 154 image loaded here has its ID, so it is used as it is." ;;
  esac
else
  if pick h; then
    tag_id=$pick_id
    image_lines="Image: IRIS for Health, build 154 ($pick_ref)."
  elif pick n; then
    tag_id=$pick_id
    build_image=$pick_ref
    image_lines="Image: IRIS (non-Health), build 154 ($pick_ref)."
    while read -r kind ref id arch; do
      if [ "$kind" = h ]; then
        image_lines="$image_lines
The IRIS for Health image $ref is for $(cpu_name "$arch"), not for this machine's $this_cpu, so the non-Health image is used."
        break
      fi
    done <<EOF
$records
EOF
  elif [ -z "$records" ]; then
    die "No IRIS build 154 image is loaded in Docker (no irishealth-community:$TAG, and no iris-community:$TAG)." \
      "Download the IRIS for Health AI Hub build 154 archive for this machine's CPU ($this_cpu; the archives are for arm64 or x64) and load it:" \
      "  docker load -i <the archive file>" \
      "Then run ./install.sh again. Nothing was changed."
  else
    die "The IRIS build 154 image that is loaded is for another CPU than this machine's. This machine's Docker runs $this_cpu." \
      "$(other_cpu_lines)" \
      "Download the IRIS for Health AI Hub build 154 archive for $this_cpu and load it:" \
      "  docker load -i <the archive file>" \
      "Then run ./install.sh again. Nothing was changed."
  fi
fi

echo "Docker is running on $this_cpu, and Docker Compose is $compose_version."
printf '%s\n' "$image_lines"

# --- the changes ---

if [ -n "$tag_id" ]; then
  if ! docker tag "$tag_id" "$base" </dev/null; then
    die "Docker could not give the image the name $base." \
      "Nothing else was changed. Run ./install.sh again, or tag it yourself:  docker tag $tag_id $base"
  fi
  echo "Tagged it as $base, the name that OcuTalon's own image is built from."
fi

if [ "$env_missing" -eq 1 ]; then
  if ! cp .env.example .env; then
    die "The file .env could not be created from .env.example." \
      "Copy it yourself (cp .env.example .env), then run ./install.sh again."
  fi
  echo "Created .env from .env.example. The model key (ANTHROPIC_API_KEY) in it is empty:"
  echo "OcuTalon starts without one, and its page shows a notice about it. To set a key, add it to .env and run: docker compose up -d --force-recreate"
else
  echo "Found .env. It was not changed."
fi

IRIS_IMAGE=$build_image
export IRIS_IMAGE

# A running, healthy OcuTalon is left alone: no `docker compose up`, no build, no restart. Every other state (no container,
# stopped, failed part-way, starting, unhealthy) runs `docker compose up -d` and waits.
already_healthy=0
read_service
if [ "$state" = running ] && [ "$health" = healthy ]; then
  already_healthy=1
  elapsed=0
  echo "OcuTalon is already running and healthy, so it was not started again."
else
  echo "Starting OcuTalon with docker compose up -d. The first start takes a few minutes; up to 15 minutes are allowed."
  started=$SECONDS
  if ! docker compose up -d </dev/null; then
    die "Docker Compose could not start OcuTalon." \
      "The messages above say why. To read the container's log, run:  docker compose logs iris" \
      "The Troubleshooting section of README.md lists the usual causes and fixes." \
      "Nothing was removed."
  fi

  # --- waiting until the compose health check passes ---

  while :; do
    read_service
    elapsed=$((SECONDS - started))
    if [ "$state" = running ] && [ "$health" = healthy ]; then
      break
    fi
    case $state in
      '' | exited | dead)
        die "OcuTalon stopped before it was ready after $(fmt_time "$elapsed") (container state: ${state:-no container})." \
          "To read what happened, run:  docker compose logs iris" \
          "The Troubleshooting section of README.md lists the usual causes and fixes." \
          "Nothing was removed: this script never removes a container, an image or a volume."
        ;;
    esac
    if [ "$elapsed" -ge "$max_wait" ]; then
      die "OcuTalon was not ready after $(fmt_time "$elapsed"), the longest this script waits." \
        "To read what is happening, run:  docker compose logs iris" \
        "The Troubleshooting section of README.md lists the usual causes and fixes." \
        "Nothing was removed. The container (state: $state${health:+, health check: $health}) may still become ready later."
    fi
    if [ -n "$health" ]; then
      echo "Waiting, $(fmt_time "$elapsed") so far: container $state, health check $health"
    else
      echo "Waiting, $(fmt_time "$elapsed") so far: container $state"
    fi
    step=$poll
    if [ "$step" -gt $((max_wait - elapsed)) ]; then step=$((max_wait - elapsed)); fi
    sleep "$step"
  done
fi

# --- ready ---

port_out=$(docker compose port iris 52773 2>/dev/null </dev/null) || port_out=""
read -r port_line <<EOF
$port_out
EOF
port=${port_line##*:}
case $port in
  '' | *[!0-9]*)
    die "OcuTalon is healthy, but Docker Compose reports no published web port, so there is no address to print." \
      "To see the ports, run:  docker compose ps"
    ;;
esac

echo
echo "OcuTalon is ready after $(fmt_time "$elapsed")."
echo
echo "  Open:      http://localhost:$port/ocutalon/"
echo "  User:      ocutalon"
echo "  Password:  ocutalon"
if [ "$already_healthy" -eq 1 ]; then
  echo
  echo "To apply an update, run: docker compose up -d --build"
fi
exit 0
