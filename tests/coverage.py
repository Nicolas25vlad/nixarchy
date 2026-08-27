"""Every Install row upstream offers, against what the selection covers.

Run from tests/options.nix. A row added by an Omarchy bump cannot then go
unmapped without someone deciding it should -- and a row upstream *removes*
shows up too, so the exception list cannot rot into a list of things that no
longer exist.

The exceptions are named rather than counted. "How many are unmapped" is a
number that drifts quietly; "which ones, and why" is a decision.
"""

import json
import os
import re
import sys

raw = open(os.environ["menuFile"]).read()
# The two transformations MenuModel.js applies.
raw = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M)
raw = re.sub(r",(\s*[}\]])", r"\1", raw)

rows = {
    k
    for k, v in json.loads(raw).items()
    if k.startswith("install.") and "action" in v
}
known = set(os.environ["mapped"].split()) | set(os.environ["notApps"].split())

unmapped = sorted(rows - known)
stale = sorted(known - rows)

if unmapped:
    sys.exit(
        "these Install rows are neither in data/apps.nix nor listed as "
        "actions:\n  " + " ".join(unmapped)
        + "\nMap them, or say in tests/options.nix why they are not apps."
    )
if stale:
    sys.exit(
        "these are mapped or excused but no longer exist upstream:\n  "
        + " ".join(stale)
        + "\nAn Omarchy bump removed them; drop them here too."
    )
print(f"all {len(rows)} Install rows are mapped or accounted for")

# ---- every command a menu row names must exist ---------------------------
# A row whose command is gone renders normally and does nothing when chosen,
# which is the quietest way for an Omarchy bump to break the desktop.
#
# Two shapes are excluded because they are not invocations. `when:` guards can
# name an *Arch package* -- install.editor.emacs tests
# `omarchy-pkg-present omarchy-emacs`, which is a package, not a command. And
# remove.webapp greps Exec= lines for `omarchy-webapp-handler`, which is a
# pattern. Both were flagged the first time this ran, and both are fine.
menu = json.loads(raw)
have = set(os.listdir(os.path.join(os.environ["omarchyPath"], "bin")))
not_invocations = {"omarchy-emacs", "omarchy-webapp-handler"}

missing = {}
for key, row in menu.items():
    for field in ("action", "when", "disabled", "checked"):
        for cmd in set(re.findall(r"\bomarchy-[a-z0-9-]+", str(row.get(field, "")))):
            if cmd not in have and cmd not in not_invocations:
                missing.setdefault(cmd, []).append(key)

if missing:
    sys.exit(
        "these menu rows name a command that does not exist:\n  "
        + "\n  ".join(f"{c} <- {' '.join(sorted(k))}" for c, k in sorted(missing.items()))
        + "\nAn Omarchy bump removed or renamed it; the rows still draw and do "
        "nothing when chosen."
    )
print(f"all {len(menu)} menu rows name commands that exist")
