#!/usr/bin/env bash
#
# Read-only health check for the whole stack. Exits 0 if everything a workflow
# depends on is reachable, 1 otherwise. Safe to run from cron or Telegram.
#
#   ./scripts/healthcheck.sh
#   ./scripts/healthcheck.sh --quiet    only print failures

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

FAILURES=0

ok()   { [[ $QUIET -eq 1 ]] || printf '  OK    %s\n' "$1"; }
warn() { printf '  WARN  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

section() { [[ $QUIET -eq 1 ]] || printf '\n%s\n' "$1"; }

check_container() {
    local name="$1"
    local state health
    state="$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null)"
    if [[ -z "$state" ]]; then
        fail "$name: container does not exist"
        return
    fi
    if [[ "$state" != "running" ]]; then
        fail "$name: state=$state"
        return
    fi
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$name" 2>/dev/null)"
    case "$health" in
        healthy)   ok   "$name: running, healthy" ;;
        none)      ok   "$name: running (no healthcheck)" ;;
        starting)  warn "$name: running, health starting" ;;
        *)         fail "$name: running, health=$health" ;;
    esac
}

section "Containers"
if ! command -v docker >/dev/null 2>&1; then
    fail "docker CLI not found"
else
    for c in aisales-postgres aisales-n8n aisales-caddy; do
        check_container "$c"
    done
fi

section "PostgreSQL"
if docker exec aisales-postgres pg_isready -q -U "${POSTGRES_USER:-aisales}" -d "${POSTGRES_DB:-aisales}" >/dev/null 2>&1; then
    ok "accepting connections"
    tables="$(docker exec aisales-postgres psql -tAqc \
        "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" \
        -U "${POSTGRES_USER:-aisales}" -d "${POSTGRES_DB:-aisales}" 2>/dev/null | tr -d '[:space:]')"
    if [[ "${tables:-0}" -gt 0 ]]; then
        ok "public schema has ${tables} tables"
    else
        fail "public schema is empty - run 'make migrate'"
    fi
else
    fail "pg_isready failed"
fi

section "n8n"
if docker exec aisales-n8n wget -q -O- http://127.0.0.1:5678/healthz >/dev/null 2>&1; then
    ok "healthz responding"
else
    fail "healthz not responding"
fi

section "Ollama"
# Ollama runs natively on the host, not in a container: a container on macOS gets
# no Metal access and would run on the CPU. It is checked over HTTP, and from
# inside n8n too, because that is the path that actually matters.
ollama_url="${OLLAMA_BASE_URL:-http://ollama:11434}"
if curl -fsS --max-time 5 "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
    models="$(curl -fsS --max-time 5 "http://127.0.0.1:11434/api/tags" 2>/dev/null \
        | tr ',' '\n' | grep -c '"name"' | tr -d '[:space:]')"
    if [[ "${models:-0}" -gt 0 ]]; then
        ok "reachable on the host, ${models} model(s) pulled"
    else
        warn "reachable but no models pulled - run 'make pull-model'"
    fi
    if docker exec aisales-n8n wget -q -O- --timeout=5 "${ollama_url}/api/tags" >/dev/null 2>&1; then
        ok "reachable from n8n at ${ollama_url}"
    else
        fail "n8n cannot reach ${ollama_url} - check the 'ollama:host-gateway' entry in docker-compose.yml"
    fi
else
    fail "not reachable on the host - is 'ollama serve' running? (brew services start ollama)"
fi

section "Disk"
avail="$(df -h . | awk 'NR==2 {print $4}')"
used_pct="$(df -h . | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
if [[ "${used_pct:-0}" -ge 90 ]]; then
    fail "filesystem ${used_pct}% used, ${avail} free"
else
    ok "${avail} free (${used_pct}% used)"
fi

section "Discovery sources"
# A snapshot nobody refreshes is a source that silently stopped. Reported,
# never a failure - WF-01 runs on what it has. Only checked when the Minimax
# directory is switched on (DISCOVERY_MINIMAX_COUNTRIES).
mm_list="$(echo "${DISCOVERY_MINIMAX_COUNTRIES:-}" | tr -d ' ')"
if [[ -z "$mm_list" ]]; then
    ok "Minimax directory: off (DISCOVERY_MINIMAX_COUNTRIES is empty)"
