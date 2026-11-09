#!/usr/bin/env bash
# Deploy what is on origin/main to the running stack.
#
#   make deploy
#
# The order is the one every manual deploy so far has followed, written down
# so it stops depending on memory:
#
#   1. drain: tell the long workflows to claim no new work (0021), then wait
#      for what is in flight to finish - a restart kills it and n8n records
#      it as "possible out-of-memory" (CLAUDE.md, rule 7)
#   2. fast-forward main; refuse on a dirty tree or a diverged branch
#   3. backup (CLAUDE.md, rule 2)
#   4. apply pending migrations
#   5. import every workflow, then re-activate exactly the set that was active
#      before - import deactivates all of them (n8n/README.md)
#   6. recreate the stack, so compose and .env changes are picked up
#   7. make health
#
# It does not edit .env: `make env-upgrade` reports drift, and applying it
# stays a human decision. It stops at the first failure.
set -euo pipefail
cd "$(dirname "$0")/../.."

# Not `source <(...)`: macOS ships bash 3.2, where that reads nothing.
eval "$(grep -E '^(POSTGRES_USER|POSTGRES_DB|DISCOVERY_MINIMAX_COUNTRIES)=' .env)"
q() { docker exec aisales-postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "$1"; }

in_flight() {
  q "select (select count(*) from n8n.execution_entity where status in ('running','new'))
          + (select count(*) from agent_runs where status='running' and started_at > now() - interval '45 minutes')"
}

echo "==> drain"
# From here until the script exits, WF-02..05 claim nothing (0021_deploy_drain
# .sql), so the runs already going are the last ones. The key is removed on any
# exit, and expires by itself after two hours if even that does not happen.
# Before 0021 is applied nothing reads the key, and this is the old plain wait.
# Re-written on every pass, so a wait longer than the expiry keeps draining.
drain() {
  q "insert into app_settings (key, value) values ('deploy_drain', to_jsonb(now()::text))
     on conflict (key) do update set value = excluded.value, updated_at = now()" >/dev/null
}
undrain() { q "delete from app_settings where key = 'deploy_drain'" >/dev/null 2>&1 || true; }
trap undrain EXIT
drain
waited=0
while [ "$(in_flight)" != 0 ]; do
  [ $((waited % 60)) = 0 ] && echo "    waiting for work in flight to finish (${waited}s)"
  sleep 10; waited=$((waited + 10))
  drain
done
echo "    idle"

echo "==> main"
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "    tracked files have local changes"; exit 1; }
git switch -q main
git pull -q --ff-only
git log --oneline -1

echo "==> backup"
make backup

echo "==> migrations"
make migrate
make migrate-status | tail -1

echo "==> directories"
# Minimax's directory of accounting offices (0029) is the only source the
# accounting_offices segment can grow from, and it reaches WF-01 only through
# directory_snapshot. As a manual step it was forgotten for three weeks, so a
# deploy fills it whenever a country in DISCOVERY_MINIMAX_COUNTRIES is missing
# or older than a week. Empty switches it off. A failure is reported and does
# not stop the deploy: WF-01 keeps the last good snapshot, and a refresh that
# parses too few offices saves nothing (minimax-directory.py).
# Letters and commas only: the list is interpolated into the query below.
mm_list=$(echo "${DISCOVERY_MINIMAX_COUNTRIES:-}" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z,')
if [ -z "$mm_list" ]; then
  echo "    minimax: off (DISCOVERY_MINIMAX_COUNTRIES is empty)"
  due=""
else
  due=$(q "select string_agg(c, ',') from unnest(string_to_array('$mm_list', ',')) c
           where c ~ '^[A-Z]{2}$' and not exists (select 1 from directory_snapshot d
                             where d.source = 'radar_minimax' and d.country = c
                               and d.fetched_at > now() - interval '7 days')")
fi
if [ -n "$due" ]; then
  echo "    minimax: refreshing $due"
  ./infra/scripts/minimax-directory.sh "$due" || echo "    minimax refresh failed; WF-01 keeps the last snapshot"
elif [ -n "$mm_list" ]; then
  echo "    minimax: current"
fi

echo "==> workflows"
active=$(q "select id from n8n.workflow_entity where active order by id")
known=$(q "select coalesce(string_agg(quote_literal(id), ','), '''''') from n8n.workflow_entity")
echo "    active: $(echo $active)"
docker exec aisales-n8n n8n import:workflow --separate --input=/workflows 2>&1 | grep -E "Importing|Successfully|rror" || true
# A workflow this import created for the first time was never active, so the
# list above cannot bring it up. One with a schedule is meant to run, so it is
# switched on; manual and error-trigger workflows stay off.
new=$(q "select id from n8n.workflow_entity where id not in ($known) and nodes::text like '%n8n-nodes-base.scheduleTrigger%' order by id")
[ -z "$new" ] || echo "    new, activating: $(echo $new)"
for id in $active $new; do
  docker exec aisales-n8n n8n update:workflow --id="$id" --active=true >/dev/null 2>&1
done

echo "==> restart"
# Import changes the database, not the running n8n: until it restarts it keeps
# executing the old workflow versions. `up -d` alone does not restart a
# container whose config is unchanged, so n8n is restarted explicitly.
#
# Schedules keep firing while the backup and import run - on 2026-09-23 three
# executions started at 22:00 during a deploy and a restart killed them - so
# wait for anything in flight to finish first, however long that takes.
waited=0
while [ "$(q "select count(*) from n8n.execution_entity where status in ('running','new')")" != 0 ]; do
  [ $((waited % 60)) = 0 ] && echo "    waiting for running executions to finish (${waited}s)"
  sleep 10; waited=$((waited + 10))
done
# Nothing started since the drain can have claimed work, so this loop only
# ever waits for runs that end within seconds.
# The dashboard comes from GHCR, pinned to this checkout (see DASHBOARD_TAG in
# the Makefile); a failed pull (offline, a local image name)
# leaves the image already here, or the build fallback in docker-compose.yml.
DASHBOARD_TAG=$(git log -1 --format=sha-%H -- dashboard .github/workflows/dashboard-image.yml | cut -c1-11)
export DASHBOARD_TAG
docker compose pull --quiet dashboard || echo "    dashboard image not pulled; using the local one"
docker compose up -d --remove-orphans
docker compose restart n8n
until [ "$(docker inspect -f '{{.State.Health.Status}}' aisales-n8n)" = healthy ]; do sleep 3; done
now_active=$(q "select count(*) from n8n.workflow_entity where active")
echo "    $now_active workflow(s) active"

make health
make env-upgrade | tail -1
