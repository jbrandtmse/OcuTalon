# Helpers shared by the in-place upgrade test (test-install-upgrade.sh) and the release upgrade harness (release/upgrade-harness.sh).
# Sourced, not run: it defines functions and nothing else. It needs lib-live.sh sourced first (pass, fail, marker, check_session, dc).
#
#   check_installed <label> <version>   the marker, the image's version file, the installed IPM package and readiness all hold the version
#   stamp_version <manifest> <version>  prints the manifest with its first <Version> replaced by the version

# check_installed <label> <version>: the installed package, the marker and readiness all hold the version.
check_installed() {
  local label=$1 want=$2
  if [ "$(marker)" = "$want" ]; then
    pass "$label: the marker equals $want"
  else
    fail "$label: the marker is '$(marker)', wanted $want"
  fi
  if [ "$(dc exec -T iris cat /opt/ocutalon/version 2>/dev/null | tr -d '\r\n')" = "$want" ]; then
    pass "$label: the image's version file says $want"
  else
    fail "$label: the image's version file does not say $want"
  fi
  check_session "$label: installed package and readiness" OCUTALON "CHK|package|$want
CHK|ready|1" \
    'Set m=##class(%IPM.Storage.Module).NameOpen("ocutalon") Write !,"CHK|package|",$Select($IsObject(m):m.VersionString,1:"")' \
    'Write !,"CHK|ready|",##class(OcuTalon.Data.Public.Settings).Get("ready")' \
    'Halt'
}

# stamp_version <manifest> <version>: the manifest with its first <Version> replaced.
stamp_version() {
  awk -v v="$2" '!done && /<Version>/ { sub(/<Version>[^<]*<\/Version>/, "<Version>" v "</Version>"); done = 1 } { print }' "$1"
}
