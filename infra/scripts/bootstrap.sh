#!/usr/bin/env bash
#
# First-run setup: create .env and Caddyfile from the committed templates and
# fill in the values that must be random. Never overwrites an existing .env.
#
#   ./infra/scripts/bootstrap.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

gen_secret() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex "${1:-24}"
    else
        LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c $(( ${1:-24} * 2 ))
        echo
    fi
}

set_var() {
    local key="$1" value="$2" file="$3"
    if grep -q "^${key}=" "$file"; then
        # Portable in-place edit: BSD sed on macOS needs the -i argument.
        sed "s|^${key}=.*|${key}=${value}|" "$file" > "$file.tmp"
        mv "$file.tmp" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

get_var() { { grep -E "^$1=" .env || true; } | tail -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }

# n8n wants 8-64 characters with a number and an uppercase letter.
gen_owner_password() { printf 'Ai%s7' "$(gen_secret 10)"; }

if [[ -f .env ]]; then
    echo ".env already exists - keeping every value in it."
else
    cp .env.example .env
    chmod 600 .env
    echo "created .env from .env.example"
fi

# Every value that must be random, filled only while it is empty. Re-running
# never changes a secret that is already set, so this is safe on a live .env
# and is how an older .env picks up a secret added later.
generated=""
fill() {
    local key="$1" value="$2"
    if [[ -z "$(get_var "$key")" ]]; then
        set_var "$key" "$value" .env
        generated="$generated $key"
    fi
}
fill POSTGRES_PASSWORD        "$(gen_secret 24)"
fill N8N_ENCRYPTION_KEY       "$(gen_secret 32)"
fill BACKUP_PASSPHRASE        "$(gen_secret 24)"
fill N8N_OWNER_PASSWORD       "$(gen_owner_password)"
fill DASHBOARD_PASSWORD       "$(gen_secret 12)"
fill DASHBOARD_SESSION_SECRET "$(gen_secret 32)"
fill DASHBOARD_DB_PASSWORD    "$(gen_secret 24)"
chmod 600 .env
if [[ -n "$generated" ]]; then
    echo "generated:$generated"
fi

if [[ -f Caddyfile ]]; then
    echo "Caddyfile already exists - leaving it untouched."
else
    cp Caddyfile.example Caddyfile
    echo "created Caddyfile from Caddyfile.example"
fi

mkdir -p backups
chmod 700 backups

cat <<'NEXT'

Next steps (./install.sh does all of this for you):
  1. Back up N8N_ENCRYPTION_KEY somewhere other than this machine. Losing it
     makes every credential stored in n8n unrecoverable.
  2. Edit .env: GENERIC_TIMEZONE/TZ, BOT_USER_AGENT, TELEGRAM_*, later SMTP_*/IMAP_*.
  3. make up && make migrate && make setup
  4. make health
NEXT
