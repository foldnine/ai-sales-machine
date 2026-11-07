#!/usr/bin/env bash
#
# AI Sales Machine - guided install.
#
#   ./install.sh                 ask a few questions, then set everything up
#   ./install.sh --yes           no questions: defaults and INSTALL_* variables
#   ./install.sh --skip-models   do not pull Ollama models (set them up later: make models)
#   ./install.sh --activate      also switch on discovery, research, scoring, drafting
#   ./install.sh --no-activate   never ask about that
#
# Safe to re-run at any time: secrets already in .env are kept, the n8n owner
# is created only once, workflows that were active stay active, and nothing
# that sends email is ever switched on here.
#
# Non-interactive values (with --yes, or to pre-fill the questions):
#   INSTALL_TIMEZONE  INSTALL_EMAIL  INSTALL_NAME  INSTALL_COMPANY  INSTALL_WEBSITE
#   INSTALL_TELEGRAM_TOKEN  INSTALL_TELEGRAM_CHAT_ID  INSTALL_ACTIVATE=yes|no
#
# Written for bash 3.2 (macOS) as well as Linux: no associative arrays, no
# mapfile, no ${var,,}.

set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"

YES=0
SKIP_MODELS=0
ACTIVATE="${INSTALL_ACTIVATE:-}"

usage() { sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)       YES=1 ;;
        --skip-models)  SKIP_MODELS=1 ;;
        --activate)     ACTIVATE=yes ;;
        --no-activate)  ACTIVATE=no ;;
        -h|--help)      usage; exit 0 ;;
        *) echo "unknown option: $1"; usage; exit 2 ;;
    esac
    shift
done

# --- output -----------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    B=$'\033[1m'; D=$'\033[2m'; R=$'\033[0m'
    GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; BLUE=$'\033[34m'; CYAN=$'\033[36m'
else
    B=""; D=""; R=""; GREEN=""; YELLOW=""; RED=""; BLUE=""; CYAN=""
fi

step()  { printf '\n%s==>%s %s%s%s\n' "$B$BLUE" "$R" "$B" "$1" "$R"; }
ok()    { printf '  %s✓%s %s\n' "$GREEN" "$R" "$1"; }
warn()  { printf '  %s!%s %s\n' "$YELLOW" "$R" "$1"; }
fail()  { printf '\n  %s✗ %s%s\n' "$RED" "$1" "$R" >&2; exit 1; }
note()  { printf '  %s%s%s\n' "$D" "$1" "$R"; }

# Run a command with its output indented and dimmed. On failure, say how to
# carry on: every step is idempotent, so re-running the installer resumes.
run() {
    local label="$1"; shift
    if ! "$@" 2>&1 | sed "s/^/    $D/; s/\$/$R/"; then
        fail "$label failed. Fix the cause above, then run ./install.sh again - it picks up where it stopped."
    fi
}

INTERACTIVE=0
if [ $YES -eq 0 ] && [ -t 0 ]; then INTERACTIVE=1; fi

# ask <default> <question> -> answer on stdout
ask() {
    local def="$1" q="$2" ans=""
    if [ $INTERACTIVE -eq 1 ]; then
        if [ -n "$def" ]; then
            printf '  %s?%s %s %s[%s]%s ' "$CYAN" "$R" "$q" "$D" "$def" "$R" >&2
        else
            printf '  %s?%s %s ' "$CYAN" "$R" "$q" >&2
        fi
        IFS= read -r ans || true
    fi
    printf '%s' "${ans:-$def}"
}

# confirm <default y|n> <question>
confirm() {
    local def="$1" q="$2" ans
    if [ $INTERACTIVE -eq 0 ]; then
        [ "$def" = y ]
        return
    fi
    if [ "$def" = y ]; then ans=$(ask "Y/n" "$q"); else ans=$(ask "y/N" "$q"); fi
    case "$ans" in [Yy]|[Yy]es|Y/n) return 0 ;; *) return 1 ;; esac
}

# --- .env -------------------------------------------------------------------

envget() { { grep -E "^$1=" .env 2>/dev/null || true; } | tail -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }

