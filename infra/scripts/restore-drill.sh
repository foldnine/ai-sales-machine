#!/usr/bin/env bash
# Prove a backup restores, without touching the running database.
#
#   make restore-drill                 the newest backup in $BACKUP_DIR
#   make restore-drill FILE=backups/aisales-<ts>.dump.gpg
#
# A backup nobody has restored is a hope. This:
#
#   1. decrypts the dump into a private temp file (if it is encrypted)
#   2. restores it into a throwaway PostgreSQL container with no network,
#      stopping at the first error
#   3. compares it with the live database: every row the live tables held at
#      the backup's timestamp has to be in the restore, and every migration
#      the restore records has to be one the live database has too
#
# Both the container and the plaintext dump are removed on exit, pass or fail.
# Nothing here writes to aisales-postgres; it only reads from it.
set -euo pipefail
cd "$(dirname "$0")/../.."

# Not `source .env`: it is also read by compose, and this needs five values.
eval "$(grep -E '^(POSTGRES_USER|POSTGRES_DB|BACKUP_DIR|BACKUP_PASSPHRASE|POSTGRES_IMAGE)=' .env)"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
IMAGE="${POSTGRES_IMAGE:-postgres:16.6-alpine}"
LIVE=aisales-postgres
DRILL=aisales-restore-drill

file="${1:-}"
[ -n "$file" ] || file=$(ls -t "$BACKUP_DIR"/aisales-*.dump* 2>/dev/null | head -1 || true)
[ -f "$file" ] || { echo "no backup found in $BACKUP_DIR"; exit 1; }

# aisales-20260924T084247Z.dump.gpg -> 2026-09-24 08:42:47+00
stamp=$(basename "$file" | sed -E 's/^aisales-([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z.*/\1-\2-\3 \4:\5:\6+00/')
case "$stamp" in *+00) ;; *) echo "cannot read a timestamp from $(basename "$file")"; exit 1 ;; esac

tmp=$(mktemp -d)
chmod 700 "$tmp"
cleanup() {
  docker rm -f "$DRILL" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

echo "==> $(basename "$file") (taken $stamp)"
dump="$file"
if [[ "$file" == *.gpg ]]; then
  [ -n "${BACKUP_PASSPHRASE:-}" ] || { echo "    encrypted, and BACKUP_PASSPHRASE is empty"; exit 1; }
  dump="$tmp/restore.dump"
  (umask 077; gpg --batch --quiet --pinentry-mode loopback --passphrase "$BACKUP_PASSPHRASE" \
      --decrypt "$file" > "$dump")
  echo "    decrypted"
fi

echo "==> restore into a throwaway container"
docker rm -f "$DRILL" >/dev/null 2>&1 || true
docker run -d --rm --name "$DRILL" --network none \
  -e POSTGRES_PASSWORD=drill -e POSTGRES_USER="$POSTGRES_USER" -e POSTGRES_DB="$POSTGRES_DB" \
  "$IMAGE" >/dev/null
# pg_isready answers during initdb's temporary server too; wait for the real one.
until docker exec "$DRILL" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc 'select 1' >/dev/null 2>&1 \
      && [ "$(docker logs "$DRILL" 2>&1 | grep -c 'ready to accept connections')" -ge 2 ]; do
  sleep 1
done
start=$(date +%s)
docker exec -i "$DRILL" pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --exit-on-error < "$dump"
echo "    restored in $(( $(date +%s) - start ))s"

echo "==> compare with the live database at $stamp"
live() { docker exec "$LIVE"  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "$1"; }
drill() { docker exec "$DRILL" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "$1"; }

fail=0
# Tables whose rows carry a creation time: the restore must hold exactly the
# rows the live table had created before the backup. Rows deleted since then
# would make live < drill; that is reported, not failed.
for spec in public.companies:created_at public.people:created_at public.leads:created_at \
            public.outreach:created_at public.signals:created_at public.suppression_list:created_at \
            public.notifications:created_at n8n.workflow_entity:createdAt n8n.credentials_entity:createdAt; do
  table=${spec%%:*}; col=${spec#*:}
  q="select count(*) from $table where \"$col\" < '$stamp'"
  l=$(live "$q"); d=$(drill "select count(*) from $table")
  if [ "$l" = "$d" ]; then printf '    ok    %-28s %s\n' "$table" "$d"
  elif [ "$l" -lt "$d" ]; then printf '    note  %-28s restore %s, live %s: rows deleted since\n' "$table" "$d" "$l"
  else printf '    FAIL  %-28s restore %s, live had %s\n' "$table" "$d" "$l"; fail=1
  fi
done

# Every migration in the restore must be one the live database also applied,
# with the same checksum. Newer live migrations are expected.
bad=$(comm -13 <(live "select version||' '||checksum from schema_migrations" | sort) \
               <(drill "select version||' '||checksum from schema_migrations" | sort) | wc -l | tr -d ' ')
n=$(drill "select count(*) from schema_migrations")
if [ "$bad" = 0 ]; then echo "    ok    schema_migrations            $n, all known to live"
else echo "    FAIL  schema_migrations            $bad not in live"; fail=1; fi

if [ "$fail" = 0 ]; then echo "PASS"; else echo "FAIL"; exit 1; fi
