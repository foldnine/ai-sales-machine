#!/usr/bin/env python3
"""Check that everything naming an offer or a signal type agrees.

agents/offers.json is the catalogue of what the pipeline sells. The same codes
also appear in places that cannot read it: the agent schemas (the model is
constrained by them), the leads and signals CHECK constraints (the latest
migration that redefines each), and the prompts' offer tables (the model reads
them as instructions). An offer added in one place and not the others fails
somewhere quiet - a CHECK violation on insert, or a model never told the offer
exists - so this fails loudly instead.

    python3 infra/scripts/check-offers.py

Exit code 0 if everything agrees, 1 otherwise. Reads files only.
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
problems = []


def load(rel):
    return json.loads((ROOT / rel).read_text(encoding="utf-8"))


def same(label, got, want):
    got, want = set(got), set(want)
    if got != want:
        missing = sorted(want - got)
        extra = sorted(got - want)
        problems.append(f"{label}: missing {missing}, unexpected {extra}")


def latest_check(constraint):
    """Values of the most recent [ADD] CONSTRAINT <name> ... IN (...) in migrations."""
    values = None
    for sql in sorted((ROOT / "postgres/migrations").glob("*.sql")):
        text = re.sub(r"--[^\n]*", "", sql.read_text(encoding="utf-8"))
        for m in re.finditer(
            r"(?:ADD\s+)?CONSTRAINT\s+" + constraint + r"\b.*?\bIN\s*\((.*?)\)\s*\)", text, re.S
        ):
            values = re.findall(r"'([^']*)'", m.group(1))
    if values is None:
        problems.append(f"no migration defines {constraint}")
        return []
    return values


catalogue = load("agents/offers.json")
codes = [o["code"] for o in catalogue["offers"]]
lines = catalogue["lines"]

for o in catalogue["offers"]:
    if o["line"] not in lines:
        problems.append(f"offers.json: {o['code']} names unknown line {o['line']}")
for name, line in lines.items():
    for key in ("tagline", "tagline_sr", "url"):
        if not line.get(key):
            problems.append(f"offers.json: line {name} has no {key}; prompts/signature.md needs one")
    if line["default_offer"] not in codes:
        problems.append(f"offers.json: line {name} defaults to unknown offer {line['default_offer']}")

research = load("agents/research/schema.json")["properties"]
same("agents/research recommended_service", research["recommended_service"]["enum"], codes + ["none"])
same("agents/scoring recommended_offer",
     load("agents/scoring/schema.json")["properties"]["recommended_offer"]["enum"], codes + ["none"])
same("agents/outreach offer", load("agents/outreach/schema.json")["properties"]["offer"]["enum"], codes)
same("agents/conversation offer_discussed",
     load("agents/conversation/schema.json")["properties"]["offer_discussed"]["enum"], codes + [""])
same("migrations leads_recommended_offer_check", latest_check("leads_recommended_offer_check"),
     codes + ["none"])

# The research schema and the signals table must allow the same signal types,
# or a valid research run fails on insert.
same("research signal_type vs migrations signals_signal_type_check",
     research["pain_signals"]["items"]["properties"]["signal_type"]["enum"],
     latest_check("signals_signal_type_check"))

for prompt in ["prompts/outreach.md", "prompts/conversation.md", "prompts/research.md"]:
    text = (ROOT / prompt).read_text(encoding="utf-8")
    for code in codes:
        if f"`{code}`" not in text:
            problems.append(f"{prompt} never names `{code}`")

# A campaign names the offer it sells (0026_first_revenue.sql).
same("migrations campaigns_offer_check", latest_check("campaigns_offer_check"), codes)

# A fixed price lives in offers.json. Every prompt row that names the offer
# must state that price and none may still call it unpriced, or the model
# quotes one number while the site publishes another.
for o in catalogue["offers"]:
    if not o.get("price_eur"):
        continue
    amount = f"{o['price_eur']:,}"
    for prompt in ["prompts/outreach.md", "prompts/conversation.md"]:
        rows = [l for l in (ROOT / prompt).read_text(encoding="utf-8").splitlines()
                if l.startswith("|") and f"`{o['code']}`" in l]
        if not rows:
            problems.append(f"{prompt}: no offer table row for `{o['code']}`")
        for row in rows:
            if amount not in row or re.search(r"not priced|no price", row, re.I):
                problems.append(f"{prompt}: the `{o['code']}` row does not state EUR {amount}")
    founding = (o.get("founding") or {}).get("price_eur")
    if founding and f"{founding:,}" not in (ROOT / "prompts/conversation.md").read_text(encoding="utf-8"):
        problems.append(f"prompts/conversation.md never states the founding price EUR {founding:,}")

for p in problems:
    print("    FAIL " + p)
if problems:
    sys.exit(1)
print(f"    {len(codes)} offers, {len(lines)} lines: schemas, migrations and prompts agree")