# envset KEY VALUE. The value travels in the environment, not in an argument
# list, so a token is never visible in `ps`. Values with spaces are quoted,
# because healthcheck.sh and migrate.sh source .env with bash.
envset() {
    ENV_KEY="$1" ENV_VALUE="$2" python3 - <<'PY'
import os, re
k, v = os.environ["ENV_KEY"], os.environ["ENV_VALUE"]
if re.search(r'["$`\\\n]', v):
    raise SystemExit(f"{k}: the characters \" $ ` \\ are not allowed in this value")
line = f'{k}="{v}"' if re.search(r"[\s#'()]", v) else f"{k}={v}"
path = ".env"
lines = open(path).read().splitlines()
for i, l in enumerate(lines):
    if l.startswith(k + "="):
        lines[i] = line
        break
else:
    lines.append(line)
open(path, "w").write("\n".join(lines) + "\n")
PY
}

detect_timezone() {
    local tz=""
    if command -v timedatectl >/dev/null 2>&1; then
        tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
    fi
    if [ -z "$tz" ] && [ -L /etc/localtime ]; then
        tz=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
    fi
    if [ -z "$tz" ] && [ -f /etc/timezone ]; then
        tz=$(head -1 /etc/timezone)
    fi
    printf '%s' "${tz:-UTC}"
}

wait_healthy() {
    local name="$1" secs="${2:-180}" i=0 st
    while :; do
        st=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null || echo missing)
        case "$st" in
            healthy|running) return 0 ;;
        esac
        i=$((i + 2))
        [ $i -lt "$secs" ] || { warn "$name is $st after ${secs}s - see: make logs SERVICE=${name#aisales-}"; return 1; }
        sleep 2
    done
}

compose_has() { docker compose config --services 2>/dev/null | grep -qx "$1"; }

# --- 1. prerequisites -------------------------------------------------------

printf '\n%sAI Sales Machine%s %s- self-hosted B2B prospecting, human-approved outreach%s\n' "$B" "$R" "$D" "$R"

step "Checking prerequisites"
missing=""
for c in docker make git openssl python3 curl; do
    if command -v "$c" >/dev/null 2>&1; then ok "$c"; else missing="$missing $c"; fi
done
[ -z "$missing" ] || fail "missing:$missing - install them and run ./install.sh again (docs/setup.md, Requirements)"

docker info >/dev/null 2>&1 || fail "Docker is installed but not running. Start Docker Desktop (or the docker service) and try again."
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is required ('docker compose', not 'docker-compose')."
ok "docker compose $(docker compose version --short 2>/dev/null)"

# The container names are fixed (aisales-*). Never take over a stack that
# another checkout started.
for c in aisales-postgres aisales-n8n; do
    dir=$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "$c" 2>/dev/null || true)
    if [ -n "$dir" ] && [ "$dir" != "$ROOT" ]; then
        fail "$c already exists and belongs to another install in $dir. Stop that stack first; this installer will not touch it."
    fi
done

if command -v ollama >/dev/null 2>&1; then
    ok "ollama $(ollama --version 2>/dev/null | awk '{print $NF}')"
    if ! curl -fsS -o /dev/null http://127.0.0.1:11434/api/version 2>/dev/null; then
        warn "Ollama is installed but not answering on :11434 - start it (ollama serve, or the app)"
    fi
elif [ $SKIP_MODELS -eq 1 ]; then
    warn "Ollama not installed - continuing without models (--skip-models)"
else
    warn "Ollama is not installed. Every agent runs on it: https://ollama.com/download"
    note "macOS: install the app, not a container (docs/ollama.md explains why)."
    if confirm n "Continue without models for now?"; then
        SKIP_MODELS=1
    else
        fail "install Ollama, or run ./install.sh --skip-models and add models later with: make models"
    fi
fi

# --- 2. configuration -------------------------------------------------------

step "Configuration"
first_run=1; [ -f .env ] && first_run=0
run "make init" ./infra/scripts/bootstrap.sh
[ $first_run -eq 1 ] && note "New secrets are in .env (chmod 600). Back up N8N_ENCRYPTION_KEY off this machine."

cur_tz=$(envget GENERIC_TIMEZONE)
def_tz="$cur_tz"; [ -z "$def_tz" ] || [ "$def_tz" = UTC ] && def_tz=$(detect_timezone)
tz=$(ask "${INSTALL_TIMEZONE:-$def_tz}" "Timezone (send windows and schedules use it)")

