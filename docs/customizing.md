# Customizing for your business

Out of the box the pipeline is configured for the business it was built for: a
small consultancy selling **infrastructure work** (audits, DevOps, SRE) to
software companies, and **business process automation** to small businesses in
the Western Balkans. Everything that makes it that business, rather than yours,
lives in a handful of files and two database tables. This page lists them in the
order you should change them.

**Nothing is sent until you set `OUTREACH_PAUSED=false`.** Change everything on
this page first, run the pipeline paused, and read the drafts it produces on
Telegram before you unpause.

## 1. Who you are: `prompts/signature.md`

The greeting and signature are not written by the model; WF-05 assembles them
from this file and appends them to every draft, so the text a human approves is
the text that is sent. Replace the placeholder name with yours and add what the
law where you send requires - typically your registered business name and a
postal address (`docs/compliance.md`). Keep the opt-out line.

`{first_name}`, `{tagline}` and `{url}` are filled in by code. `{tagline}` and
`{url}` come from the offer line in `agents/offers.json`.

## 2. What you sell: `agents/offers.json`

The offer catalogue, read at run time by WF-04 (scoring) and WF-05 (drafting).

- **`lines`** - the business lines. Each has a `tagline` (and `tagline_sr`) and
  a `url` used in the signature, and a `default_offer`. Replace
  `Your Company` and `example.com`.
- **`offers`** - each offer's `code`, `line`, `name`, `use_when` (what the model
  reads when choosing it) and `price`. The price is what
  `prompts/conversation.md` may quote, and nothing else.

`make validate` runs `infra/scripts/check-offers.py`, which fails when the
catalogue, the agent schemas, the `leads.recommended_offer` constraint and the
prompts' offer tables disagree. Changing a price or a name is a file edit.
**Adding or renaming an offer code or a line** also needs a new migration for
the constraints that name them (`leads.recommended_offer`, `icp_segments.line`,
`campaigns.offer`) and the `enum` lists in `agents/*/schema.json`; the check
tells you which ones it found out of step.

## 3. What the agents are told: `prompts/`

Each prompt is read at run time; a change takes effect on the next run. The
parts that describe the sender's business, its offers and its tone are marked
`CUSTOMIZE`. Edit those, and leave the rest - the output contracts, the
"never invent" rules and the banned-phrase lists - alone unless you also change
the code that checks them.

| File | Agent | What to adapt |
|---|---|---|
| `prompts/research.md` | research (WF-02) | What the business sells, so research looks for evidence that matters to it |
| `prompts/scoring.md` | scoring (WF-04) | The rubric (`docs/scoring.md`): which signals count and how much |
| `prompts/outreach.md` | outreach (WF-05) | The voice, the offer per line, the language sections |
| `prompts/reply-draft.md` | reply drafts (WF-08) | The facts about the offer a reply may use, the links to send |
| `prompts/conversation.md` | conversation (WF-09, not built) | Prices and terms it may state, and when to hand over |

The limits that matter are checked twice, in the prompt and in the workflow
after the model returns (`docs/architecture.md`). If you change a limit in a
prompt - the 120-word ceiling, the one-question rule - change the check in the
workflow too, or the prompt and the check disagree and the check wins.

## 4. Who you target: `icp_segments`

ICP segments are rows, not code (`0024_icp_segments.sql`,
`0025_segment_allocation.sql`). Each segment has:

| Column | Meaning |
|---|---|
| `code`, `name` | Identifier and label |
| `line` | Which offer line it belongs to (`infrastructure` or `automation`) |
| `active` | Inactive segments are still scored, but use `OUTREACH_MIN_SCORE` |
| `min_score` | The score a company in this segment must reach for a first message |
| `sources` | Discovery sources that feed it (`radar_yc`, `radar_hn`, `radar_osm`, `radar_minimax`, ...) |
| `industry_like` | Optional `LIKE` patterns on `companies.industry`, e.g. `OSM shop=%` |
| `priority` | Lower wins when a company matches more than one |
| `angle` | The segment's offer, handed to the outreach model. `NULL` keeps the line's prompt unchanged |
| `discovery_share` | Percentage of `DISCOVERY_DAILY_LIMIT` reserved for this segment each day. Slots it cannot fill go to the others |

The shipped segments are `infra_startups`, `webshops`, `accounting_offices`,
`logistics`, `agencies` and an inactive control, `regional_other`. Their
`angle` texts describe Balkan small businesses (e-invoicing through SEF,
Minimax bookkeeping). Change them with a new migration rather than by hand, so
a fresh install and yours agree:

```sql
-- postgres/migrations/0031_my_segments.sql
UPDATE icp_segments SET active = false WHERE code IN ('accounting_offices', 'logistics');
UPDATE icp_segments SET angle = '...your offer for webshops...', discovery_share = 50
WHERE code = 'webshops';
```

Then `make backup && make migrate`.

## 5. Where companies come from: discovery

WF-01 reads free public sources - no data provider, no API key
(`docs/lead-discovery.md`):

| Source | Feeds | Configured by |
|---|---|---|
| Y Combinator company directory | `radar_yc` | `DISCOVERY_MIN_TEAM_SIZE`, `DISCOVERY_MAX_TEAM_SIZE`, `DISCOVERY_MAX_BATCH_AGE_YEARS` |
| Hacker News "Who is hiring?" | `radar_hn` | always on |
| OpenStreetMap businesses with a website | `radar_osm` | `DISCOVERY_OSM_COUNTRIES` (ISO codes, empty switches it off), `DISCOVERY_OSM_MAX_LOCATIONS` (chain filter), `make osm-refresh` |
| Minimax's directory of accounting offices (SI, RS, HR) | `radar_minimax` | `make minimax-refresh` |

`DISCOVERY_DAILY_LIMIT` is the throttle on the whole pipeline: set it to what
your research model can actually read in a day, not more.

Every request the crawlers make carries `BOT_USER_AGENT`. Set it to something
that identifies you and gives a contact URL, e.g.
`MyCompanyBot/1.0 (+https://example.com/bot)`, so a site owner can tell who is
reading their pages. `robots.txt` is honoured regardless.

## 6. Which language: `OUTREACH_LANGUAGES`

A comma-separated `COUNTRY:language` map, e.g. `RS:sr,HR:sr`. Every country not
listed is written in English; empty or `none` means English everywhere. A
language needs its own greeting and signature sections in
`prompts/signature.md` and its own section in `prompts/outreach.md` - only `sr`
(Serbian/Croatian/Bosnian, Latin script) ships with them. Leads in a non-English
language are drafted by `OUTREACH_NIGHT_MODEL` in the night window
(`docs/outreach-generation.md`).

## 7. Before you unpause

- [ ] No `Your Company`, `Your Name` or `example.com` left in
      `prompts/signature.md`, `agents/offers.json` and the prompts
      (`grep -rn -e 'Your Company' -e 'Your Name' -e example.com prompts agents`)
- [ ] `make validate` passes
- [ ] Your own domain and current clients are in `suppression_list`
- [ ] The mailbox is set up and warmed up (`docs/mail.md`)
- [ ] You have read `docs/compliance.md` and checked the rules for the
      countries you write to
- [ ] You have read at least one full batch of drafts on Telegram
- [ ] `OUTREACH_DAILY_LIMIT` is low (5 is the default)
