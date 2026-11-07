#!/usr/bin/env bash
# First-run setup for n8n and Ollama, so a new install does not depend on
# clicking through the n8n UI.
#
#   make models          pull every model .env names, build the 64k-context one
#   make n8n-owner       create the n8n owner account from .env (fresh instance only)
#   make credentials     create the n8n credentials the workflows reference, from .env
#   make workflows       import every workflow in n8n/workflows; keeps what was active
#   make dashboard-role  give the aisales_dashboard database role its password
#   make setup           all of the above, in that order
#
#   ./infra/scripts/n8n-setup.sh activate
#                        activate everything except sending (WF-06), the inbox
#                        (WF-08) and the manual pipeline test; Telegram
#                        workflows only when TELEGRAM_BOT_TOKEN is set
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

POSTGRES_CONTAINER=${POSTGRES_CONTAINER:-aisales-postgres}

envval() { { grep -E "^$1=" .env || true; } | tail -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }

need_running() {
  docker ps --format '{{.Names}}' | grep -qx "$1" \
    || { echo "$1 is not running - make up first"; exit 1; }
}

# A query against the application database, one value per line.
pgq() {
  docker exec "$POSTGRES_CONTAINER" psql -v ON_ERROR_STOP=1 -U "$(envval POSTGRES_USER)" \
    -d "$(envval POSTGRES_DB)" -Atc "$1"
}

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
  need_running "$N8N_CONTAINER"

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

