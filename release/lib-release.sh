#!/usr/bin/env bash
# The helpers that the release scripts share (Story 11.3; AD-25, AD-29; REL-6). Sourced, not run: it defines functions and a few
# variables, and runs nothing. release/rehearse.sh, release/upgrade-harness.sh and the scripts of Stories 11.4, 11.5 and 11.13 use it.
#
# release_config_read <file>   reads the author's configuration file (KEY=value lines, outside the repository) and sets the shell
#                              variables REHEARSAL_<KEY>. No line is expanded: a $(...) in a value stays text, and only a leading ~/ of a
#                              path key becomes the home folder. Lines that do not start with REHEARSAL_, blank lines and # lines are
#                              ignored. Keys: CLEAN_SSH (user@host), CLEAN_KEY, CLEAN_WEB (the clean host's name or address as the
#                              driver host reaches it; no scheme and no port), DRIVER_SSH (user@host, or local), DRIVER_KEY (not needed for local),
#                              ENV_FILE; optional CLEAN_PORT, DRIVER_PORT and KNOWN_HOSTS. It prints one line "REFUSED config: ..."
#                              that names a key or a kind of file, never a value, and returns 2 for a missing file, a missing or
#                              unknown key, a file of the repository, or an env file that group or others can read; 0 otherwise
# release_config_path          prints the configuration file's path: OCUTALON_RELEASE_CONFIG, else
#                              ${XDG_CONFIG_HOME:-$HOME/.config}/ocutalon/release.conf
# host_run <clean|driver> <command>
#                              runs the POSIX sh command on a host, with the caller's standard input. REHEARSAL_MODE is real or dry. In real
#                              mode it is ${OCUTALON_REHEARSAL_SSH:-ssh} -i <key> -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=15
#                              -o StrictHostKeyChecking=yes [-o UserKnownHostsFile=<file>] [-p <port>] -- <destination> <command>, so
#                              host keys are checked strictly whatever the user's ssh configuration says; a driver of
#                              local runs sh -c in REHEARSAL_LOCAL_DIR on this machine. In dry mode it never runs ssh: the clean host is
#                              sh -c in $REHEARSAL_STANDIN/clean with the throwaway's STANDIN_PROJECT, STANDIN_FILES, STANDIN_IMAGE and
#                              STANDIN_WAIT as COMPOSE_PROJECT_NAME, COMPOSE_FILE, IRIS_IMAGE and OCUTALON_INSTALL_WAIT, and the driver
#                              is sh -c in $REHEARSAL_STANDIN/driver. Paths in a command are relative to the login folder
# record_path <version> <rc>   prints release/records/<version>/rc<rc>.md
# record_write <file> <section file> [<heading>]
#                              writes the section file (its first line is its "## " title) into the record: it replaces the section with
#                              that title, up to the next heading or the end of the file, or appends it. A missing file (and its folder) is
#                              created with the heading, by default "# OcuTalon <v> rc<n>" for a path ending <v>/rc<n>.md and
#                              "# OcuTalon candidate record" otherwise. The other sections are kept byte for byte
# env_get <file> <key>, env_set <file> <key> <value>   key=value files (options, results of a run)
# detail_clean                 a result detail on one line of printable ASCII, 300 characters at most, with no pipe (stdin to stdout)
umask 077

release_lib_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

REHEARSAL_KEYS="CLEAN_SSH CLEAN_KEY CLEAN_WEB DRIVER_SSH DRIVER_KEY ENV_FILE CLEAN_PORT DRIVER_PORT KNOWN_HOSTS"
REHEARSAL_PATH_KEYS="CLEAN_KEY DRIVER_KEY ENV_FILE KNOWN_HOSTS"