else
    mm_expected="$(echo "$mm_list" | tr ',' '\n' | grep -c .)"
    minimax="$(docker exec aisales-postgres psql -tAqc \
        "SELECT count(*) || ' ' || COALESCE(extract(day FROM now() - min(fetched_at))::int, -1)
         FROM directory_snapshot WHERE source = 'radar_minimax';" \
        -U "${POSTGRES_USER:-aisales}" -d "${POSTGRES_DB:-aisales}" 2>/dev/null)"
    read -r mm_countries mm_age <<<"${minimax:-x x}"
    if [[ "$mm_countries" == "x" ]]; then
        warn "Minimax directory: could not read directory_snapshot"
    elif [[ "$mm_countries" -eq 0 ]]; then
        warn "Minimax directory: empty - accounting offices get no new companies; run 'make minimax-refresh'"
    elif [[ "$mm_countries" -lt "$mm_expected" || "$mm_age" -gt 14 ]]; then
        warn "Minimax directory: ${mm_countries}/${mm_expected} countries, oldest ${mm_age} days - run 'make minimax-refresh'"
    else
        ok "Minimax directory: ${mm_countries} countries, oldest ${mm_age} days"
    fi
fi

section "Sender identity"
# The repository ships with placeholder identity. A message signed "Your Name"
# with a link to example.com is worse than no message: edit these first
# (docs/customizing.md). Reported, never a failure.
# Whole lines only: the note at the top of the file names the placeholder too.
if grep -qx 'Your Name' prompts/signature.md 2>/dev/null; then
    warn "prompts/signature.md still says 'Your Name' - edit before sending"
else
    ok "prompts/signature.md has a sender name"
fi
# The taglines and URLs, not the $comment that explains them.
if python3 -c '
import json, sys
def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k in ("tagline", "tagline_sr", "url") and isinstance(v, str):
                yield v
            else:
                yield from walk(v)
    elif isinstance(o, list):
        for v in o:
            yield from walk(v)
vals = list(walk(json.load(open("agents/offers.json"))))
sys.exit(0 if any("example.com" in v or "Your Company" in v for v in vals) else 1)' 2>/dev/null; then
    warn "agents/offers.json still says Your Company / example.com - edit before sending"
else
    ok "agents/offers.json has your own URLs"
fi

section "Safety rails"
# Guarded autosend (0030_autosend.sql): reported, never a failure. Two
# switches, both the operator's - OUTREACH_AUTOSEND_ENABLED in .env is the master, and
# app_settings 'autosend' is what /autosend on|off and /stop flip on Telegram.
# A first message is approved without them only while both are on.
autosend_env="${OUTREACH_AUTOSEND_ENABLED:-false}"
autosend_db="$(docker exec aisales-postgres psql -tAqc \
    "SELECT COALESCE((SELECT value ->> 'enabled' FROM app_settings WHERE key = 'autosend'), 'missing');" \
    -U "${POSTGRES_USER:-aisales}" -d "${POSTGRES_DB:-aisales}" 2>/dev/null | tr -d '[:space:]')"
[[ -n "$autosend_db" ]] || autosend_db="unknown"
if [[ "$autosend_env" == "true" && "$autosend_db" == "true" ]]; then
    warn "autosend ON - first messages that pass autosend_blockers() go out without approval; /stop on Telegram turns it off"
elif [[ "$autosend_env" == "true" ]]; then
    ok "autosend off (master switch on, runtime switch ${autosend_db}; /autosend on starts it)"
elif [[ "$autosend_db" == "true" ]]; then
    ok "autosend off (runtime switch on, but OUTREACH_AUTOSEND_ENABLED is not true)"
else
    ok "autosend off (OUTREACH_AUTOSEND_ENABLED=${autosend_env}, runtime switch ${autosend_db}); every draft waits for /approve"
fi
if [[ -f .env ]]; then
    perms="$(ls -l .env | cut -c1-10)"
    case "$perms" in
        -rw-------) ok ".env permissions $perms" ;;
        *)          warn ".env permissions $perms - run: chmod 600 .env" ;;
    esac
fi

printf '\n'
if [[ $FAILURES -eq 0 ]]; then
    echo "healthy"
    exit 0
fi
echo "$FAILURES check(s) failed"
exit 1