owner() {
  need_running "$N8N_CONTAINER"
  local port base email name pw code body first last
  port=$(envval N8N_BIND_PORT); base="http://127.0.0.1:${port:-5678}"
  email=$(envval N8N_OWNER_EMAIL); name=$(envval N8N_OWNER_NAME); pw=$(envval N8N_OWNER_PASSWORD)
  [ -n "$email" ] || { echo "N8N_OWNER_EMAIL is empty in .env - set it, or run ./install.sh"; exit 1; }
  [ -n "$pw" ] || { echo "N8N_OWNER_PASSWORD is empty in .env - run make init"; exit 1; }

  local i=0
  until curl -fsS -o /dev/null "$base/healthz" 2>/dev/null; do
    i=$((i + 1)); [ $i -lt 90 ] || { echo "n8n did not answer on $base"; exit 1; }
    sleep 2
  done

  # /rest/settings is public: the editor reads it before anyone logs in.
  if curl -fsS "$base/rest/settings" 2>/dev/null | python3 -c '
import json, sys
um = json.load(sys.stdin).get("data", {}).get("userManagement", {})
sys.exit(0 if um.get("showSetupOnFirstLoad") is False else 1)' 2>/dev/null; then
    echo "n8n owner already set up - nothing to do"
    return 0
  fi

  name=${name:-AI Sales Operator}
  first=${name%% *}; last=${name#* }
  [ "$last" != "$name" ] || last="Operator"
  body=$(mktemp)
  # The password reaches curl on stdin, never in an argument list.
  code=$(OWNER_EMAIL="$email" OWNER_FIRST="$first" OWNER_LAST="$last" OWNER_PW="$pw" python3 -c '
import json, os
print(json.dumps({"email": os.environ["OWNER_EMAIL"], "firstName": os.environ["OWNER_FIRST"],
                  "lastName": os.environ["OWNER_LAST"], "password": os.environ["OWNER_PW"]}))' \
    | curl -sS -o "$body" -w '%{http_code}' -H 'Content-Type: application/json' \
           --data-binary @- "$base/rest/owner/setup")
  local ok=0
  if [ "$code" = 200 ]; then
    echo "n8n owner created: $email (password: N8N_OWNER_PASSWORD in .env)"
  elif grep -q 'already setup' "$body"; then
    echo "n8n owner already set up - nothing to do"
  else
    echo "n8n owner setup failed (HTTP $code):"
    python3 -c 'import json,sys; print("  " + json.load(open(sys.argv[1])).get("message", "?"))' "$body" 2>/dev/null \
      || head -c 300 "$body"
    ok=1
  fi
  rm -f "$body"
  return $ok
}

dashboard() {
  need_running "$POSTGRES_CONTAINER"
  local pw q="'"
  pw=$(envval DASHBOARD_DB_PASSWORD)
  [ -n "$pw" ] || { echo "DASHBOARD_DB_PASSWORD is empty in .env - run make init"; exit 1; }
  if [ "$(pgq "select count(*) from pg_roles where rolname = 'aisales_dashboard'")" != 1 ]; then
    echo "role aisales_dashboard does not exist yet (make migrate creates it) - skipped"
    return 0
  fi
  # SQL on stdin, so the password is in no argument list on the host or in the
  # container. %L quotes it; '' doubles any quote for psql's \set.
  printf '%s\n' \
    "\\set pw '${pw//$q/$q$q}'" \
    "SELECT format('ALTER ROLE aisales_dashboard WITH LOGIN PASSWORD %L', :'pw') \\gexec" \
    | docker exec -i "$POSTGRES_CONTAINER" psql -v ON_ERROR_STOP=1 -q \
        -U "$(envval POSTGRES_USER)" -d "$(envval POSTGRES_DB)" >/dev/null
  echo "aisales_dashboard can log in (password: DASHBOARD_DB_PASSWORD in .env)"
}

# Everything that finds, researches, scores and drafts - nothing that sends or
# reads the inbox. WF-06 and WF-08 are switched on by hand once the mailbox is
# set up (README, "Turn it on"); the pipeline test only has a manual trigger.
activate() {
  need_running "$N8N_CONTAINER"; need_running "$POSTGRES_CONTAINER"
  local skip="'wf06OutreachDispatch','wf08InboxClassifier','wf00PipelineTest'"
  if [ -z "$(envval TELEGRAM_BOT_TOKEN)" ]; then
    skip="$skip,'wf10TelegramDispatch','wf11TelegramCommands'"
    echo "TELEGRAM_BOT_TOKEN is empty - leaving the Telegram workflows off"
  fi
  local ids id n=0
  ids=$(pgq "select id from n8n.workflow_entity where not active and id not in ($skip) order by id")
  for id in $ids; do
    docker exec "$N8N_CONTAINER" n8n update:workflow --id="$id" --active=true >/dev/null 2>&1 \
      && n=$((n + 1)) || echo "  could not activate $id"
  done
  echo "activated $n workflow(s). Restart n8n (make restart SERVICE=n8n) for the schedules to start."
}

workflows() {
  need_running "$N8N_CONTAINER"
  python3 infra/scripts/validate-workflows.py
  # Import deactivates every workflow it touches (n8n/README.md), so remember
  # what was on and turn exactly that back on - re-running setup must not
  # quietly switch a running pipeline off.
  local was_active="" id
  if docker ps --format '{{.Names}}' | grep -qx "$POSTGRES_CONTAINER"; then
    was_active=$(pgq "select id from n8n.workflow_entity where active order by id" 2>/dev/null || true)
  fi
  # --separate is required even for a directory of single-object files.
  docker exec "$N8N_CONTAINER" n8n import:workflow --separate --input=/workflows
  for id in $was_active; do
    docker exec "$N8N_CONTAINER" n8n update:workflow --id="$id" --active=true >/dev/null 2>&1 \
      || echo "  could not re-activate $id"
  done
  [ -z "$was_active" ] || echo "re-activated: $(echo $was_active)"
  echo "imported. Restart n8n (make restart SERVICE=n8n) so it loads them."
}

case "${1:-}" in
  models) models ;;
  credentials) credentials ;;
  workflows) workflows ;;
  owner) owner ;;
  dashboard) dashboard ;;
  activate) activate ;;
  all) models; owner; credentials; workflows; dashboard ;;
  *) echo "usage: $0 models|owner|credentials|workflows|dashboard|activate|all"; exit 2 ;;
esac
