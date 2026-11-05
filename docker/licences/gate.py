#!/usr/bin/env python3
"""The licence gate and the notices of the Docker image's Python packages (Story 34.2; AD-23).

  gate.py check <dir>              list every distribution installed in <dir> (a pip --target folder) with its licence, and exit 1
                                   when one is outside the allowed set of allowed.txt, or when <dir> holds no distribution
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


def read(path):
    with open(path, "rb") as handle:
        return handle.read().decode("utf-8", "replace")


def load_allowed(path):
    """The rules of allowed.txt: (allowed ids by lower case, aliases by lower case, texts [(id, regex)], ignored phrases)."""
    allowed, aliases, texts, ignored = {}, {}, [], set()
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
        else:
            raise SystemExit("licence gate: %s:%d is not a rule" % (path, number))
    return allowed, aliases, texts, ignored


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
    """What the package declares: the License-Expression, else a one-line License, else its License :: classifiers (all of them)."""
    for value in fields.get("license-expression", []):
        if value:
            return value
    for value in fields.get("license", []):
        if value and len(value) <= 200 and value.upper() != "UNKNOWN":
            return value
    names = []
    for value in fields.get("classifier", []):
        if value.startswith("License ::"):
            names.append(value.split("::")[-1].strip())
    return " AND ".join(names)


RANK = {"ok": 0, "files": 1, "no": 2}


def evaluate(expression, rules):
    """(verdict, how): verdict 'ok', 'files' (every other name is allowed, but a phrase needs the licence files) or 'no'.

    The expression is read with parentheses, AND (also a comma or a semicolon) binding tighter than OR: an AND is as bad as its worst
    side and an OR as good as its best. Anything that does not parse is 'no'."""
    allowed, aliases, _, ignored = rules
    text = expression
    for alias in sorted((a for a in aliases if "," in a), key=len, reverse=True):
        text = re.sub(r"(?<![\w.-])" + re.escape(alias) + r"(?![\w.-])", aliases[alias], text, flags=re.I)
    items = [re.sub(r"\s+", " ", item).strip() for item in re.split(r"(\(|\)|\s+AND\s+|\s+OR\s+|[,;])", text)]
    items = [item for item in items if item]
    state = {"at": 0}

    def peek():
        return items[state["at"]] if state["at"] < len(items) else None

    def name_verdict(token):
        token = aliases.get(token.lower(), token)
        if token.lower() in allowed:
            return "ok"
        return "files" if token.lower() in ignored else "no"

    def combine(left, right, pick):
        if left is None:
            return right
        if right is None:
            return left
        return pick(left, right, key=RANK.get)

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
            return None
        state["at"] += 1
        return name_verdict(item)

    def parse_and():
        verdict = parse_atom()
        while peek() in ("AND", ",", ";"):
            state["at"] += 1
            verdict = combine(verdict, parse_atom(), max)
        return verdict

    def parse_or():
        verdict = parse_and()
        while peek() == "OR":
            state["at"] += 1
            verdict = combine(verdict, parse_and(), min)
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


def recognised(path, rules):
    """The allowed identifiers whose text the file holds."""
    allowed, _, texts, _ = rules
    text = normalise(read(path))
    return [ident for ident, regex in texts if ident.lower() in allowed and regex.search(text)]


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


def check(target, rules):
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
    if failures:
        print("FAIL licence gate: %d of %d distributions are outside the allowed licences (docker/licences/allowed.txt)" % (failures, len(dists)))
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
        "its licence and holds the licence texts that its wheel ships. Packages under the MPL-2.0 are installed unmodified.",
        "",
    ]
    lines.extend(CREDITS)
    lines.append("")
    for name, version, info, fields in dists:
        lines.append("=" * 78)
        lines.append("%s %s" % (name, version))
        lines.append("licence: %s" % (declared_licence(fields) or "see the licence files below"))
        for path in sorted(set(licence_files(info) + notice_files(info))):
            lines.append("-" * 78)
            lines.append("file: %s" % os.path.relpath(path, info).replace(os.sep, "/"))
            lines.append("")
            lines.append(read(path).replace("\r\n", "\n").rstrip())
        lines.append("")
    with open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    print("notices: wrote %s for %d distributions" % (out, len(dists)))
    return 0


def main(argv):
    rules = load_allowed(os.environ.get("OCUTALON_LICENCES_ALLOWED", os.path.join(HERE, "allowed.txt")))
    if len(argv) == 3 and argv[1] == "check":
        return check(argv[2], rules)
    if len(argv) == 4 and argv[1] == "notices":
        return notices(argv[2], argv[3], rules)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