cur_email=$(envget N8N_OWNER_EMAIL)
email=$(ask "${INSTALL_EMAIL:-$cur_email}" "Your email (your n8n login)")
if [ -z "$email" ]; then
    email="operator@example.com"
    warn "no email given - using $email as the n8n login (change it in n8n later)"
fi

sig_has_placeholder=0; grep -qx 'Your Name' prompts/signature.md && sig_has_placeholder=1
offers_has_placeholder=0; grep -q '"tagline[a-z_]*": "Your Company' agents/offers.json && offers_has_placeholder=1
url_has_placeholder=0; grep -q '"url": "https://example.com' agents/offers.json && url_has_placeholder=1

name=""; company=""; website=""
if [ $sig_has_placeholder -eq 1 ] || [ -n "${INSTALL_NAME:-}" ]; then
    name=$(ask "${INSTALL_NAME:-}" "Your name, as it should appear under every email (Enter to skip)")
fi
if [ $offers_has_placeholder -eq 1 ] || [ -n "${INSTALL_COMPANY:-}" ]; then
    company=$(ask "${INSTALL_COMPANY:-}" "Your company name (Enter to skip)")
fi
if [ $url_has_placeholder -eq 1 ] || [ -n "${INSTALL_WEBSITE:-}" ]; then
    website=$(ask "${INSTALL_WEBSITE:-}" "Your website, e.g. https://yourcompany.com (Enter to skip)")
fi
case "$website" in
    ""|http://*|https://*) ;;
    *) website="https://$website" ;;
esac
website="${website%/}"

note "Telegram is where drafts are approved and alerts arrive. Optional now: the dashboard can approve too."
note "Create a bot with @BotFather; your chat id is shown by @userinfobot."
tg_token=$(ask "${INSTALL_TELEGRAM_TOKEN:-$(envget TELEGRAM_BOT_TOKEN)}" "Telegram bot token (Enter to skip)")
tg_chat=""
if [ -n "$tg_token" ]; then
    tg_chat=$(ask "${INSTALL_TELEGRAM_CHAT_ID:-$(envget TELEGRAM_CHAT_ID)}" "Telegram chat id")
fi
note "Mail (SMTP/IMAP) comes later, once you are ready to send: docs/mail.md"

envset GENERIC_TIMEZONE "$tz"
envset TZ "$tz"
envset N8N_OWNER_EMAIL "$email"
if [ -n "$name" ]; then
    envset N8N_OWNER_NAME "$name"
    [ -n "$(envget EMAIL_FROM_NAME)" ] || envset EMAIL_FROM_NAME "$name"
fi
if [ -n "$tg_token" ]; then
    envset TELEGRAM_BOT_TOKEN "$tg_token"
    envset TELEGRAM_CHAT_ID "$tg_chat"
    envset TELEGRAM_ENABLED true
fi
if [ -n "$website" ] && envget BOT_USER_AGENT | grep -q 'example.com'; then
    envset BOT_USER_AGENT "AiSalesMachineBot/1.0 (+$website)"
fi
ok "timezone $tz, n8n login $email${tg_token:+, Telegram on}"

# Sender identity: only the placeholders are replaced, nothing else in the files.
if [ -n "$name$company$website" ]; then
    CUST_NAME="$name" CUST_COMPANY="$company" CUST_WEBSITE="$website" python3 - <<'PY'
import json, os, re
name, company, site = (os.environ[k] for k in ("CUST_NAME", "CUST_COMPANY", "CUST_WEBSITE"))
changes = []

if name:
    p = "prompts/signature.md"
    lines = open(p, encoding="utf-8").read().split("\n")
    n = sum(1 for l in lines if l == "Your Name")
    if n:
        open(p, "w", encoding="utf-8").write("\n".join(name if l == "Your Name" else l for l in lines))
        changes.append(f"{p}: signature name -> {name} ({n} signatures)")

p = "agents/offers.json"
text = open(p, encoding="utf-8").read()
before = text
if company:
    text = re.sub(r'("tagline(?:_sr)?": ")Your Company', lambda m: m.group(1) + company, text)
if site:
    text = re.sub(r'("url": ")https://example\.com', lambda m: m.group(1) + site, text)
if text != before:
    json.loads(text)  # never leave the catalogue unparseable
    open(p, "w", encoding="utf-8").write(text)
    if company:
        changes.append(f"{p}: taglines now start with {company}")
    if site:
        changes.append(f"{p}: offer URLs now on {site}")

