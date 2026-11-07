#!/usr/bin/env bash
# First-run setup for n8n and Ollama, so a new install does not depend on
# clicking through the n8n UI.
#
#   make models        pull every model .env names, build the 64k-context one
#   make credentials   create the n8n credentials the workflows reference, from .env
#   make workflows     import every workflow in n8n/workflows (all inactive)
#   make setup         all three, in that order
#
# Credentials are created with the exact ids the workflow JSON references, so an
# imported workflow finds its credential without anyone re-linking nodes. The
# JSON is generated in memory, piped into the container, imported (n8n encrypts
# it with N8N_ENCRYPTION_KEY) and deleted. It never touches the repository.
#
# Re-running `make credentials` overwrites those five credentials with what .env
# says now. That is the point: .env is the source of truth for them.
set -euo pipefail
cd "$(dirname "$0")/../.."

[ -f .env ] || { echo "no .env - run make init first"; exit 1; }
N8N_CONTAINER=${N8N_CONTAINER:-aisales-n8n}

envval() { grep -E "^$1=" .env | tail -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }

models() {
  command -v ollama >/dev/null || { echo "ollama is not installed on this host (docs/ollama.md)"; exit 1; }
  local wanted
  wanted=$(grep -E '^OLLAMA_[A-Z_]*MODEL=' .env | cut -d= -f2- | sort -u)
  for m in $wanted; do
    [ -n "$m" ] || continue
    local base=${m%:latest}
    if [ -f "infra/ollama/$base.Modelfile" ]; then
      # A local variant (e.g. a larger context window): pull what it is built
      # FROM, then create it under the name .env uses.
      local from
      from=$(awk '/^FROM /{print $2; exit}' "infra/ollama/$base.Modelfile")
      echo "==> $m (built from $from)"
      ollama pull "$from"
      ollama create "$base" -f "infra/ollama/$base.Modelfile"
    else
      echo "==> $m"
      ollama pull "$m"
    fi
  done
}

credentials() {
  docker ps --format '{{.Names}}' | grep -qx "$N8N_CONTAINER" \
    || { echo "$N8N_CONTAINER is not running - make up first"; exit 1; }

  export PGUSER_V PGPASS_V PGDB_V PGHOST_V PGPORT_V OLLAMA_V TG_V \
         SMTP_HOST_V SMTP_PORT_V SMTP_USER_V SMTP_PASS_V SMTP_SECURE_V \
         IMAP_HOST_V IMAP_PORT_V IMAP_USER_V IMAP_PASS_V
  PGUSER_V=$(envval POSTGRES_USER);   PGPASS_V=$(envval POSTGRES_PASSWORD)
  PGDB_V=$(envval POSTGRES_DB);       PGHOST_V=$(envval POSTGRES_HOST)
  PGPORT_V=$(envval POSTGRES_PORT);   OLLAMA_V=$(envval OLLAMA_BASE_URL)
  TG_V=$(envval TELEGRAM_BOT_TOKEN)
  SMTP_HOST_V=$(envval SMTP_HOST);    SMTP_PORT_V=$(envval SMTP_PORT)
  SMTP_USER_V=$(envval SMTP_USER);    SMTP_PASS_V=$(envval SMTP_PASSWORD)
  SMTP_SECURE_V=$(envval SMTP_SECURE)
  IMAP_HOST_V=$(envval IMAP_HOST);    IMAP_PORT_V=$(envval IMAP_PORT)
  IMAP_USER_V=$(envval IMAP_USER);    IMAP_PASS_V=$(envval IMAP_PASSWORD)

  python3 - <<'PY' | docker exec -i "$N8N_CONTAINER" sh -c \
    'umask 077; cat > /tmp/creds.json && n8n import:credentials --input=/tmp/creds.json; rc=$?; rm -f /tmp/creds.json; exit $rc'
import json, os, sys
e = os.environ.get
creds = [
    {"id": "vUxYVHnmuty8Jcgk", "name": "Postgres account", "type": "postgres",
     "data": {"host": e("PGHOST_V") or "postgres", "port": int(e("PGPORT_V") or 5432),
              "database": e("PGDB_V"), "user": e("PGUSER_V"), "password": e("PGPASS_V"),
              "ssl": "disable"}},
    {"id": "iZbPMscIrJAawH4X", "name": "Ollama account", "type": "ollamaApi",
     "data": {"baseUrl": e("OLLAMA_V") or "http://ollama:11434"}},
]
skipped = []
if e("TG_V"):
    creds.append({"id": "Ss2Ff8xj69SABZq4", "name": "Telegram account", "type": "telegramApi",
                  "data": {"accessToken": e("TG_V")}})
else:
    skipped.append("Telegram (TELEGRAM_BOT_TOKEN empty)")
if e("SMTP_HOST_V") and e("SMTP_USER_V"):
    creds.append({"id": "smtpOutbound", "name": "SMTP account", "type": "smtp",
                  "data": {"host": e("SMTP_HOST_V"), "port": int(e("SMTP_PORT_V") or 465),
                           "user": e("SMTP_USER_V"), "password": e("SMTP_PASS_V"),
                           "secure": (e("SMTP_SECURE_V") or "true").lower() == "true"}})
else:
    skipped.append("SMTP (SMTP_HOST/SMTP_USER empty)")
if e("IMAP_HOST_V") and e("IMAP_USER_V"):
    creds.append({"id": "imapInbound", "name": "IMAP account", "type": "imap",
                  "data": {"host": e("IMAP_HOST_V"), "port": int(e("IMAP_PORT_V") or 993),
                           "user": e("IMAP_USER_V"), "password": e("IMAP_PASS_V"),
                           "secure": True}})
else:
    skipped.append("IMAP (IMAP_HOST/IMAP_USER empty)")
for s in skipped:
    print("skipped: " + s + " - fill it in .env and re-run make credentials", file=sys.stderr)
json.dump(creds, sys.stdout)
PY
}

workflows() {
  docker ps --format '{{.Names}}' | grep -qx "$N8N_CONTAINER" \
    || { echo "$N8N_CONTAINER is not running - make up first"; exit 1; }
  python3 infra/scripts/validate-workflows.py
  # --separate is required even for a directory of single-object files
  # (n8n/README.md). Import leaves every workflow inactive; activating them is
  # a deliberate step (README.md, "Turn it on").
  docker exec "$N8N_CONTAINER" n8n import:workflow --separate --input=/workflows
  echo "imported. Restart n8n (make restart SERVICE=n8n) so it loads them, then activate in the editor."
}

case "${1:-}" in
  models) models ;;
  credentials) credentials ;;
  workflows) workflows ;;
  all) models; credentials; workflows ;;
  *) echo "usage: $0 models|credentials|workflows|all"; exit 2 ;;
esac