# env_get <file> <key> / env_set <file> <key> <value>: key=value files (options, seed.env, upgrade.env).
env_get() { sed -n "s/^$2=//p" "$1" 2> /dev/null | tail -n 1; }
env_set() {
  if [ -f "$1" ]; then
    grep -v "^$2=" "$1" > "$1.new"
    mv "$1.new" "$1"
  fi
  printf '%s=%s\n' "$2" "$3" >> "$1"
}

# detail_clean: a result detail on one line of printable ASCII, 300 characters at most, with no pipe (the record is a table).
detail_clean() { tr -d '\r' | tr '\n' ' ' | LC_ALL=C tr -c '\040-\176' '?' | tr '|' '/' | cut -c1-300; }

# --- the configuration ---

release_config_path() {
  printf '%s\n' "${OCUTALON_RELEASE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/ocutalon/release.conf}"
}

# release_in_repo <path>: 0 when the path is below the repository that holds this library.
release_in_repo() {
  local d
  d=$(cd "$(dirname "$1")" 2> /dev/null && pwd -P) || return 1
  case $d/ in
    "$release_lib_root"/*) return 0 ;;
  esac
  return 1
}

# release_private_file <path>: 0 when neither group nor others have any permission on the file.
release_private_file() {
  [ "$(ls -ld "$1" 2> /dev/null | cut -c5-10)" = "------" ]
}

release_config_read() {
  local file=$1 line key val name k var
  for k in $REHEARSAL_KEYS; do unset "REHEARSAL_$k"; done
  if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    echo "REFUSED config: the configuration file is missing or not readable"
    return 2
  fi
  if release_in_repo "$file"; then
    echo "REFUSED config: the configuration file is inside the repository; keep it outside"
    return 2
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    line=${line#"${line%%[![:space:]]*}"}
    case $line in
      '' | '#'*) continue ;;
      *=*) ;;
      *) continue ;;
    esac
    key=${line%%=*}
    val=${line#*=}
    key=${key%"${key##*[![:space:]]}"}
    case $key in
      REHEARSAL_*) ;;
      *) continue ;;
    esac
    name=${key#REHEARSAL_}
    case " $REHEARSAL_KEYS " in
      *" $name "*) ;;
      *)
        echo "REFUSED config: unknown key $key"
        return 2
        ;;
    esac
    val=${val#"${val%%[![:space:]]*}"}
    val=${val%"${val##*[![:space:]]}"}
    case $val in
      \"*\") val=${val#\"}; val=${val%\"} ;;
      \'*\') val=${val#\'}; val=${val%\'} ;;
    esac
    case " $REHEARSAL_PATH_KEYS " in
      *" $name "*)
        case $val in
          '~/'*) val=$HOME/${val#'~/'} ;;
        esac
        ;;
    esac
    printf -v "$key" '%s' "$val"
  done < "$file"
  for k in CLEAN_SSH CLEAN_KEY CLEAN_WEB DRIVER_SSH ENV_FILE; do
    var=REHEARSAL_$k
    if [ -z "${!var:-}" ]; then
      echo "REFUSED config: $var is not set"
      return 2
    fi
  done
  if [ "$REHEARSAL_DRIVER_SSH" != local ] && [ -z "${REHEARSAL_DRIVER_KEY:-}" ]; then
    echo "REFUSED config: REHEARSAL_DRIVER_KEY is not set"
    return 2
  fi
  for k in CLEAN_KEY DRIVER_KEY KNOWN_HOSTS; do
    var=REHEARSAL_$k
    if [ -n "${!var:-}" ] && [ ! -r "${!var}" ]; then
      echo "REFUSED config: $var names no readable file"
      return 2
    fi
  done
  if [ ! -f "$REHEARSAL_ENV_FILE" ] || [ ! -r "$REHEARSAL_ENV_FILE" ]; then
    echo "REFUSED config: REHEARSAL_ENV_FILE names no readable file"
    return 2
  fi
  if release_in_repo "$REHEARSAL_ENV_FILE"; then
    echo "REFUSED config: the env file is inside the repository; keep it outside"
    return 2
  fi
  if ! release_private_file "$REHEARSAL_ENV_FILE"; then
    echo "REFUSED config: the env file is readable by group or others; run chmod 600 on it"
    return 2
  fi
  return 0
}

# --- the hosts ---

host_run() {
  local which=$1 cmd=$2 dest key port ssh_cmd args
  case ${REHEARSAL_MODE:-real} in
    dry)
      case $which in
        clean)
          (
            cd "${REHEARSAL_STANDIN:?}/clean" \
              && env -u ANTHROPIC_API_KEY -u TELEGRAM_BOT_TOKEN COMPOSE_PROJECT_NAME="${STANDIN_PROJECT:-}" COMPOSE_FILE="${STANDIN_FILES:-}" \
                IRIS_IMAGE="${STANDIN_IMAGE:-}" OCUTALON_INSTALL_WAIT="${STANDIN_WAIT:-}" sh -c "$cmd"
          )
          ;;
        driver)
          (cd "${REHEARSAL_STANDIN:?}/driver" && sh -c "$cmd")
          ;;
        *) return 2 ;;
      esac
      return
      ;;
  esac
  case $which in
    clean)
      dest=${REHEARSAL_CLEAN_SSH:-}
      key=${REHEARSAL_CLEAN_KEY:-}
      port=${REHEARSAL_CLEAN_PORT:-}
      ;;
    driver)
      dest=${REHEARSAL_DRIVER_SSH:-}
      key=${REHEARSAL_DRIVER_KEY:-}
      port=${REHEARSAL_DRIVER_PORT:-}
      if [ "$dest" = local ]; then
        (cd "${REHEARSAL_LOCAL_DIR:-.}" && sh -c "$cmd")
        return
      fi
      ;;
    *) return 2 ;;
  esac
  read -r -a ssh_cmd <<< "${OCUTALON_REHEARSAL_SSH:-ssh}"
  args=("${ssh_cmd[@]}" -i "$key" -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=yes)
  if [ -n "${REHEARSAL_KNOWN_HOSTS:-}" ]; then args+=(-o "UserKnownHostsFile=$REHEARSAL_KNOWN_HOSTS"); fi
  if [ -n "$port" ]; then args+=(-p "$port"); fi
  args+=(-- "$dest" "$cmd")
  "${args[@]}"
}

# --- the record ---

record_path() { printf 'release/records/%s/rc%s.md\n' "$1" "$2"; }

# record_write <file> <section file> [<heading>]: see the header.
record_write() {
  local file=$1 section=$2 heading=${3:-} title base dir
  if [ -z "$heading" ]; then
    base=$(basename "$file" .md)
    dir=$(basename "$(dirname "$file")")
    case $base in
      rc[0-9]*) heading="# OcuTalon $dir $base" ;;
      *) heading="# OcuTalon candidate record" ;;
    esac
  fi
  title=$(head -n 1 "$section" 2> /dev/null)
  [ -n "$title" ] || return 2
  mkdir -p "$(dirname "$file")" || return 1
  if [ ! -f "$file" ]; then
    printf '%s\n\n' "$heading" > "$file" || return 1
  fi
  TITLE=$title awk -v sec="$section" '
    BEGIN { title = ENVIRON["TITLE"]; while ((getline l < sec) > 0) s[++n] = l }
    function put(   i) { for (i = 1; i <= n; i++) print s[i]; done = 1 }
    { t = $0; sub(/[ \t]+$/, "", t) }
    t == title && !done { skip = 1; put(); next }
    skip && /^##? / { skip = 0; print "" }
    skip { next }
    { print; last = $0 }
    END {
      if (!done) { if (NR > 0 && last != "") print ""; put() }
    }' "$file" > "$file.new" && mv "$file.new" "$file"
}

# Sourced, it defines the functions and runs nothing.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then return 0; fi
echo "release/lib-release.sh is sourced by the release scripts; it is not run" >&2
exit 2
