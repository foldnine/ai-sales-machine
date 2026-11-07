#!/usr/bin/env bash
#
# Bring an existing .env in line with the current .env.example, without
# touching a single secret.
#
# .env is created once by bootstrap.sh and never regenerated, so when a
# variable is removed from the stack it stays behind in every deployed .env.
# This removes the ones the stack no longer reads, adds the ones it now does,
# and changes a default on purpose when one changes. Everything else is left exactly as it is.
#
#   ./infra/scripts/env-upgrade.sh            show what would change
#   ./infra/scripts/env-upgrade.sh --apply    change it (a copy is kept first)
#
# Safe to run twice: the second run finds nothing to do.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE=".env"
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

if [[ ! -f "$ENV_FILE" ]]; then
    echo "error: no .env here. A fresh install uses 'make init', not this." >&2
    exit 1
fi

# Removed in the change that dropped Redis and n8n basic auth. Neither was
# doing anything: n8n never ran in queue mode, and basic auth was removed from
# n8n in 1.0.
OBSOLETE='^(REDIS_PASSWORD|REDIS_HOST|REDIS_PORT|REDIS_BIND_ADDR|REDIS_BIND_PORT|REDIS_IMAGE|N8N_BASIC_AUTH_ACTIVE|N8N_BASIC_AUTH_USER|N8N_BASIC_AUTH_PASSWORD)='

changes=0

echo "==> variables the stack no longer reads"
if grep -Eq "$OBSOLETE" "$ENV_FILE"; then
    # Names only: the values are secrets and have no business in a terminal.
    grep -E "$OBSOLETE" "$ENV_FILE" | cut -d= -f1 | sed 's/^/    remove  /'
    changes=1
else
    echo "    none"
fi

echo "==> variables the stack now reads"
add_caddy=0
if ! grep -q '^CADDY_BIND_ADDR=' "$ENV_FILE"; then
    echo "    add     CADDY_BIND_ADDR=127.0.0.1"
    add_caddy=1
    changes=1
fi
add_ua=0
if ! grep -q '^BOT_USER_AGENT=' "$ENV_FILE"; then
    echo "    add     BOT_USER_AGENT   (put your own contact URL in it)"
    add_ua=1
    changes=1
fi
# Added with the dashboard and the automatic n8n owner. Secrets are generated
# on --apply, never shown; the rest get the .env.example default.
NEW_VARS="N8N_OWNER_EMAIL N8N_OWNER_NAME N8N_OWNER_PASSWORD DASHBOARD_PASSWORD DASHBOARD_SESSION_SECRET DASHBOARD_DB_PASSWORD DASHBOARD_BIND_ADDR DASHBOARD_PORT"
missing_new=""
for v in $NEW_VARS; do
    if ! grep -q "^${v}=" "$ENV_FILE"; then
        echo "    add     $v"
        missing_new="$missing_new $v"
        changes=1
    fi
done
if [[ $add_caddy -eq 0 && $add_ua -eq 0 && -z "$missing_new" ]]; then
    echo "    none"
fi

echo "==> defaults changed on purpose"
# The GitHub commit route is off by default now (migration 0016,
# docs/contact-enrichment.md). A .env written before that change says true
# only because the old .env.example did, so it is turned off here. Turn it
# back on by hand, deliberately, if that is what you want.
set_github=0
if grep -q '^ENRICH_GITHUB_ENABLED=true' "$ENV_FILE"; then
    echo "    set     ENRICH_GITHUB_ENABLED=false   (see docs/contact-enrichment.md)"
    set_github=1
    changes=1
fi

if [[ $set_github -eq 0 ]]; then
    echo "    none"
fi

if [[ $changes -eq 0 ]]; then
    echo
    echo ".env is already current."
    exit 0
fi

if [[ $APPLY -eq 0 ]]; then
    echo
    echo "Nothing changed. Run again with --apply (or make env-upgrade APPLY=yes) to make these changes."
    exit 0
fi

backup="$ENV_FILE.bak-$(date +%Y%m%d-%H%M%S)"
cp -p "$ENV_FILE" "$backup"

tmp="$(mktemp)"
grep -Ev "$OBSOLETE" "$ENV_FILE" > "$tmp" || true
if [[ $set_github -eq 1 ]]; then
    # Portable in-place edit: BSD sed on macOS has a different -i.
    sed 's|^ENRICH_GITHUB_ENABLED=true|ENRICH_GITHUB_ENABLED=false|' "$tmp" > "$tmp.2"
    mv "$tmp.2" "$tmp"
fi
if [[ $add_caddy -eq 1 ]]; then
    printf '\n# Host address Caddy binds to. Loopback: nothing needs inbound traffic.\nCADDY_BIND_ADDR=127.0.0.1\n' >> "$tmp"
fi

if [[ $add_ua -eq 1 ]]; then
    printf '\n# How the crawlers identify themselves. Put your own site or contact URL here.\nBOT_USER_AGENT="AiSalesMachineBot/1.0 (+https://example.com/bot)"\n' >> "$tmp"
fi

gen_hex() { openssl rand -hex "$1" 2>/dev/null || LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c $(( $1 * 2 )); }
if [[ -n "$missing_new" ]]; then
    printf '\n# Added by env-upgrade (n8n owner, dashboard). See .env.example.\n' >> "$tmp"
    for v in $missing_new; do
        case "$v" in
            N8N_OWNER_PASSWORD)       val="Ai$(gen_hex 10)7" ;;
            DASHBOARD_PASSWORD)       val="$(gen_hex 12)" ;;
            DASHBOARD_SESSION_SECRET) val="$(gen_hex 32)" ;;
            DASHBOARD_DB_PASSWORD)    val="$(gen_hex 24)" ;;
            N8N_OWNER_NAME)           val='"AI Sales Operator"' ;;
            DASHBOARD_BIND_ADDR)      val="127.0.0.1" ;;
            DASHBOARD_PORT)           val="3000" ;;
            *)                        val="" ;;
        esac
        printf '%s=%s\n' "$v" "$val" >> "$tmp"
    done
fi

cat "$tmp" > "$ENV_FILE"   # keeps the file's own permissions
rm -f "$tmp"
chmod 600 "$ENV_FILE" "$backup"

echo
echo "Done. The previous version is $backup (gitignored, chmod 600)."
echo "Delete it once the stack is confirmed healthy: it still holds the old secrets."
