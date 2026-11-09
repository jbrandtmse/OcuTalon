#!/usr/bin/env bash
# The helpers that the release scripts share (Story 11.3; AD-25, AD-29; REL-6). Sourced, not run: it defines functions and a few
# variables, and runs nothing. release/rehearse.sh, release/upgrade-harness.sh and the scripts of Stories 11.4, 11.5, 11.13 and 11.17
# use it; Story 15.3 reads the IPM artifact through it.
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
# notes_path <version> <rc>    prints release/records/<version>/rc<rc>-notes.md: the draft notes of a candidate, the one contract of the
#                              notes file (Story 11.4's checklist scans it; Story 11.13 writes it)
# record_write <file> <section file> [<heading>]
#                              writes the section file (its first line is its "## " title) into the record: it replaces the section with
#                              that title, up to the next heading or the end of the file, or appends it. A missing file (and its folder) is
#                              created with the heading, by default "# OcuTalon <v> rc<n>" for a path ending <v>/rc<n>.md and
#                              "# OcuTalon candidate record" otherwise. The other sections are kept byte for byte
# release_previous_tag <ref> <version> [<repository>]
#                              prints the previous release's tag: the highest v[0-9]* tag merged into <ref>, skipping a tag that points at
#                              <ref> and v<version>, with a pre-release (v1.1.0-rc1) before its release; nothing when there is none (the
#                              first release). The repository defaults to the current folder. Story 11.13's notes and Story 11.2's
#                              resolve_previous use it
# candidate_branch <version> <rc>
#                              prints release/<version>-rc<rc>: the name of a candidate (Story 11.5)
# release_tags [<remote>]      prints the v* tags of the current repository, locally and (with a remote) on the remote, one per line, sorted,
#                              without duplicates. An unreachable remote gives status 1 and the local tags only
# next_rc <version> <remote>   prints 1 more than the highest rc of the branches release/<version>-rc<n> found locally or on the remote
#                              (1 when there is none); status 1 when the remote cannot be read
# env_get <file> <key>, env_set <file> <key> <value>   key=value files (options, results of a run)
# detail_clean                 a result detail on one line of printable ASCII, 300 characters at most, with no pipe (stdin to stdout)
# release_state_root           prints the folder of the release sequences' states: ${OCUTALON_RELEASE_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/
#                              ocutalon/release}
# release_state_dir <v> <rc>   prints the state folder of one candidate: <state root>/<v>-rc<rc> (Story 11.17)
# sha256_file <file>           prints the 64-hex SHA-256 of a file (sha256sum, else shasum -a 256)
# ipm_artifact_path <v> <rc>   prints the IPM artifact of a candidate: <state folder>/ipm/ocutalon-<v>.tgz (Story 11.17; Story 15.3 reads it)
# ipm_artifact_check <tgz> <v> <tree> <root|src>
#                              prints one line per problem of the IPM artifact, and nothing when it is good: the top-level module.xml must name
#                              ocutalon and <v> and hold the FileCopy of the bundle, and every file of <tree>/src/ocutalon/csp/ must be in the
#                              artifact with the same bytes. The last argument, required, names the manifest the artifact was packed from and so
#                              where the bundle is: root (module.xml of the repository root) src/ocutalon/csp/<rel>, src (src/module.xml)
#                              ocutalon/csp/<rel>. Any other value is a problem, never a pass
# ipm_content_digest <tgz>     prints the SHA-256 of the sorted "<sha256>  <path>" lines of every regular file of the artifact: one value for
#                              every packaging of one tree, whatever the archive's own bytes
# ipm_unpack <tgz> <folder>    extracts the artifact into the folder; status 1 when it cannot be read as a gzip tar archive
# last_prompt_free_line <file> prints the last line of a session's plain output that is not blank and not a terminal prompt (NS>)
# record_section <file> <heading>
#                              prints one "## " section of a record or notes file, its heading line included, up to the next "## " or "# " line
# record_field <file> <heading> <field>
#                              prints the text after "<field>: " on the first such line of that section (Story 11.14)
# production_stubs <tree>      scans <tree>/src for the production classes (an XData ProductionDefinition; a path with a /Test/ folder is not
#                              scanned) and prints "FOUND|<production>|<item>|<class>" for each enabled item whose class, or an in-tree
#                              superclass, carries Parameter STUB = 1, then "COUNTS|<enabled items>|<productions>|<stub items>|<enabled stubs>".
#                              Superclasses go left to right, depth first, and a class's own STUB value wins. An item is enabled unless its
#                              Enabled is false or 0. Status 1 when an enabled stub is found, 3 when the scan printed no COUNTS line (Story 11.14)
# candidate_clone <dir> <branch> <sha> [web]
#                              clones this repository's <branch> into <dir> (no network), copies in every local tag, and checks that HEAD is
#                              <sha>; with web it also runs ensure_web_bundle in the clone. Status 1 and CLONE_WHY when it fails (Story 11.14)
# gh_repo <remote>             prints owner/repo of the remote's github.com https or ssh URL; for a local-path URL, OCUTALON_RELEASE_GH_REPO
#                              (owner/repo); otherwise status 1 (Story 11.14)
# ci_runs <repo> <sha> <event> <branch>
#                              runs gh run list for the branch and commit and prints "<id><TAB><workflow><TAB><status><TAB><conclusion>" for
#                              each run whose headSha is <sha>. Status 127 when gh is not installed, else gh's own non-zero status (Story 11.14)
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

