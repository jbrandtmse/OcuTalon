# CLAUDE.md

## IRIS reference source: `irislib/` and `irissys/`

These folders hold InterSystems source exported from the `ocutalon-aihub-test` IRIS instance (2026.3.0AI Early Access) for reference only:

- `irislib/`: the HSCUSTOM namespace, including the `%`, `HS*` and `Ens*` system packages
- `irissys/`: the `%SYS` namespace (`%` packages plus `SYS`, `Config`, `Security`, `OAuth2` and the system routines)

Rules:

- Read them to look up how system classes, macros and APIs work. Do not modify, delete or add files in them.
- Never load, import or compile anything from them into IRIS.
- Our own classes go elsewhere in the repo, in our own packages, never under the system package names found here.
- Both folders are gitignored and must never be committed (InterSystems code from an Early Access build).
- To refresh them, re-export with the IRIS MCP `iris_doc_export` tool against `ocutalon-aihub-test` rather than editing files by hand.

### Searching them

Because both folders are gitignored, a search started from the repo root skips them silently: the Grep and Glob tools, `rg` and `grep -r` all return nothing from them. No hits from a root search does not mean a class or macro doesn't exist. Always name the folder as the search path:

- Grep tool: set `path` to `irislib` (or `irissys`).
- Shell: `rg -n 'pattern' irislib irissys`, or `rg --no-ignore` from the root.
- Find a file by name: `find irislib -name 'DynamicObject.cls'`.

Paths follow the class name, so go straight to the file when you know it: `%Library.DynamicObject` is `irislib/%Library/DynamicObject.cls`, and macro includes sit at the top level (`irislib/%occStatus.inc`). Search `irislib` first, since it has almost everything; use `irissys` for the %SYS-only packages. The `%` classes are in both, so searching both folders returns each of them twice.
