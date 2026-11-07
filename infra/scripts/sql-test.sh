#!/usr/bin/env bash
# Apply every migration to a throwaway PostgreSQL and run postgres/tests/*.sql.
#
#   ./infra/scripts/sql-test.sh        (make test)
#
# The container has no network and is removed afterwards; the stack and its
# data are never touched. Migrations go through migrate.sh itself, so a
# migration that would fail on deploy fails here first. Each test file runs
# in one transaction with ON_ERROR_STOP: an assertion is a DO block that
# raises, and the first failure stops the run with its message.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

IMAGE="${POSTGRES_IMAGE:-postgres:16.6-alpine}"
NAME="aisales-sqltest-$$"
DB_USER="sqltest"
DB_NAME="sqltest"

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "==> throwaway postgres ($IMAGE)"
docker run -d --rm --name "$NAME" --network none \
    -e POSTGRES_USER="$DB_USER" -e POSTGRES_DB="$DB_NAME" -e POSTGRES_PASSWORD=sqltest \
    "$IMAGE" >/dev/null
for _ in $(seq 1 60); do
    if docker exec "$NAME" pg_isready -q -U "$DB_USER" -d "$DB_NAME" 2>/dev/null \
       && docker exec "$NAME" psql -q -U "$DB_USER" -d "$DB_NAME" -c 'select 1' >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

echo "==> migrations"
# migrate.sh reads .env when there is one, and on a deployed machine that names
# the production container. It runs from a copy with no .env, pointed at the
# throwaway, so it cannot reach anything else.
WORK="$(mktemp -d)"
trap 'cleanup; rm -rf "$WORK"' EXIT
mkdir -p "$WORK/infra/scripts" "$WORK/postgres"
cp infra/scripts/migrate.sh "$WORK/infra/scripts/"
cp -R postgres/migrations "$WORK/postgres/"
POSTGRES_CONTAINER="$NAME" POSTGRES_USER="$DB_USER" POSTGRES_DB="$DB_NAME" \
    "$WORK/infra/scripts/migrate.sh" | tail -2 | sed 's/^/    /'

# The workflow queries the tests call, as prepared statements.
wf_sql() {
    python3 infra/scripts/workflow-sql.py wf11_apply n8n/workflows/ai-sales-telegram-commands.json "Apply Command"
    python3 infra/scripts/workflow-sql.py wf05_claim n8n/workflows/ai-sales-outreach-generation.json "Claim Leads"
    python3 infra/scripts/workflow-sql.py wf05_queue n8n/workflows/ai-sales-outreach-generation.json "Queue For Approval"
    python3 infra/scripts/workflow-sql.py wf08_apply n8n/workflows/ai-sales-inbox-classifier.json "Apply Classification"
    python3 infra/scripts/workflow-sql.py wf01_record n8n/workflows/ai-sales-lead-discovery.json "Record Candidates"
    python3 infra/scripts/workflow-sql.py wf03_claim n8n/workflows/ai-sales-contact-enrichment.json "Claim Companies"
    python3 infra/scripts/workflow-sql.py wf08_reply_context n8n/workflows/ai-sales-inbox-classifier.json "Reply Context"
    python3 infra/scripts/workflow-sql.py wf08_queue_reply n8n/workflows/ai-sales-inbox-classifier.json "Queue Reply Draft"
    python3 infra/scripts/workflow-sql.py wf05_autosend n8n/workflows/ai-sales-outreach-generation.json "Autosend Check"
    python3 infra/scripts/workflow-sql.py wf05_alert n8n/workflows/ai-sales-outreach-generation.json "Queue Draft Alert"
    python3 infra/scripts/workflow-sql.py wf100_stats n8n/workflows/ai-sales-daily-report.json "Read Daily Stats"
    python3 infra/scripts/workflow-sql.py wf06_claim n8n/workflows/ai-sales-outreach-dispatch.json "Claim Approved Outreach"
}

failed=0
for test in postgres/tests/*.sql; do
    if { wf_sql; cat "$test"; } | docker exec -i "$NAME" \
           psql -v ON_ERROR_STOP=1 -q -X --single-transaction -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>"$ROOT_DIR/.sqltest.err"; then
        echo "    PASS $test"
    else
        echo "    FAIL $test"
        sed 's/^/      /' "$ROOT_DIR/.sqltest.err"
        failed=1
    fi
done
rm -f "$ROOT_DIR/.sqltest.err"
exit $failed