# --- the state and the IPM artifact (Story 11.17) ---

release_state_root() { printf '%s\n' "${OCUTALON_RELEASE_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/ocutalon/release}"; }

release_state_dir() { printf '%s/%s-rc%s\n' "$(release_state_root)" "$1" "$2"; }

# release_sha256_tool: the command that prints "<hex>  <name>" lines.
release_sha256_tool() {
  if command -v sha256sum > /dev/null 2>&1; then echo sha256sum; else echo "shasum -a 256"; fi
}

sha256_file() { $(release_sha256_tool) < "$1" | awk '{ print $1 }'; }

ipm_artifact_path() { printf '%s/ipm/ocutalon-%s.tgz\n' "$(release_state_dir "$1" "$2")" "$1"; }

# ipm_unpack <tgz> <folder>: extracts the artifact into the folder.
ipm_unpack() {
  mkdir -p "$2" && tar -xzf "$1" -C "$2" < /dev/null 2> /dev/null
}

ipm_artifact_check() {
  local tgz=$1 ver=$2 tree=$3 layout=${4:-} csp d f rel mx
  case $layout in
    root) csp=src/ocutalon/csp ;;
    src) csp=ocutalon/csp ;;
    *)
      echo "cannot be checked (the layout '$layout' is not root or src)"
      return 0
      ;;
  esac
  d=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-ipmchk.XXXXXX" 2> /dev/null) || {
    echo "cannot be checked (no temporary folder)"
    return 0
  }
  if ! ipm_unpack "$tgz" "$d"; then
    echo "cannot be read as a gzip tar archive"
    rm -rf "$d"
    return 0
  fi
  mx=$d/module.xml
  if [ ! -f "$mx" ]; then
    echo "has no top-level module.xml"
  else
    grep -qF "<Name>ocutalon</Name>" "$mx" || echo "holds a module.xml that does not name ocutalon"
    grep -qF "<Version>$ver</Version>" "$mx" || echo "holds a module.xml that does not read version $ver"
    grep -qF "<FileCopy Name=\"$csp/\"" "$mx" || echo "holds a module.xml with no FileCopy of $csp/"
  fi
  # The Python resources and the requirements of an IPM install (Story 19.6, U-294): every resource of the candidate's src/ocutalon/python, with
  # the candidate's bytes, and a FileCopy that copies it to ${mgrdir}python/<file>; and a top-level requirements.txt that equals the candidate's.
  if [ -d "$tree/src/ocutalon/python" ] && [ -f "$mx" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      rel=${csp%/csp}/python/$(basename "$f")
      grep -qF "<FileCopy Name=\"$rel\" Target=\"\${mgrdir}python/$(basename "$f")\"" "$mx" || echo "holds a module.xml with no FileCopy of $rel"
      if [ ! -f "$d/$rel" ]; then
        echo "lacks the Python resource $rel"
      elif ! cmp -s "$f" "$d/$rel"; then
        echo "holds a different $rel than the candidate"
      fi
    done <<EOT
$(find "$tree/src/ocutalon/python" -type f -name '*.py' | LC_ALL=C sort)
EOT
  fi
  if [ -f "$tree/requirements.txt" ]; then
    if [ ! -f "$d/requirements.txt" ]; then
      echo "has no top-level requirements.txt"
    elif ! cmp -s "$tree/requirements.txt" "$d/requirements.txt"; then
      echo "holds a different requirements.txt than the candidate"
    fi
  fi
  if [ -d "$tree/src/ocutalon/csp" ]; then
    while IFS= read -r f; do
      rel=${f#"$tree/src/ocutalon/csp/"}
      if [ ! -f "$d/$csp/$rel" ]; then
        echo "lacks the bundle file $csp/$rel"
      elif ! cmp -s "$f" "$d/$csp/$rel"; then
        echo "holds a different $csp/$rel than the candidate"
      fi
    done <<EOT
$(find "$tree/src/ocutalon/csp" -type f | LC_ALL=C sort)
EOT
  fi
  rm -rf "$d"
  return 0
}

ipm_content_digest() {
  local d sum
  d=$(mktemp -d "${TMPDIR:-/tmp}/ocutalon-ipmdig.XXXXXX") || return 1
  if ! ipm_unpack "$1" "$d"; then
    rm -rf "$d"
    return 1
  fi
  sum=$(
    cd "$d" || exit 1
    find . -type f -print0 | xargs -0 $(release_sha256_tool) | sed 's|  \./|  |' | LC_ALL=C sort | $(release_sha256_tool) | awk '{ print $1 }'
  )
  rm -rf "$d"
  [ -n "$sum" ] || return 1
  printf '%s\n' "$sum"
}

last_prompt_free_line() {
  awk '{ line[NR] = $0 } END {
    n = NR
    while (n > 0 && (line[n] ~ /^[ \t]*$/ || line[n] ~ /^[%A-Za-z0-9]+>[ \t]*$/)) n--
    if (n > 0) print line[n] }' "$1"
}

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

