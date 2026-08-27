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
