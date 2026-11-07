<div align="center">

# AI Sales Machine

**A self-hosted B2B prospecting pipeline that reads public signals, does the
research a good salesperson would, and drafts outreach you would actually
send - on your own hardware, with local models, and with a human in charge of
every email.**

[Quick start](#quick-start) · [How it works](#how-it-works) ·
[Make it yours](docs/customizing.md) · [Docs](#documentation) ·
[Responsible use](docs/compliance.md)

![license](https://img.shields.io/badge/license-MIT-blue)
![self-hosted](https://img.shields.io/badge/self--hosted-yes-success)
![local models](https://img.shields.io/badge/LLM-Ollama%20(local)-informational)
![stack](https://img.shields.io/badge/stack-n8n%20%2B%20PostgreSQL-orange)

</div>

---

## Why

Most outbound tooling is a lead database plus a mail-merge. Everyone gets the
same list and sends the same email, and recipients have learned to delete it.

The premise here is different: **the useful signal is already public.** Take
a company that posted a Senior DevOps role sixty days ago and blogged about a
Kubernetes migration last month. It has told you what it needs, when, and in
its own words. Nobody acts on that because reading it at scale is tedious, not
because it is hard.

This system does that reading. It finds companies with evidence of a need,
researches them, keeping facts apart from inference. It scores them against
a rubric and writes one short, specific message per company. Then it waits
for you to approve it on Telegram.

Everything else exists to keep that judgement repeatable and to stop it from
turning into spam: the schema, the guards in the database, the approval queue.

## Features

- **Signal-based discovery** from free, public sources: the Y Combinator
  directory, Hacker News *Who is hiring?*, OpenStreetMap business listings and
  public industry directories. No paid lead database needed.
- **Grounded research.** Fetches a company's own pages and public ATS job
  boards (Greenhouse, Lever, Ashby, Workable, Personio...), respects
  `robots.txt` and per-domain cooldowns. Research output separates *facts*,
  *inferences* and *unknowns*, and every claim carries its source URL.
- **A 100-point scoring rubric** where missing evidence scores zero, with a
  score band computed by the database, not the model.
- **Outreach that may refuse to write.** About 120 words, one sourced problem,
  one offer, one question. If the evidence is too thin, the agent declines.
- **Human approval on Telegram.** `/approve`, `/reject`, daily report, alerts.
  Optional *guarded autosend* for first messages that pass every automated
  check, off by default.
- **Reply handling.** The inbox classifier sorts replies into eight categories,
  honours opt-outs in code and in several languages, and drafts a suggested
  answer for you to send.
- **Local-first AI.** Every agent runs on [Ollama](https://ollama.com) on the
  same machine. No API key is required and no prospect data leaves your box.
- **Safety enforced by the database, not by hope.** A trigger rejects any
  message to a suppressed address, and unique indexes prevent duplicate sends
  on retry. A single `OUTREACH_PAUSED` switch stops everything.
- **Multi-language outreach.** English plus Serbian out of the box. Add a
  language by adding a greeting, a signature and opt-out phrases.
- **Boring, inspectable stack.** n8n + PostgreSQL + Ollama + Caddy. Prompts
  are Markdown files and agent contracts are JSON Schema. Every LLM call is
  logged in `agent_runs`.

## How it works

```
                 ┌──────────────── n8n (orchestration, schedules, retries) ─────────────────┐
 public sources  │                                                                         │
 YC · HN · OSM ──┼─▶ WF-01 discover ─▶ WF-02 research ─▶ WF-03 contacts ─▶ WF-04 score     │
 directories     │                                                        │                │
                 │                                                        ▼                │
                 │   WF-08 classify ◀── IMAP      WF-06 send ◀── [ YOU APPROVE ] ◀── WF-05 draft
                 │        │                           │               ▲                    │
                 │        ▼                           ▼               │                    │
                 │   reply draft ─────────────▶  Telegram  ◀──────────┘  daily report, alerts
                 └────────────┬──────────────────────────────────────────────────────────┘
                              ▼
               PostgreSQL (system of record: suppression, dedup, scoring bands, audit log)
               Ollama on the host (all models, local)
```

| Workflow | Does | Schedule |
|---|---|---|
| WF-00 | Pipeline test: one end-to-end smoke test | manual |
| WF-01 | Discover companies from public directories | daily |
| WF-02 | Research: fetch pages and job boards, extract evidence | every 30 min |
| WF-03 | Find the decision maker (or the published role address) | hourly |
| WF-04 | Score against the rubric, plus a nightly re-scoring sweep | every 15 min |
| WF-05 | Draft outreach, run the quality checks, queue for approval | hourly |
| WF-06 | **The only workflow that sends**, approved rows only, inside a send window | every 15 min |
| WF-08 | Classify replies, honour opt-outs, draft an answer | IMAP |
| WF-10/11 | Telegram notifications and commands | every 5 min / webhook |
| WF-12 | Refresh OpenStreetMap snapshots | daily |
| WF-99/100/101 | Error handling, daily report, agent health | - |

WF-07 (follow-ups) and WF-09 (autonomous conversation) are designed but not
built. Nothing follows up and nothing answers a reply without a person. See
[`docs/roadmap.md`](docs/roadmap.md).

## Requirements

| | Minimum | Recommended |
|---|---|---|
| Machine | Any always-on Linux or macOS host | Apple silicon with 32 GB+ unified memory, or Linux with a 24 GB GPU |
| Memory for models | 16 GB (swap the 27B models for smaller ones in `.env`) | 32 GB+ |
| Disk | 60 GB | 100 GB |
| Software | Docker + Compose, `make`, `git`, `openssl`, `python3`, [Ollama](https://ollama.com) on the host | + `gpg` for encrypted backups, Tailscale for remote access |
| Accounts | - | A Telegram bot, and a sending mailbox on **your own domain** with SPF/DKIM/DMARC |

Throughput is bounded by the GPU, not by the pipeline. On an M4 Pro, one
company takes roughly 7 GPU minutes (research about 4.6, scoring about 2.3).
That is about 150 companies a day, which is plenty for an approval queue a
person reads.

> **macOS:** run Ollama natively, not in Docker. Docker on macOS has no Metal
> access, so a containerised model runs on the CPU. The stack already expects
> this. See [`docs/ollama.md`](docs/ollama.md).

## Quick start

```bash
git clone https://github.com/foldnine/ai-sales-machine.git
cd ai-sales-machine

make init           # creates .env and Caddyfile, generates every secret
```

Open `.env` and set at least:

| Variable | What |
|---|---|
| `GENERIC_TIMEZONE`, `TZ` | Your timezone. Send windows and schedules use it. |
| `BOT_USER_AGENT` | How your crawler identifies itself. Put **your** contact URL in it. |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | From [@BotFather](https://t.me/BotFather). This is where approvals happen. |
| `SMTP_*`, `IMAP_*`, `EMAIL_FROM*` | Your sending mailbox. Can wait until you are ready to send. |

Back up `N8N_ENCRYPTION_KEY` somewhere other than this machine **now**. Every
credential n8n stores is encrypted with it.

Then bring it up:

```bash
make up             # PostgreSQL, n8n, Caddy (Ollama runs on the host)
make migrate        # create the schema
make models         # pull every model .env names (several GB)
```

Open n8n at <http://localhost:5678> and create the owner account. Do it right
away: until then, anyone who can reach the editor owns it. Then:

```bash
make credentials    # create the n8n credentials from .env (Postgres, Ollama, Telegram, SMTP, IMAP)
make workflows      # import every workflow, all inactive
make restart SERVICE=n8n
make health         # should end with "healthy"
```

`make setup` runs models, credentials and workflows in one go.

### Make it yours (before anything is sent)

Out of the box the pipeline is configured as a reference example: a small
consultancy selling **DevOps/SRE infrastructure audits** to growing tech
companies, and **process automation** to small businesses. To sell what *you*
sell:

1. **`agents/offers.json`**: your offer lines, offers, taglines and URLs.
2. **`prompts/signature.md`**: your name, company, legal identity and
   opt-out line. *Required.* `make health` warns while it still says
   `Your Name`.
3. **The `<!-- CUSTOMIZE -->` blocks in `prompts/`**: how the research,
   scoring and outreach agents describe your business and your ideal customer.
4. **ICP segments and discovery sources**: which directories to read and how
   the daily discovery budget is split.

The full guide is [`docs/customizing.md`](docs/customizing.md).

### Turn it on, in this order

1. Activate **WF-00 Pipeline Test** and run it once. It exercises the
   database, the model and Telegram end to end.
2. Activate **WF-99**, **WF-10/11** (Telegram) and **WF-101** (agent health).
3. Activate **WF-01 → WF-05**. Drafts start arriving in Telegram. Read them
   for a week. This is where you tune prompts and rubric.
4. Set up the mailbox ([`docs/mail.md`](docs/mail.md)), warm it up, then
   activate **WF-06** and **WF-08**.
5. Only now set `OUTREACH_PAUSED=false`. Messages still go out one approval
   at a time, at most `OUTREACH_DAILY_LIMIT` a day.

## Safety model

The system assumes a model will eventually be wrong, talked into something,
or both. The limits that matter are therefore enforced twice: stated in the
prompt, and checked in code or in the database after the model returns.

- **Human approval by default.** WF-06 only sends rows a person approved.
  Guarded autosend exists, but it is off unless you turn it on in `.env` *and*
  on Telegram. Even then it only covers first messages that pass every
  blocker, and `/stop` ends it instantly.
- **Suppression is a database trigger.** A workflow bug produces a failed
  transaction, not an email to someone who asked you to stop.
- **Opt-out wins.** "Stop", "unsubscribe" and their equivalents in supported
  languages are detected in code before the classifier is asked anything.
- **Rate limits and a kill switch.** `OUTREACH_DAILY_LIMIT`, send windows,
  per-domain caps, and `OUTREACH_PAUSED=true` as a single stop button.
- **Nothing is exposed.** PostgreSQL, Ollama and n8n bind to `127.0.0.1`. For
  remote access use `tailscale serve`, never a port forward.
- **No tracking.** Plain-text email, no pixels, no link rewriting.
- **Untrusted input stays data.** Fetched pages and inbound replies are
  treated as potential prompt injection: the model's output is schema-checked,
  and it has no tools.

Details: [`docs/security.md`](docs/security.md).

## Responsible use

This is a tool for **sending a small number of relevant, individually approved
B2B emails.** It is not a bulk mailer, and it is deliberately hard to turn into
one.

Cold outreach is regulated: GDPR and national ePrivacy rules in the EU, PECR in
the UK, CAN-SPAM in the US, and CASL in Canada (which needs consent). As the
operator, you are the sender, so the obligations are yours. That means a
lawful basis, a real sender identity and address, a working opt-out, and
honouring it. Read [`docs/compliance.md`](docs/compliance.md) before you
switch sending on. It is not legal advice.

## Documentation

| | |
|---|---|
| [`docs/setup.md`](docs/setup.md) | Full installation, remote access, backups, troubleshooting |
| [`docs/customizing.md`](docs/customizing.md) | Adapting offers, prompts, ICP, sources and languages |
| [`docs/architecture.md`](docs/architecture.md) | What it is, and why it is built this way |
| [`docs/workflows.md`](docs/workflows.md) | Every workflow: inputs, outputs, guards, failure handling |
| [`docs/scoring.md`](docs/scoring.md) | The 100-point rubric |
| [`docs/telegram.md`](docs/telegram.md) · [`docs/telegram-commands.md`](docs/telegram-commands.md) | The human control plane |
| [`docs/mail.md`](docs/mail.md) | Mailbox, DNS (SPF/DKIM/DMARC) and warm-up |
| [`docs/ollama.md`](docs/ollama.md) | Models, context windows, GPU notes |
| [`docs/security.md`](docs/security.md) · [`docs/compliance.md`](docs/compliance.md) | Security posture and legal obligations |
| [`docs/roadmap.md`](docs/roadmap.md) | What is built and what comes next |
| [`postgres/README.md`](postgres/README.md) · [`n8n/README.md`](n8n/README.md) | Schema, migrations, workflow versioning |

## Repository layout

```
├── docker-compose.yml     PostgreSQL, n8n, Caddy - pinned, healthchecked, loopback-only
├── .env.example           every setting, documented; safe defaults
├── Makefile               make help
├── agents/                per-agent contract (JSON Schema) + offers.json
├── prompts/               the prompts, read at run time
├── n8n/workflows/         exported workflow JSON (source of truth)
├── postgres/              migrations (checksummed), seeds, SQL tests
├── infra/                 bootstrap, migrate, deploy, backup drill, Ollama Modelfiles
├── scripts/               healthcheck, backup
└── docs/
```

## Day to day

```bash
make ps / logs / health      # status
make backup                  # GPG-encrypted dump (cron it)
make restore-drill           # prove the newest backup restores
make migrate-status          # applied vs pending
make env-upgrade             # what in .env is out of date after an upgrade
make deploy                  # pull, back up, migrate, import workflows, restart, health
```

## Contributing

Issues and pull requests are welcome. Start with
[CONTRIBUTING.md](CONTRIBUTING.md). Report security problems privately, as
described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). Built and run in production by [FoldNine](https://foldnine.dev).
