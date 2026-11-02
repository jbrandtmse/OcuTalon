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
# record_field <file> <section> <field>
#                              prints the value of the first "<field>: <value>" line of one "## " section of a record (the section is given
#                              with or without its "## "); nothing when the file, the section or the line is missing
# production_stubs <tree>      scans the XData ProductionDefinition of every production class below <tree>/src (a path with a /Test/
#                              folder is not scanned). An item counts as enabled unless its Enabled is false or 0, and as a stub when its
#                              class sets Parameter STUB = 1, or sets no STUB and a superclass found in the tree is a stub. It prints "FOUND|<Production>|<Item>|<Class>"
#                              for each enabled stub and, always, "COUNTS|<items>|<productions>|<disabled stubs>|<enabled stubs>". Status 1
#                              when any enabled stub was found, 2 when the tree holds no production, 3 when the scan printed no result, else 0
# candidate_clone <dir> <version> <rc> <sha> <remote>
#                              makes (or keeps) a clone of the remote with full history and tags, on release/<version>-rc<rc>, in <dir>.
#                              Status 0 only when the clone's HEAD, the remote's branch and <sha> are the same commit; otherwise status 1
#                              and CLONE_WHY holds the reason (the author's checkout is never touched). An existing <dir> at <sha> is kept
# gh_repo <remote>             prints owner/repo of the remote when its URL is a github.com one; else OCUTALON_RELEASE_GH_REPO (a test
#                              seam); else status 1
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

# record_field <file> <section> <field>: see the header.
record_field() {
  local heading=$2
  case $heading in
    '## '*) ;;
    *) heading="## $heading" ;;
  esac
  awk -v h="$heading" -v f="$3" '
    { t = $0; sub(/[ \t\r]+$/, "", t) }
    !inside && t == h { inside = 1; next }
    inside && (/^## / || /^# /) { exit }
    inside && index(t, f ":") == 1 { v = substr(t, length(f) + 2); sub(/^[ \t]+/, "", v); print v; exit }' "$1" 2> /dev/null
}

# production_stubs <tree>: see the header.
production_stubs() {
  local tree=${1%/} files found keep_ifs=$IFS
  files=$(find "$tree/src" -name '*.cls' -type f 2> /dev/null | LC_ALL=C sort)
  if [ -z "$files" ]; then
    echo "COUNTS|0|0|0|0"
    return 2
  fi
  # one file per line, so a path with a space is still one file
  IFS='
'
  set -f
  # shellcheck disable=SC2086
  found=$(LC_ALL=C awk -v tree="$tree/" '
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
    function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
    function isstub(c,   n, parts, i) {
      if (c in seen) return 0
      seen[c] = 1
      if (c in stubv) return (stubv[c] == 1)
      n = split(sup[c], parts, ",")
      for (i = 1; i <= n; i++) if (parts[i] != "" && isstub(parts[i])) return 1
      return 0
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
    /^Parameter[ \t]+STUB[ \t]*(\([^)]*\))?[ \t]*(As[ \t]+[^ \t=]+[ \t]*)?=/ && cls != "" {
      v = $0
      sub(/^[^=]*=/, "", v)
      gsub(/[ \t\r;"]/, "", v)
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
        if (isstub(icls[k])) {
          if (ien[k]) { printf "FOUND|%s|%s|%s\n", iprod[k], iname[k], icls[k]; enabled++ }
          else disabled++
        }
      }
      printf "COUNTS|%d|%d|%d|%d\n", n, nprod, disabled, enabled
    }' $files)
  set +f
  IFS=$keep_ifs
  case $found in
    *COUNTS\|*) ;;
    *)
      echo "COUNTS|0|0|0|0"
      return 3
      ;;
  esac
  printf '%s\n' "$found"
  case $found in
    *FOUND\|*) return 1 ;;
    *COUNTS\|0\|0\|*) return 2 ;;
  esac
  return 0
}

# candidate_clone <dir> <version> <rc> <sha> <remote>: see the header.
CLONE_WHY=""
candidate_clone() {
  local dir=$1 ver=$2 rcn=$3 sha=$4 remote=$5 branch url rhead head
  CLONE_WHY=""
  branch=$(candidate_branch "$ver" "$rcn")
  rhead=$(git ls-remote "$remote" "refs/heads/$branch" < /dev/null 2> /dev/null | awk '{ print $1 }')
  if [ "$rhead" != "$sha" ]; then
    CLONE_WHY="$remote does not hold $branch at the cut commit"
    return 1
  fi
  head=$(git -C "$dir" rev-parse --verify --quiet HEAD < /dev/null 2> /dev/null)
  if [ "$head" != "$sha" ]; then
    rm -rf "$dir"
    url=$(git remote get-url "$remote" < /dev/null 2> /dev/null) || url=$remote
    if ! git clone -q --branch "$branch" "$url" "$dir" < /dev/null > /dev/null 2>&1; then
      rm -rf "$dir"
      CLONE_WHY="the clone of $branch from $remote failed"
      return 1
    fi
    head=$(git -C "$dir" rev-parse --verify --quiet HEAD < /dev/null 2> /dev/null)
    if [ "$head" != "$sha" ]; then
      rm -rf "$dir"
      CLONE_WHY="the clone's HEAD is not the cut commit"
      return 1
    fi
  fi
  return 0
}

# gh_repo <remote>: see the header.
gh_repo() {
  local url slug="" seam=${OCUTALON_RELEASE_GH_REPO:-}
  url=$(git remote get-url "$1" < /dev/null 2> /dev/null) || url=""
  url=${url%/}
  url=${url%.git}
  slug=$(printf '%s\n' "$url" | sed -n -E 's#^(https?://([^/@]*@)?|ssh://git@|git@)github\.com[:/]([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$#\3#p')
  if [ -z "$slug" ]; then
    slug=$(printf '%s\n' "$seam" | sed -n -E 's#^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$#\1#p')
  fi
  [ -n "$slug" ] || return 1
  printf '%s\n' "$slug"
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

# Sourced, it defines the functions and runs nothing.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then return 0; fi
echo "release/lib-release.sh is sourced by the release scripts; it is not run" >&2
exit 2