notes_path() { printf 'release/records/%s/rc%s-notes.md\n' "$1" "$2"; }

candidate_branch() { printf 'release/%s-rc%s\n' "$1" "$2"; }

# release_tags [<remote>]: see the header.
release_tags() {
  local remote=${1:-} out=0 remote_tags=""
  if [ -n "$remote" ]; then
    remote_tags=$(git ls-remote --tags "$remote" 'refs/tags/v*' < /dev/null 2> /dev/null) || out=1
  fi
  {
    git tag --list 'v*' < /dev/null 2> /dev/null
    printf '%s\n' "$remote_tags" | awk 'NF >= 2 { t = $2; sub(/^refs\/tags\//, "", t); sub(/\^\{\}$/, "", t); print t }'
  } | grep -v '^$' | sort -u
  return $out
}

# next_rc <version> <remote>: see the header.
next_rc() {
  local ver=$1 remote=$2 out=0 remote_heads="" highest
  remote_heads=$(git ls-remote --heads "$remote" "refs/heads/release/$ver-rc*" < /dev/null 2> /dev/null) || out=1
  highest=$(
    {
      git for-each-ref --format='%(refname:short)' "refs/heads/release/$ver-rc*" < /dev/null 2> /dev/null
      printf '%s\n' "$remote_heads" | awk 'NF >= 2 { sub(/^refs\/heads\//, "", $2); print $2 }'
    } | sed -n "s|^release/$ver-rc\\([0-9][0-9]*\\)\$|\\1|p" | sort -n | tail -n 1
  )
  echo $((10#${highest:-0} + 1))
  return $out
}

# release_previous_tag <ref> <version> [<repository>]: see the header.
release_previous_tag() {
  local ref=$1 ver=$2 repo=${3:-.} skip tag
  skip=$(git -C "$repo" tag --points-at "$ref" 2> /dev/null)
  while IFS= read -r tag; do
    [ -n "$tag" ] || continue
    [ "$tag" != "v$ver" ] || continue
    if printf '%s\n' "$skip" | grep -qxF -- "$tag"; then continue; fi
    printf '%s\n' "$tag"
    return 0
  done <<EOT
$(git -C "$repo" -c versionsort.suffix=- tag --merged "$ref" --list 'v[0-9]*' --sort=-version:refname 2> /dev/null)
EOT
  return 0
}

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

# record_section <file> <heading>: see the header.
record_section() {
  awk -v h="$2" '
    { t = $0; sub(/[ \t\r]+$/, "", t) }
    !inside && t == h { inside = 1; print; next }
    inside && (/^## / || /^# /) { exit }
    inside { print }' "$1" 2> /dev/null
}

# record_field <file> <heading> <field>: see the header.
record_field() {
  record_section "$1" "$2" | awk -v f="$3" '
    { t = $0; sub(/[ \t\r]+$/, "", t) }
    NR > 1 && index(t, f ": ") == 1 { print substr(t, length(f) + 3); exit }'
}

# production_stubs <tree>: see the header.
production_stubs() {
  local tree=${1%/} files found
  files=$(find "$tree/src" -name '*.cls' -type f 2> /dev/null | LC_ALL=C sort)
  if [ -z "$files" ]; then
    return 3
  fi
  # one file per line, so that a path with a space is still one file
  found=$(
    IFS='
'
    set -f
    # shellcheck disable=SC2086
    LC_ALL=C awk -v tree="$tree/" '
      function uncomment(s,   out, i, j) {
        out = ""
        while (s != "") {
          if (incomment) {
            j = index(s, "-->")
            if (j == 0) return out
            s = substr(s, j + 3)
            incomment = 0
          } else {
            i = index(s, "<!--")
            if (i == 0) { out = out s; s = "" }
            else { out = out substr(s, 1, i - 1); s = substr(s, i + 4); incomment = 1 }
          }
        }
        return out
      }
      function attr(tag, name,   v) {
        if (match(tag, "[ \t]" name "=\"[^\"]*\"")) {
          v = substr(tag, RSTART, RLENGTH)
          sub(/^[^=]*="/, "", v)
          sub(/"$/, "", v)
          return v
        }
        if (match(tag, "[ \t]" name "=\047[^\047]*\047")) {
          v = substr(tag, RSTART, RLENGTH)
          sub("^[^=]*=\047", "", v)
          sub("\047$", "", v)
          return v
        }
        return ""
      }
      function resolve(c,   n, parts, i, r) {
        if (c in seen) return -1
        seen[c] = 1
        if (c in stubv) return (stubv[c] == 1) ? 1 : 0
        n = split(sup[c], parts, ",")
        for (i = 1; i <= n; i++) {
          if (parts[i] == "") continue
          r = resolve(parts[i])
          if (r != -1) return r
        }
        return -1
      }
      FNR == 1 {
        rel = substr(FILENAME, length(tree) + 1)
        skip = (index("/" rel, "/Test/") > 0)
        cls = ""; inx = 0; incomment = 0; buf = ""; prod = ""
      }
      /^[ \t]*\/\// { next }
      /^Class[ \t]+/ && cls == "" {
        line = $0
        cls = $2
        while (line ~ /Extends[ \t]*\(/ && line !~ /\)/) {
          if ((getline nxt) <= 0) break
          line = line " " nxt
        }
        if (match(line, /Extends[ \t]*/)) {
          rest = substr(line, RSTART + RLENGTH)
          sub(/[\[{].*$/, "", rest)
          gsub(/[()]/, "", rest)
          gsub(/[ \t\r]/, "", rest)
          sup[cls] = rest
        }
        next
      }
      /^[ \t]*Parameter[ \t]+STUB[ \t]*(\([^)]*\))?[ \t]*(As[ \t]+[^ \t=\[]+[ \t]*)?(\[[^\]]*\][ \t]*)?=/ && cls != "" {
        v = $0
        sub(/^[^=]*=/, "", v)
        sub(/[;\/].*$/, "", v)
        gsub(/[ \t\r"]/, "", v)
        stubv[cls] = v
        next
      }
      /^XData[ \t]+ProductionDefinition/ { inx = 1; buf = ""; prod = cls; next }
      inx && /^}/ { inx = 0; next }
      inx && !skip {
        buf = buf " " uncomment($0) " "
        while (match(buf, /<(Production|Item)[ \t\r]/)) {
          rest = substr(buf, RSTART)
          e = index(rest, ">")
          if (e == 0) { buf = rest; break }
          tag = substr(rest, 1, e)
          buf = substr(rest, e + 1)
          if (tag ~ /^<Production/) {
            prod = attr(tag, "Name"); if (prod == "") prod = cls
            nprod++
          } else {
            n++
            iprod[n] = prod; iname[n] = attr(tag, "Name"); icls[n] = attr(tag, "ClassName")
            en = tolower(attr(tag, "Enabled"))
            ien[n] = (en == "false" || en == "0") ? 0 : 1
          }
        }
        if (!match(buf, /<(Production|Item)/)) buf = ""
      }
      END {
        for (k = 1; k <= n; k++) {
          delete seen
          if (ien[k]) nen++
          if (resolve(icls[k]) == 1) {
            nstub++
            if (ien[k]) { printf "FOUND|%s|%s|%s\n", iprod[k], iname[k], icls[k]; enabled++ }
          }
        }
        if (nprod > 0) printf "COUNTS|%d|%d|%d|%d\n", nen, nprod, nstub, enabled
      }' $files
  )
  case $found in
    *COUNTS\|*) ;;
    *)
      return 3
      ;;
  esac
  printf '%s\n' "$found"
  case $found in
    *FOUND\|*) return 1 ;;
  esac
  return 0
}

# candidate_clone <dir> <branch> <sha> [web]: see the header.
CLONE_WHY=""
candidate_clone() {
  local dir=$1 br=$2 sha=$3 web=${4:-} head out
  CLONE_WHY=""
  rm -rf "$dir"
  if ! git clone -q --branch "$br" "$release_lib_root" "$dir" < /dev/null > /dev/null 2>&1; then
    rm -rf "$dir"
    CLONE_WHY="the clone of $br failed"
    return 1
  fi
  if ! git -C "$dir" fetch -q "$release_lib_root" 'refs/tags/*:refs/tags/*' < /dev/null > /dev/null 2>&1; then
    rm -rf "$dir"
    CLONE_WHY="the tags could not be copied into the clone"
    return 1
  fi
  head=$(git -C "$dir" rev-parse --verify --quiet HEAD < /dev/null 2> /dev/null)
  if [ "$head" != "$sha" ]; then
    rm -rf "$dir"
    CLONE_WHY="the clone's HEAD is not the cut commit"
    return 1
  fi
  if [ -n "$web" ]; then
    if ! type ensure_web_bundle > /dev/null 2>&1; then
      rm -rf "$dir"
      CLONE_WHY="the web dependencies cannot be installed here"
      return 1
    fi
    out=$(cd "$dir" && ensure_web_bundle < /dev/null 2>&1)
    if [ $? -ne 0 ]; then
      rm -rf "$dir"
      out=$(printf '%s\n' "$out" | tail -n 1)
      CLONE_WHY=${out#FAIL }
      return 1
    fi
  fi
  return 0
}

# gh_repo <remote>: see the header.
gh_repo() {
  local url slug seam=${OCUTALON_RELEASE_GH_REPO:-}
  url=$(git remote get-url "$1" < /dev/null 2> /dev/null) || url=""
  url=${url%/}
  url=${url%.git}
  slug=$(printf '%s\n' "$url" | sed -n -E 's#^(https?://([^/@]*@)?|ssh://git@|git@)github\.com[:/]([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$#\3#p')
  if [ -z "$slug" ]; then
    case $url in
      /* | ./* | ../* | file://*)
        slug=$(printf '%s\n' "$seam" | sed -n -E 's#^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$#\1#p')
        ;;
    esac
  fi
  [ -n "$slug" ] || return 1
  printf '%s\n' "$slug"
}

# ci_runs <repo> <sha> <event> <branch>: see the header.
ci_runs() {
  local json
  command -v gh > /dev/null 2>&1 || return 127
  json=$(gh run list --repo "$1" --branch "$4" --commit "$2" --event "$3" --limit 50 \
    --json databaseId,workflowName,status,conclusion,headSha < /dev/null 2> /dev/null) || return $?
  printf '%s' "$json" | node -e '
    let s = "";
    process.stdin.on("data", (d) => { s += d; });
    process.stdin.on("end", () => {
      let runs;
      try { runs = JSON.parse(s); } catch (e) { process.exit(65); }
      if (!Array.isArray(runs)) process.exit(65);
      for (const r of runs) {
        if (r.headSha !== process.argv[1]) continue;
        const f = (v) => String(v == null ? "" : v).replace(/[\t\r\n]/g, " ");
        console.log([f(r.databaseId), f(r.workflowName), f(r.status), f(r.conclusion)].join("\t"));
      }
    });' "$2" || return $?
}

# Sourced, it defines the functions and runs nothing.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then return 0; fi
echo "release/lib-release.sh is sourced by the release scripts; it is not run" >&2
exit 2
