#!/usr/bin/env python3
"""The licence gate and the notices of the Docker image's Python packages (Story 34.2; AD-23).

  gate.py check <dir> [<constraints>]
                                   list every distribution installed in <dir> (a pip --target folder) with its licence, and exit 1
                                   when one is outside the allowed set of allowed.txt, or when <dir> holds no distribution; with a
                                   constraints file (name==version lines, as pip -c reads them) it also exits 1 for an installed
                                   distribution that the file does not name or names at another version, and for a pin of the file
                                   that is not installed (Story 34.3, DW-738)
  gate.py notices <dir> <file>     write <file>: the licence texts and credits of every distribution in <dir>

The allowed set lives in allowed.txt beside this script (its format is described there). ASCII only; Python 3 standard library only.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CREDITS = (
    "Portions of this software are copyright (c) The FreeType Project (www.freetype.org). All rights reserved.",
    "This software is based in part on the work of the Independent JPEG Group.",
)
NOT_LICENCE_NAME = re.compile(r"^(notice|authors?)", re.I)
LICENCE_NAME = re.compile(r"^(licen[cs]e|copying|unlicense)", re.I)
NOTICE_NAME = re.compile(r"^(notice|thirdpartynotices)", re.I)


def read(path):
    with open(path, "rb") as handle:
        return handle.read().decode("utf-8", "replace")


def load_allowed(path):
    """The rules of allowed.txt: (allowed ids by lower case, aliases by lower case, texts [(id, regex)], ignored phrases,
    documentation-only ids by lower case)."""
    allowed, aliases, texts, ignored, docs = {}, {}, [], set(), set()
    for number, line in enumerate(read(path).splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        word, _, rest = line.partition(" ")
        if word == "allow" and rest:
            allowed[rest.lower()] = rest
        elif word == "alias" and " = " in rest:
            declared, _, ident = rest.rpartition(" = ")
            aliases[declared.strip().lower()] = ident.strip()
        elif word == "text" and " :: " in rest:
            ident, _, regex = rest.partition(" :: ")
            texts.append((ident.strip(), re.compile(regex.strip())))
        elif word == "ignore" and rest:
            ignored.add(rest.strip().lower())
        elif word == "docs" and rest:
            docs.add(rest.strip().lower())
        else:
            raise SystemExit("licence gate: %s:%d is not a rule" % (path, number))
    return allowed, aliases, texts, ignored, docs


def parse_metadata(text):
    """The header fields of a METADATA file: {name: [values]} (the body after the first blank line is not read)."""
    fields = {}
    for line in text.splitlines():
        if not line.strip():
            break
        if line[0] in " \t":
            continue
        name, _, value = line.partition(":")
        fields.setdefault(name.strip().lower(), []).append(value.strip())
    return fields


def declared_licence(fields):
    """What the package declares, every declaration of it: its License-Expression, the first line of its License (when that is at
    most 200 characters and not UNKNOWN) and each of its License :: classifiers, joined with AND (each in parentheses when there are
    several), so that a licence named anywhere must be allowed; "" when it declares none."""
    parts = [value for value in fields.get("license-expression", []) if value]
    parts += [value for value in fields.get("license", []) if value and len(value) <= 200 and value.upper() != "UNKNOWN"]
    parts += [value.split("::")[-1].strip() for value in fields.get("classifier", []) if value.startswith("License ::")]
    unique = []
    for part in parts:
        if part not in unique:
            unique.append(part)
    if len(unique) == 1:
        return unique[0]
    return " AND ".join("(%s)" % part for part in unique)


RANK = {"ok": 0, "files": 1, "no": 2}


def evaluate(expression, rules):
    """(verdict, how): verdict 'ok', 'files' (every other name is allowed, but a phrase needs the licence files) or 'no'.

    The expression is read with parentheses, AND (also a comma or a semicolon) binding tighter than OR: an AND is as bad as its worst
    side; an OR is 'ok' when one side is, else 'no' when one side is (a phrase never stands in for a refused alternative), else
    'files'. A documentation-only licence (a docs line) is 'no' here. Anything that does not parse (an unbalanced parenthesis, an
    operator with no name on one side) is 'no'."""
    allowed, aliases, _, ignored, _ = rules
    text = expression
    for alias in sorted((a for a in aliases if re.search(r"[,;()]", a)), key=len, reverse=True):
        text = re.sub(r"(?<![\w.-])" + re.escape(alias) + r"(?![\w.-])", aliases[alias], text, flags=re.I)
    items = [re.sub(r"\s+", " ", item).strip() for item in re.split(r"(\(|\)|(?<![^\s()])(?:AND|OR)(?![^\s()])|[,;])", text)]
    items = [item for item in items if item]
    state = {"at": 0}

    def peek():
        return items[state["at"]] if state["at"] < len(items) else None

    def name_verdict(token):
        token = aliases.get(token.lower(), token)
        if token.lower() in allowed:
            return "ok"
        return "files" if token.lower() in ignored else "no"

    def worst(left, right):
        return max(left, right, key=RANK.get)

    def either(left, right):
        if "ok" in (left, right):
            return "ok"
        return "no" if "no" in (left, right) else "files"

    def parse_atom():
        item = peek()
        if item == "(":
            state["at"] += 1
            inner = parse_or()
            if peek() != ")":
                raise ValueError("unbalanced")
            state["at"] += 1
            return inner
        if item is None or item in (")", "AND", "OR", ",", ";"):
            raise ValueError("a name is missing")
        state["at"] += 1
        return name_verdict(item)

    def parse_and():
        verdict = parse_atom()
        while peek() in ("AND", ",", ";"):
            state["at"] += 1
            verdict = worst(verdict, parse_atom())
        return verdict

    def parse_or():
        verdict = parse_and()
        while peek() == "OR":
            state["at"] += 1
            verdict = either(verdict, parse_and())
        return verdict

    try:
        verdict = parse_or()
        if state["at"] != len(items):
            return "no"
    except ValueError:
        return "no"
    return verdict or "no"


def normalise(text):
    text = re.sub(r"(?m)^[ \t]*(//+|/\*+|\*+/?|#+)", " ", text)
    text = text.lower().replace("\u2018", "'").replace("\u2019", "'").replace("\u201c", '"').replace("\u201d", '"')
    return re.sub(r"\s+", " ", text)


def licence_files(info):
    """The licence files of a .dist-info folder: everything under licenses/, and LICENSE/COPYING files beside METADATA."""
    found = []
    for folder, _, names in os.walk(os.path.join(info, "licenses")):
        found.extend(os.path.join(folder, name) for name in names)
    for name in os.listdir(info):
        path = os.path.join(info, name)
        if os.path.isfile(path) and LICENCE_NAME.match(name):
            found.append(path)
    return sorted(found)


def notice_files(info):
    """The NOTICE files beside METADATA (an Apache-2.0 package asks that they travel with its licence)."""
    return sorted(os.path.join(info, name) for name in os.listdir(info) if name.lower().startswith("notice") and os.path.isfile(os.path.join(info, name)))


def package_licence_files(target, info):
    """The licence and notice files that the wheel installed outside its .dist-info folder, as its RECORD lists them (onnxruntime keeps
    its LICENSE and ThirdPartyNotices.txt in its package folder): a file named LICENSE, COPYING, NOTICE or ThirdPartyNotices (any
    case, any extension but .py) under target."""
    record = os.path.join(info, "RECORD")
    if not os.path.isfile(record):
        return []
    own = os.path.basename(info) + "/"
    found = []
    for line in read(record).splitlines():
        path = line.split(",")[0].strip()
        parts = path.split("/")
        name = parts[-1]
        if not path or path.startswith(own) or path.startswith("/") or ".." in parts or name.lower().endswith(".py"):
            continue
        if LICENCE_NAME.match(name) or NOTICE_NAME.match(name):
            full = os.path.join(target, *parts)
            if os.path.isfile(full):
                found.append(full)
    return sorted(found)


def recognised(path, rules):
    """The allowed identifiers (documentation-only ones included) whose text the file holds."""
    allowed, _, texts, _, docs = rules
    text = normalise(read(path))
    return [ident for ident, regex in texts if (ident.lower() in allowed or ident.lower() in docs) and regex.search(text)]


def distributions(target):
    """[(name, version, info folder, METADATA fields)] for every .dist-info folder of target, by name."""
    found = []
    for entry in sorted(os.listdir(target)):
        info = os.path.join(target, entry)
        if not (entry.endswith(".dist-info") and os.path.isdir(info)):
            continue
        meta = os.path.join(info, "METADATA")
        fields = parse_metadata(read(meta)) if os.path.isfile(meta) else {}
        base = entry[: -len(".dist-info")]
        name = (fields.get("name") or [base.rsplit("-", 1)[0]])[0]
        version = (fields.get("version") or [base.rsplit("-", 1)[-1]])[0]
        found.append((name, version, info, fields))
    return sorted(found, key=lambda item: item[0].lower())


def canonical(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def load_constraints(path):
    """{canonical name: (name, version)} of a constraints file: one name==version per line, # comments and blank lines skipped.
    Raises SystemExit for any other line or a name pinned twice."""
    pins = {}
    for number, line in enumerate(read(path).splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = re.match(r"^([A-Za-z0-9][A-Za-z0-9._-]*)==([A-Za-z0-9][A-Za-z0-9._+!-]*)$", line)
        if not match or canonical(match.group(1)) in pins:
            raise SystemExit("licence gate: %s:%d is not a name==version pin, or its name is pinned twice" % (path, number))
        pins[canonical(match.group(1))] = (match.group(1), match.group(2))
    return pins


def constraint_failures(dists, pins):
    """The lines that tell how the installed distributions differ from the pins: an installed one that is not pinned or at another
    version, and a pin that is not installed."""
    lines = []
    seen = set()
    for name, version, _, _ in dists:
        key = canonical(name)
        seen.add(key)
        if key not in pins:
            lines.append("FAIL constraints: %s %s is installed but not pinned" % (name, version))
        elif pins[key][1] != version:
            lines.append("FAIL constraints: %s is installed at %s but pinned at %s" % (name, version, pins[key][1]))
    for key in sorted(pins):
        if key not in seen:
            lines.append("FAIL constraints: %s==%s is pinned but not installed" % pins[key])
    return lines


def check(target, rules, constraints=None):
    dists = distributions(target)
    if not dists:
        print("FAIL licence gate: %s holds no installed distribution" % target)
        return 1
    failures = 0
    print("licence gate: %d distributions in %s" % (len(dists), target))
    for name, version, info, fields in dists:
        declared = declared_licence(fields)
        files = [path for path in licence_files(info) if not NOT_LICENCE_NAME.match(os.path.basename(path))]
        via, verdict = "declaration", "no"
        if declared:
            verdict = evaluate(declared, rules)
        else:
            via = "files"
            verdict = "files"
        if verdict == "files":
            via = "files"
            unread = [os.path.relpath(path, info) for path in files if not recognised(path, rules)]
            verdict = "ok" if files and not unread else "no"
            if verdict == "no":
                via = "files (%s)" % (("not read as an allowed licence: " + ", ".join(unread[:5])) if unread else "none shipped")
        print("%s %s %s | declared: %s | by %s" % ("OK  " if verdict == "ok" else "FAIL", name, version, declared or "(nothing)", via))
        if verdict != "ok":
            failures += 1
    differences = []
    if constraints is not None:
        differences = constraint_failures(dists, load_constraints(constraints))
        for line in differences:
            print(line)
        if differences:
            print("FAIL licence gate: the installed set differs from %s in %d places" % (os.path.basename(constraints), len(differences)))
        else:
            print("licence gate: the installed set equals %s" % os.path.basename(constraints))
    if failures:
        print("FAIL licence gate: %d of %d distributions are outside the allowed licences (docker/licences/allowed.txt)" % (failures, len(dists)))
    if failures or differences:
        return 1
    print("licence gate: all %d distributions are under an allowed licence" % len(dists))
    return 0


def notices(target, out, rules):
    dists = distributions(target)
    if not dists:
        print("FAIL notices: %s holds no installed distribution" % target)
        return 1
    lines = [
        "THIRD-PARTY NOTICES",
        "",
        "The Python packages in this image (fastembed, pdfplumber and python-docx, with their dependencies and the libraries bundled",
        "with PDFium) were installed unmodified from their published wheels when the image was built. This file lists each one with",
        "its licence and holds the licence and notice texts that its wheel ships. Packages under the MPL-2.0 are installed unmodified.",
        "",
    ]
    lines.extend(CREDITS)
    lines.append("")
    for name, version, info, fields in dists:
        lines.append("=" * 78)
        lines.append("%s %s" % (name, version))
        lines.append("licence: %s" % (declared_licence(fields) or "see the licence files below"))
        for path in sorted(set(licence_files(info) + notice_files(info))) + package_licence_files(target, info):
            lines.append("-" * 78)
            lines.append("file: %s" % os.path.relpath(path, info if path.startswith(info + os.sep) else target).replace(os.sep, "/"))
            lines.append("")
            lines.append(read(path).replace("\r\n", "\n").rstrip())
        lines.append("")
    with open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    print("notices: wrote %s for %d distributions" % (out, len(dists)))
    return 0


def main(argv):
    rules = load_allowed(os.environ.get("OCUTALON_LICENCES_ALLOWED", os.path.join(HERE, "allowed.txt")))
    if len(argv) in (3, 4) and argv[1] == "check":
        return check(argv[2], rules, argv[3] if len(argv) == 4 else None)
    if len(argv) == 4 and argv[1] == "notices":
        return notices(argv[2], argv[3], rules)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