for c in changes:
    print("  ✓ " + c)
PY
    note "These are edits to tracked files: keep them on your own branch or fork (docs/customizing.md)."
fi
if grep -qx 'Your Name' prompts/signature.md; then
    warn "prompts/signature.md still says 'Your Name' - nothing is sent until you approve it, but fix it before you do"
fi

# --- 3. the stack -----------------------------------------------------------

step "Starting the stack"
run "make up" make up
wait_healthy aisales-postgres 120 && ok "PostgreSQL"
wait_healthy aisales-n8n 240 && ok "n8n"
if compose_has dashboard; then
    wait_healthy aisales-dashboard 180 && ok "dashboard" || true
fi

step "Database"
run "make migrate" make migrate

if docker exec aisales-n8n wget -q -T 5 -O /dev/null http://ollama:11434/api/version 2>/dev/null; then
    ok "n8n reaches Ollama"
else
    warn "n8n cannot reach Ollama at OLLAMA_BASE_URL. On Linux, Ollama must listen beyond 127.0.0.1 (docs/ollama.md)."
fi

if [ $SKIP_MODELS -eq 0 ]; then
    step "Models (several GB the first time - this takes a while)"
    run "make models" make models
else
    note "Skipping models. Later: make models"
fi

step "n8n"
run "make n8n-owner" make n8n-owner
run "make credentials" make credentials
run "make workflows" make workflows

step "Dashboard"
run "make dashboard-role" make dashboard-role
if compose_has dashboard; then
    run "restart dashboard" docker compose restart dashboard
    wait_healthy aisales-dashboard 120 && ok "dashboard up" || true
fi

# --- 4. switch on (never sending) -------------------------------------------

step "Workflows"
note "Discovery, research, scoring and drafting fill the approval queue. Sending (WF-06)"
note "and the inbox (WF-08) stay off until the mailbox is set up, and OUTREACH_PAUSED=true."
if [ -z "$ACTIVATE" ]; then
    if confirm n "Activate discovery, research, scoring and drafting now? (sending stays off)"; then
        ACTIVATE=yes
    else
        ACTIVATE=no
    fi
fi
if [ "$ACTIVATE" = yes ]; then
    if grep -qx 'Your Name' prompts/signature.md; then
        warn "drafts will carry the placeholder signature until you edit prompts/signature.md"
    fi
    run "make activate" make activate
else
    note "Left off. Later: make activate (or switch them on in the n8n editor)."
fi

run "restart n8n" make restart SERVICE=n8n
wait_healthy aisales-n8n 240 && ok "n8n restarted"

step "Health check"
if make health 2>&1 | sed "s/^/    /"; then
    ok "healthy"
else
    warn "make health reported problems - read the lines above (warnings about identity or mail are expected now)"
fi

# --- 5. summary ---------------------------------------------------------------

dash_port=$(envget DASHBOARD_PORT); dash_port=${dash_port:-3000}
n8n_port=$(envget N8N_BIND_PORT); n8n_port=${n8n_port:-5678}
paused=$(envget OUTREACH_PAUSED)

line() { printf '  %s│%s %-64s %s│%s\n' "$D" "$R" "$1" "$D" "$R"; }
rule() { printf '  %s%s%s\n' "$D" "$1" "$R"; }

printf '\n'
rule "╭──────────────────────────────────────────────────────────────────╮"
line "AI Sales Machine is running"
line ""
line "Dashboard   http://localhost:$dash_port"
line "            password: $(envget DASHBOARD_PASSWORD)"
line "            (DASHBOARD_PASSWORD in .env)"
line "n8n editor  http://localhost:$n8n_port"
line "            login: $email"
line "            (password: N8N_OWNER_PASSWORD in .env)"
line ""
line "Sending     OFF - OUTREACH_PAUSED=${paused:-true}, WF-06 inactive"
line ""
line "Next:"
line "  1. Back up N8N_ENCRYPTION_KEY somewhere off this machine"
line "  2. Make it yours           docs/customizing.md"
line "  3. Set up the mailbox      docs/mail.md, then WF-06 and WF-08"
line "  4. Before unpausing        docs/compliance.md"
rule "╰──────────────────────────────────────────────────────────────────╯"
note "Remote access: tailscale serve --bg $dash_port  (never a port forward - docs/setup.md)"
printf '\n'
