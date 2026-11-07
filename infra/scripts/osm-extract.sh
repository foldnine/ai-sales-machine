#!/usr/bin/env bash
# Fill osm_snapshot from Geofabrik's country extracts, without Overpass.
#
#   make osm-refresh                 every country in DISCOVERY_OSM_COUNTRIES
#   make osm-refresh COUNTRIES=RS    just these
#
# The public Overpass instance has refused this IP on every backend and port
# since 2026-09-24, so no OpenStreetMap company ever reached WF-01. Geofabrik
# publishes the same map as one file per country, updated daily, as a plain
# download. This script:
#
#   1. downloads each country's .osm.pbf into $OSM_CACHE_DIR, only when
#      Geofabrik has a newer one (curl -z)
#   2. keeps offices and shops that list a website - what the Overpass query
#      in WF-12 asked for - with osmium (brew install osmium-tool)
#   3. writes them to osm_snapshot in the shape Overpass answered in,
#      {"elements": [{"type", "id", "tags"}]}, so WF-01 reads it unchanged
#
# WF-12 stays as it is: it only asks Overpass for a snapshot older than
# DISCOVERY_OSM_REFRESH_DAYS, and this script keeps them newer than that.
# Map data (c) OpenStreetMap contributors, ODbL: used internally, never
# republished (docs/lead-discovery.md).
set -euo pipefail
cd "$(dirname "$0")/../.."

# Not `source .env`: it is also read by compose, and this needs four values.
eval "$(grep -E '^(POSTGRES_USER|POSTGRES_DB|DISCOVERY_OSM_COUNTRIES|BOT_USER_AGENT)=' .env)"
COUNTRIES="${1:-${DISCOVERY_OSM_COUNTRIES:-}}"
if [ -z "$COUNTRIES" ]; then
  echo "OpenStreetMap discovery is off: DISCOVERY_OSM_COUNTRIES is empty (or pass COUNTRIES=RS,HR)"
  exit 0
fi
CACHE="${OSM_CACHE_DIR:-./tmp/osm}"
DB="${OSM_DB_CONTAINER:-aisales-postgres}"
UA="${BOT_USER_AGENT:-AiSalesMachineBot/1.0 (+https://github.com/foldnine/ai-sales-machine)}"

command -v osmium >/dev/null || { echo "osmium not found: brew install osmium-tool"; exit 1; }
mkdir -p "$CACHE"

geofabrik() {
  case "$1" in
    RS) echo serbia ;; HR) echo croatia ;; BA) echo bosnia-herzegovina ;;
    ME) echo montenegro ;; SI) echo slovenia ;; MK) echo macedonia ;;
    AL) echo albania ;; BG) echo bulgaria ;; RO) echo romania ;; HU) echo hungary ;;
    *) return 1 ;;
  esac
}

fail=0
for iso in $(echo "$COUNTRIES" | tr -d ' ' | tr ',' ' ' | tr '[:lower:]' '[:upper:]'); do
  name=$(geofabrik "$iso") || { echo "==> $iso: no Geofabrik extract mapped"; fail=1; continue; }
  pbf="$CACHE/$name-latest.osm.pbf"
  echo "==> $iso ($name)"
  if [ -f "$pbf" ]; then z=(-z "$pbf"); else z=(); fi
  if ! curl -fsSL -A "$UA" ${z[@]+"${z[@]}"} -o "$pbf.part" "https://download.geofabrik.de/europe/$name-latest.osm.pbf"; then
    echo "    download failed; the last snapshot stays"; rm -f "$pbf.part"; fail=1; continue
  fi
  # curl -z writes nothing when the file is not newer.
  if [ -s "$pbf.part" ]; then mv "$pbf.part" "$pbf"; echo "    downloaded $(du -h "$pbf" | cut -f1)"
  else rm -f "$pbf.part"; echo "    unchanged since the last download"; fi

  osmium tags-filter -O -o "$CACHE/$iso-biz.pbf" "$pbf" nwr/office nwr/shop
  osmium export -O -f geojsonseq -x print_record_separator=false -a type,id \
    -o "$CACHE/$iso-biz.geojsonl" "$CACHE/$iso-biz.pbf" 2>/dev/null
  python3 infra/scripts/osm-to-overpass.py "$iso" "$CACHE/$iso-biz.geojsonl" > "$CACHE/$iso.sql"
  docker exec -i "$DB" psql -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$CACHE/$iso.sql"
  echo "    saved: $(docker exec "$DB" psql -At -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
      -c "select elements || ' elements, ' || fetched_at from osm_snapshot where country = '$iso'")"
  rm -f "$CACHE/$iso-biz.pbf" "$CACHE/$iso-biz.geojsonl" "$CACHE/$iso.sql"
done
exit "$fail"
