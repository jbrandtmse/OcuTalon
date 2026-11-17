#!/usr/bin/env bash
# The capture of the fallback replies of an eval run (DW-1421; AD-8, AD-22). eval/run.sh sources this file, and only when OCUTALON_EVAL_CAPTURE_DIR is set and
# not empty (the Planner's key-holder sets it for --release-candidate; no workflow, compose file or class default does), and calls capture_fallbacks after the
# run's result is final and before its exit trap tears the stack down, because the raw replies exist only on that stack:
#   OCUTALON_EVAL_CAPTURE_DIR=<an existing evidence folder outside the checkout> bash eval/run.sh --release-candidate [--on-mock]
# capture_fallbacks <folder>:
#   - resolves the folder (cd and pwd -P) and refuses, with the line "CAPTURE refused: ..." and no session and no file, one that is missing or that is the checkout or
#     below it, or another checkout of the same repository that git lists (the main checkout or a worktree) or below one (a raw reply is never written inside a checkout);
#   - runs one IRIS session in OCUTALON that calls OcuTalon.Test.Eval.CaptureTool, which reads the raw reply of every reply that a fallback decision of kind decide or
#     diagnose got, checks it again with Decide.Recheck and writes one file per reply, plus summary.json, into a folder of the container;
#   - copies each file whose name is made of letters, digits, dots, hyphens and underscores into the folder, with the run's own cat, and removes the folder
#     of the container; a file that was named and not copied (a failed cat, an empty copy or an unsafe name) is counted, and what a failed copy left is removed;
#   - prints counts and rule names only (the CAPTURE lines below): never a reply text. A value that the container gave and that holds a character outside
#     [A-Za-z0-9 #:;<>.,()_-] is printed as (withheld).
# It reads no key and no environment file, calls no model and no runner, and sends no message. It returns 0 (also for a refusal) or 1 when the capture failed
# (the session printed no result line; the caller says so), and it never changes the verdict or the exit code of the run: the caller goes on.
#   CAPTURE <n> fallback decision(s) (decide <d>, diagnose <g>), <r> reply(s), <f> file(s)
#   CAPTURE reason <reason>: <n>
#   CAPTURE rule <rule> field <field or ->: <n>
#   CAPTURE case <case> rule <rule>: <n>
#   CAPTURE accepted-without-confidence outcome <outcome>: <n> (a decide decision accepted without a confidence: the attention floor of the triage-accept ruling)
#   CAPTURE copy failed: <n> file(s) were not copied (only when a named file was not copied or came out empty; a count, before the folder line)
#   CAPTURE folder <the folder given>
# Run directly, it prints a usage line and exits 2.

CAPTURE_CONTAINER_DIR=/tmp/ocutalon-capture

# capture_value <text>: the text, or (withheld) when it holds a character outside [A-Za-z0-9 #:;<>.,()_-].
capture_value() {
  (
    LC_ALL=C
    case $1 in
      *[!A-Za-z0-9\ \#:\;\<\>.,\(\)_-]*) printf '(withheld)' ;;
      *) printf '%s' "$1" ;;
    esac
  )
}

# capture_inside <folder>: 0 when the resolved folder is the checkout or below it, or a checkout of the same repository that git lists or below one.
capture_inside() {
  local here line top
  here=$(cd "$root" && pwd -P) || return 0
  case $1/ in
    "$here"/*) return 0 ;;
  esac
  while IFS= read -r line; do
    case $line in
      'worktree '*)
        top=$(CDPATH= cd -- "${line#worktree }" 2> /dev/null && pwd -P) || continue
        case $1/ in
          "$top"/*) return 0 ;;
        esac
        ;;
    esac
  done < <(git -C "$here" worktree list --porcelain 2> /dev/null)
  return 1
}

# capture_fallbacks <folder>: see the header.
capture_fallbacks() {
  local given=$1 resolved out kind a b c d e name field failed=0
  if [ -z "$given" ] || [ ! -d "$given" ]; then
    echo "CAPTURE refused: the evidence folder does not exist (make it first, outside the checkout)"
    return 0
  fi
  resolved=$(CDPATH= cd -- "$given" && pwd -P) || {
    echo "CAPTURE refused: the evidence folder cannot be entered"
    return 0
  }
  if capture_inside "$resolved"; then
    echo "CAPTURE refused: the evidence folder is inside the checkout"
    return 0
  fi
  out=$(printf '%s\n' \
    'Write !,"CHK|started|1"' \
    "Set sc=##class(OcuTalon.Test.Eval.CaptureTool).Run(\"$CAPTURE_CONTAINER_DIR/\",\"\",.summary)" \
    'If $SYSTEM.Status.IsError(sc) { Write !,"CHK|error|",$Piece($SYSTEM.Status.GetErrorText(sc),":",1) Halt }' \
    'Do ##class(OcuTalon.Test.Eval.CaptureTool).Print(summary)' \
    'Write !,"CHK|run|1"' \
    'Halt' | iris_script OCUTALON)
  case $out in
    *CHK\|run\|1*) ;;
    *)
      dc exec -T iris rm -rf "$CAPTURE_CONTAINER_DIR" > /dev/null 2>&1
      return 1
      ;;
  esac
  while IFS='|' read -r _ kind a b c d e; do
    case $kind in
      decisions)
        echo "CAPTURE $(capture_value "$a") fallback decision(s) (decide $(capture_value "$b"), diagnose $(capture_value "$c")), $(capture_value "$d") reply(s), $(capture_value "$e") file(s)"
        ;;
      reason) echo "CAPTURE reason $(capture_value "$a"): $(capture_value "$b")" ;;
      rule)
        field=$(capture_value "$b")
        echo "CAPTURE rule $(capture_value "$a") field $field: $(capture_value "$c")"
        ;;
      case) echo "CAPTURE case $(capture_value "$a") rule $(capture_value "$b"): $(capture_value "$c")" ;;
      accepted) echo "CAPTURE accepted-without-confidence outcome $(capture_value "$a"): $(capture_value "$b")" ;;
      file)
        name=$a
        case $name in
          '') ;;
          *[!A-Za-z0-9._-]*) failed=$((failed + 1)) ;;
          *)
            if ! dc exec -T iris cat "$CAPTURE_CONTAINER_DIR/$name" < /dev/null > "$resolved/$name" 2> /dev/null || [ ! -s "$resolved/$name" ]; then
              rm -f "$resolved/$name"
              failed=$((failed + 1))
            fi
            ;;
        esac
        ;;
    esac
  done <<< "$out"
  if [ "$failed" -gt 0 ]; then
    echo "CAPTURE copy failed: $failed file(s) were not copied"
  fi
  echo "CAPTURE folder $given"
  dc exec -T iris rm -rf "$CAPTURE_CONTAINER_DIR" > /dev/null 2>&1
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "usage: OCUTALON_EVAL_CAPTURE_DIR=<evidence folder outside the checkout> bash eval/run.sh --release-candidate [--on-mock]" >&2
  exit 2
fi
