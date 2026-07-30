#!/usr/bin/env python3
"""Dry-run every lab code update without writing, so TODO drift is caught early.

Each labN_updates.py replaces a TODO-containing block in the lab source with the
completed implementation. If a TODO is edited or removed, the replacement stops
matching and the workshop step silently stops working. Run this after changing
any lab source or any labN_updates.py.
"""
import pathlib
import runpy
import sys
import types

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
LABS = (2, 3, 4, 5, 6)


def normalize(text):
    return text.replace("\r\n", "\n")


def collect_replacements(lab):
    """Import labN_updates.py with replace_in_file stubbed so nothing is written."""
    calls = []
    stub = types.ModuleType("replace_function")
    stub.replace_in_file = lambda old, new, path: calls.append((old, new, path))
    saved = sys.modules.get("replace_function")
    sys.modules["replace_function"] = stub
    try:
        runpy.run_path(str(SCRIPT_DIR / f"lab{lab}_updates.py"), run_name="__main__")
    finally:
        if saved is None:
            del sys.modules["replace_function"]
        else:
            sys.modules["replace_function"] = saved
    return calls


def check(lab):
    problems = 0
    calls = collect_replacements(lab)
    print(f"=== lab{lab}_updates.py: {len(calls)} replacement(s) ===")
    for old, new, target in calls:
        path = SCRIPT_DIR.parent / target.replace("../", "", 1)
        if not path.is_file():
            print(f"  MISSING FILE     {target}")
            problems += 1
            continue

        content = normalize(path.read_text(encoding="utf-8"))
        occurrences = content.count(normalize(old))
        if occurrences == 1:
            print(f"  OK               {target}")
        elif occurrences > 1:
            # replace_in_file requires exactly one match and will refuse.
            print(f"  AMBIGUOUS ({occurrences}x)  {target}")
            problems += 1
        elif normalize(new) in content:
            # The update already ran; re-running run_workshop.sh is expected to hit this.
            print(f"  ALREADY APPLIED  {target}")
        else:
            print(f"  NOT FOUND        {target}")
            problems += 1
    return problems


def main():
    problems = sum(check(lab) for lab in LABS)
    print()
    if problems:
        print(f"FAILED: {problems} replacement(s) will not apply")
        return 1
    print("All replacements match their target files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
