#!/usr/bin/env python3
"""Turn an osmium geojsonseq export into the SQL that saves one osm_snapshot row.

    osm-to-overpass.py RS RS-biz.geojsonl > RS.sql

Keeps what WF-12's Overpass query asked for - an office or a shop with a
website or contact:website - and writes it in the shape Overpass answered in,
{"elements": [{"type": ..., "id": ..., "tags": {...}}]}, so WF-01 reads a
Geofabrik snapshot exactly as it read an Overpass one. Refuses to write an
empty country: a snapshot with no elements would replace a good one.
"""
import json
import secrets
import sys

TYPES = {"n": "node", "w": "way", "r": "relation"}


def main(iso, path):
    elements = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            props = dict(json.loads(line).get("properties") or {})
            kind, oid = props.pop("@type", ""), props.pop("@id", None)
            if oid is None:
                continue
            if not ("office" in props or "shop" in props):
                continue
            if not ("website" in props or "contact:website" in props):
                continue
            elements.append({"type": TYPES.get(kind[:1], kind), "id": int(oid), "tags": props})
    if not elements:
        sys.exit(f"{iso}: no offices or shops with a website; nothing written")
    payload = json.dumps({"elements": elements}, ensure_ascii=False, separators=(",", ":"))
    tag = "osm" + secrets.token_hex(8)
    assert f"${tag}$" not in payload
    print(
        "INSERT INTO osm_snapshot (country, payload, elements, fetched_at)\n"
        f"VALUES ('{iso}', ${tag}${payload}${tag}$, {len(elements)}, now())\n"
        "ON CONFLICT (country) DO UPDATE\n"
        "    SET payload = EXCLUDED.payload, elements = EXCLUDED.elements, fetched_at = now();"
    )


if __name__ == "__main__":
    if len(sys.argv) != 3 or not sys.argv[1].isalpha() or len(sys.argv[1]) != 2:
        sys.exit(__doc__)
    main(sys.argv[1].upper(), sys.argv[2])
