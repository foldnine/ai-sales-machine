#!/usr/bin/env bash
# Fill directory_snapshot from Minimax's public directory of accounting services.
#
#   make minimax-refresh               DISCOVERY_MINIMAX_COUNTRIES (e.g. SI,RS,HR)
#   make minimax-refresh COUNTRIES=RS  just these
#
# Minimax lists the accounting offices that use it, per country, so that
# entrepreneurs can find a bookkeeper. It is the only regional source with
# hundreds of accounting offices and a website or email for each
# (0029_minimax_directory.sql has the counts), and every one of them works in
# Minimax, which is what the segment email opens with. One page per country,
# three requests a run; WF-01 reads the snapshot, never the site.
set -euo pipefail
cd "$(dirname "$0")/../.."

eval "$(grep -E '^(POSTGRES_USER|POSTGRES_DB|DISCOVERY_MINIMAX_COUNTRIES|BOT_USER_AGENT)=' .env)"
COUNTRIES="${1:-${DISCOVERY_MINIMAX_COUNTRIES:-}}"
if [ -z "$COUNTRIES" ]; then
  echo "Minimax directory is off: DISCOVERY_MINIMAX_COUNTRIES is empty (or pass COUNTRIES=SI,RS,HR)"
  exit 0
fi
CACHE="${MINIMAX_CACHE_DIR:-./tmp/minimax}"
DB="${OSM_DB_CONTAINER:-aisales-postgres}"
UA="${BOT_USER_AGENT:-AiSalesMachineBot/1.0 (+https://github.com/foldnine/ai-sales-machine)}"
mkdir -p "$CACHE"

page() {
  case "$1" in
    SI) echo https://www.minimax.si/sl-si/seznam-racunovodskih-servisov ;;
    RS) echo https://www.minimax.rs/sr-latn-rs/spisak-knjigovodstvenih-agencija ;;
    HR) echo https://www.minimax.hr/hr-hr/popis-racunovodstvenih-servisa ;;
    *) return 1 ;;
  esac
}

fail=0
for iso in $(echo "$COUNTRIES" | tr -d ' ' | tr ',' ' ' | tr '[:lower:]' '[:upper:]'); do
  url=$(page "$iso") || { echo "==> $iso: no Minimax directory mapped"; fail=1; continue; }
  echo "==> $iso $url"
  if ! curl -fsSL -A "$UA" -m 60 -o "$CACHE/$iso.html" "$url"; then
    echo "    download failed; the last snapshot stays"; fail=1; continue
  fi
  if ! python3 infra/scripts/minimax-directory.py "$iso" "$CACHE/$iso.html" "$url" > "$CACHE/$iso.sql"; then
    fail=1; continue
  fi
  docker exec -i "$DB" psql -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$CACHE/$iso.sql"
  echo "    saved: $(docker exec "$DB" psql -At -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
      -c "select elements || ' offices, ' || fetched_at from directory_snapshot where source = 'radar_minimax' and country = '$iso'")"
  rm -f "$CACHE/$iso.html" "$CACHE/$iso.sql"
done
exit "$fail"
