#!/usr/bin/env python3
"""Report missing translations and compile .po files to .mo.

VVV ships prebuilt .mo files (translations/vvv-<lang>.mo); this script keeps
them up to date without requiring gettext tools:

    python scripts/po_tools.py report [lang]   - msgids used in src/ that are
                                                 missing or empty in vvv-<lang>.po
    python scripts/po_tools.py compile         - (re)build every vvv-*.mo from
                                                 its vvv-*.po

The .mo writer implements the GNU gettext format (magic 0x950412de) with a
null hash table, which every gettext reader accepts.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
TRANSLATIONS = ROOT / "translations"

PO_UNESCAPE = {
    "n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\", "'": "'",
}

def _unescape(s):
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            out.append(PO_UNESCAPE.get(s[i + 1], s[i + 1]))
            i += 2
        else:
            out.append(s[i])
            i += 1
    return "".join(out)

def extract_msgids():
    """All string literals passed to _() in the application sources.

    src/ibpp is excluded: its headers define _(s) as an identity macro, so
    those strings are never translated.
    """
    pat = re.compile(r'_\(\s*"((?:[^"\\]|\\.)*)"')
    msgids = {}
    files = [p for p in SRC.rglob("*")
             if p.suffix in (".cpp", ".h", ".c") and "ibpp" not in p.parts]
    for path in sorted(files):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for m in pat.finditer(text):
            mid = _unescape(m.group(1))
            if mid:
                msgids.setdefault(mid, set()).add(path.name)
    return msgids

def parse_po(path):
    """Returns a list of (msgid, msgstr, has_translation) tuples."""
    entries, cur_id, cur_str, state = [], [], [], None
    def flush():
        nonlocal cur_id, cur_str, state
        if state is not None:
            mid = _unescape("".join(cur_id))
            mstr = _unescape("".join(cur_str))
            entries.append((mid, mstr, bool(mstr)))
        cur_id, cur_str, state = [], [], None
    cont = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*$')
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("msgid "):
            flush()
            state = "id"
            cur_id = [line[6:].strip().strip('"')]
            if line[6:].strip() in ('""',):
                cur_id = [""]
        elif line.startswith("msgstr "):
            state = "str"
            cur_str = [line[7:].strip().strip('"')]
        elif line.startswith('"') and state in ("id", "str"):
            m = cont.match(line)
            if m:
                (cur_id if state == "id" else cur_str).append(m.group(1))
        elif not line.strip():
            continue
    flush()
    return entries

def po_report(lang):
    src_ids = extract_msgids()
    po_path = TRANSLATIONS / f"vvv-{lang}.po"
    entries = parse_po(po_path)
    by_id = {mid: (mstr, ok) for mid, mstr, ok in entries}
    missing, empty = [], []
    for mid, files in sorted(src_ids.items()):
        if mid not in by_id:
            missing.append((mid, files))
        elif not by_id[mid][1]:
            empty.append((mid, files))
    print(f"--- vvv-{lang}.po: {len(entries)} entries, {len(missing)} missing, {len(empty)} empty ---")
    for mid, files in missing:
        print(f"  MISSING [{','.join(sorted(files))}] {mid!r}")
    for mid, files in empty:
        print(f"  EMPTY    [{','.join(sorted(files))}] {mid!r}")
    return missing, empty

def write_mo(entries, out_path):
    """entries: list of (msgid, msgstr) - writes a msgfmt-compatible .mo.

    Conventions verified against a real msgfmt-built file: the table lengths
    exclude the terminating NUL (the header msgid has length 0), the NUL
    bytes are physically present between the blob strings, the entries are
    sorted by msgid bytes, and the hash table is left empty.
    """
    entries = sorted(entries, key=lambda e: e[0].encode("utf-8"))
    o_orig = 7 * 4
    o_trans = o_orig + len(entries) * 8
    o_hash = o_trans + len(entries) * 8
    blob_start = o_hash           # hash table is empty, strings follow it
    keys, vals, offsets, o = [], [], [], 0
    for mid, mstr in entries:
        kb = mid.encode("utf-8")
        vb = mstr.encode("utf-8")
        keys.append((blob_start + o, len(kb)))
        offsets.append((blob_start + o + len(kb) + 1, len(vb)))
        vals.append(kb + b"\x00" + vb + b"\x00")
        o += len(kb) + len(vb) + 2
    n = len(entries)
    blob = b"".join(vals)
    out = bytearray()
    out += (0x950412DE).to_bytes(4, "little")   # magic
    out += (0).to_bytes(4, "little")            # revision
    out += n.to_bytes(4, "little")
    out += o_orig.to_bytes(4, "little")
    out += o_trans.to_bytes(4, "little")
    out += (0).to_bytes(4, "little")            # hash table size
    out += (0).to_bytes(4, "little")            # hash table offset
    for off, ln in keys:
        out += ln.to_bytes(4, "little") + off.to_bytes(4, "little")
    for off, ln in offsets:
        out += ln.to_bytes(4, "little") + off.to_bytes(4, "little")
    out += blob
    out_path.write_bytes(out)

def compile_all():
    for po in sorted(TRANSLATIONS.glob("vvv-*.po")):
        if "@" in po.stem:  # sr@latin: keep going, just handled by glob too
            pass
        entries = parse_po(po)
        header = [(mid, mstr) for mid, mstr, ok in entries if mid == ""]
        used = [(mid, mstr) for mid, mstr, ok in entries if ok and mid != ""]
        if not header:
            print(f"{po.name}: no header entry, skipping")
            continue
        mo = po.with_suffix(".mo")
        write_mo(header + used, mo)
        print(f"{po.name} -> {mo.name} ({len(used)} translated entries)")

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "report":
        lang = sys.argv[2] if len(sys.argv) > 2 else "de"
        po_report(lang)
    elif cmd == "report-all":
        for po in sorted(TRANSLATIONS.glob("vvv-*.po")):
            lang = po.stem[4:]
            po_report(lang)
    elif cmd == "keys":
        import json
        ids = extract_msgids()
        print(json.dumps(sorted(ids), ensure_ascii=False, indent=0))
    elif cmd == "worklist":
        # prints the msgids that are missing or untranslated in a language
        import json
        lang = sys.argv[2]
        src_ids = extract_msgids()
        entries = parse_po(TRANSLATIONS / f"vvv-{lang}.po")
        by_id = {mid: (mstr, ok) for mid, mstr, ok in entries}
        todo = sorted(mid for mid in src_ids
                      if mid not in by_id or not by_id[mid][1])
        print(json.dumps(todo, ensure_ascii=False, indent=0))
    elif cmd == "apply":
        # apply <values.json>; the work list is recomputed here, so the
        # values file just carries the translations in work-list order
        import json
        data = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
        lang, values = data["lang"], data["values"]
        src_ids = extract_msgids()
        po_path = TRANSLATIONS / f"vvv-{lang}.po"
        entries = parse_po(po_path)
        by_id = {mid: (mstr, ok) for mid, mstr, ok in entries}
        todo = sorted(mid for mid in src_ids
                      if mid not in by_id or not by_id[mid][1])
        if len(values) != len(todo):
            sys.exit(f"{lang}: {len(values)} values for {len(todo)} work-list "
                     f"entries - aborting")
        mapping = dict(zip(todo, values))

        def po_escape(s):
            return (s.replace("\\", "\\\\").replace('"', '\\"')
                     .replace("\n", "\\n").replace("\t", "\\t"))

        text = po_path.read_text(encoding="utf-8")
        # pass 1: fill existing empty entries in place
        out_lines = []
        filled, appended = 0, 0
        i = 0
        src_lines = text.splitlines()
        while i < len(src_lines):
            line = src_lines[i]
            if line.startswith("msgid ") and not line.startswith('msgid ""'):
                mid, i2 = _read_po_string(src_lines, i)
                entry_end = _entry_end(src_lines, i)
                mstr = ""
                for j in range(i, entry_end):
                    if src_lines[j].startswith("msgstr "):
                        mstr, _ = _read_po_string(src_lines, j)
                        break
                if mid in mapping and not mstr:
                    # replace the msgstr line(s) with the translation
                    j = i
                    while j < entry_end:
                        if src_lines[j].startswith("msgstr "):
                            break
                        out_lines.append(src_lines[j])
                        j += 1
                    out_lines.append(f'msgstr "{po_escape(mapping[mid])}"')
                    j += 1
                    while j < entry_end and src_lines[j].startswith('"'):
                        j += 1  # drop old continuation lines
                    filled += 1
                    mapping.pop(mid)
                    i = j
                    continue
            out_lines.append(line)
            i += 1
        # pass 2: append the remaining (missing) entries
        if mapping:
            out_lines.append("")
            for mid, mstr in mapping.items():
                out_lines.append(f'msgid "{po_escape(mid)}"')
                out_lines.append(f'msgstr "{po_escape(mstr)}"')
                appended += 1
        po_path.write_text("\n".join(out_lines) + "\n", encoding="utf-8")
        print(f"vvv-{lang}.po: {filled} entries filled, {appended} appended")
    elif cmd == "compile":
        compile_all()
    else:
        print(__doc__)
        sys.exit(1)


def _read_po_string(lines, i):
    """Read the string that starts at lines[i] ('msgid x' or 'msgstr x'),
    including continuation lines. Returns (value, next_index)."""
    first = lines[i].split(" ", 1)[1].strip()
    val = _unescape(first[1:-1]) if first.startswith('"') else ""
    i += 1
    cont = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*$')
    while i < len(lines):
        m = cont.match(lines[i])
        if not m:
            break
        val += _unescape(m.group(1))
        i += 1
    return val, i


def _entry_end(lines, i):
    """Index of the blank line (or EOF) that ends the entry starting at i."""
    while i < len(lines) and lines[i].strip() != "":
        i += 1
    return i

if __name__ == "__main__":
    main()
