# Security

This system holds an API key that costs money, a mailbox that can send on your
behalf, and personal data about people who never asked to be in it. All three
deserve more care than a side project usually gets.

## Secrets

**Never commit a secret.** `.env` is gitignored, `.env.example` contains only
empty values, and `make secrets-scan` fails the build if anything
credential-shaped appears in a tracked file. Run it before every commit.

**Every secret comes from `.env`.** Nothing is hardcoded in
`docker-compose.yml`, the SQL, the prompts or the workflows. The compose file
uses `${VAR:?message}` for required values, so a missing secret fails at start
with a clear message instead of silently defaulting.

**`.env` is chmod 600.** `make init` sets it; `make health` warns if it drifts.

**`N8N_ENCRYPTION_KEY` is the master key.** Every credential stored in n8n is
encrypted with it. Back it up separately from the database dumps, because a
dump plus the key in the same place is the same as no encryption. Rotating it
invalidates every stored credential.

**Credentials belong in n8n's credential store,** not in workflow node
parameters and not in environment variables read by expressions. n8n encrypts
the credential store; exported workflow JSON does not contain credential values,
which is what makes `n8n/workflows/` safe to commit.

**API keys must never reach a log.** Do not log full request objects. WF-99
alert text is built from specific fields, never from a whole error payload -
provider errors routinely echo the request headers back.

## Network exposure

| Service | Binding | Public |
|---|---|---|
| PostgreSQL | `127.0.0.1:5432` | Never |
| Ollama | `*:11434` on the host | Never through Caddy |
| n8n | `127.0.0.1:5678` | Never |
| Caddy | `${CADDY_BIND_ADDR:-127.0.0.1}:80,443` | Never |
| `tailscale serve` | tailnet only, HTTPS | Only to your own devices |

**Ollama runs on the host and binds every interface,** which is how the n8n
container reaches it and also means the local network can. On a home network
behind NAT that is usually acceptable; elsewhere bind it to the Docker bridge
address instead. See `docs/ollama.md`.

**Ollama has no authentication of any kind.** Anyone who can reach port 11434
can use the model, read what is sent to it, and consume the machine's CPU. It
must never be published beyond loopback.

**Note on Docker and host firewalls:** published ports are inserted into the
`DOCKER` chain, which is evaluated before the host firewall's input rules on
Linux. A `ufw deny` will not close a published Docker port. This is why the
bindings above are explicit loopback addresses rather than a firewall rule.

**n8n must never be exposed to the internet.** It stores credentials and can
execute arbitrary code, and its only authentication is the owner account: the
`N8N_BASIC_AUTH_*` variables this stack used to set were removed in n8n 1.0 and
did nothing. Keep the image current as well - n8n has had critical remote code
execution advisories since 1.76.

**Nothing in this stack needs inbound traffic.** Telegram is polled, mail is
outbound SMTP/IMAP, and no workflow has a webhook trigger. So the editor is
reached with `tailscale serve` (tailnet-only HTTPS in front of
127.0.0.1:5678), not through a public hostname or a tunnel. If a webhook is ever added, expose that
one path, not the editor.

## Data

The database holds names, job titles, email addresses and notes about people at
companies who did not opt in. Under GDPR this is processing personal data for
direct marketing, which is permitted under legitimate interest for B2B contact
in most of the EU, but carries obligations:

- **An unconditional right to object.** The suppression list is that mechanism,
  and it must work the first time, every time.
- **Every message identifies the sender** and explains how to stop receiving
  them. This is a legal requirement, not a courtesy.
- **Data minimisation.** Store what is needed to decide whether to write and
  what to write. Not more.
- **Erasure on request.** A person asking to be deleted gets deleted, with a
  suppression entry left behind so the pipeline does not rediscover them.

This is a description of the obligations the system is built to meet, not legal
advice. Rules differ by country - some require consent even for B2B email - and
the operator is responsible for their own. `docs/compliance.md` summarises the
rules by region and splits what the system enforces from what the operator must
do.

### Where contact details come from

Accuracy and provenance are the two obligations that a cold outreach pipeline
gets wrong first, so WF-03 records both on every row it writes. Nothing is
stored without `source_url` and `discovery_method`
(`postgres/migrations/0013_enrichment.sql`), which means "where did you get my
details" always has an answer.

| How | Recorded as | Standing |
|---|---|---|
| Published on the company's own site | `published_page` | The company put the address there to be written to. The cleanest footing legitimate interest has. |
| Author metadata of a commit in the company's public repository | `git_commit` | **Weaker.** Published for attribution, not to be written to, and GitHub's Acceptable Use Policies forbid using its data for unsolicited email. Off by default (`ENRICH_GITHUB_ENABLED=false`). |
| Derived from a pattern seen in a published address on the same domain | `pattern_inferred` | An inference, marked as one. Only ever from an address that company itself published. |

**Blind guessing is deliberately not implemented.** Trying `first.last@`,
`f.last@` and the rest against a domain that has never shown one produces more
addresses and no evidence: the address can belong to somebody else, it cannot be
sourced, and it is the case where accuracy and the right to know the origin both
fail at once. `docs/contact-enrichment.md` has the mechanism.

WF-03 only writes addresses on the company's own domain, and never writes a role
address (`hello@`, `jobs@`) as though a person were behind it.

**Role contacts (decided by the operator, 2026-09-24).** When no named person with an
address is found, the company's published general address - `info@`,
`office@`, `kontakt@` and a short allowlist - may be written to, as a nameless
`kind = 'role'` row (`0022_role_contacts.sql`). The footing is the same as for a
published personal address: a small company that publishes only a general
address has published it for business contact. It is recorded as
`published_page` with its `source_url`, so "where did you get this address"
still has an answer. Applicant, support, billing, press, legal, abuse and
no-reply addresses are never used, a named person always takes precedence, and
every draft is still approved by a human. `docs/contact-enrichment.md` has the
lists and the reasons.

## Suppression

The suppression list is the one rule the system enforces in three places:

1. **Discovery** skips suppressed domains, so they never enter the pipeline.
2. **The dispatcher** checks before every send.
3. **A database trigger** on `outreach` rejects the insert outright.

The third one exists because the first two are code, and code has bugs. A
workflow that forgets the check gets a failed transaction, not a sent email.

Additions to the list are permanent. There is no removal path in the workflows
by design; taking someone off requires a deliberate manual action.

## Outreach volume

Rate limits are a security control here, not a politeness setting. A
compromised or misconfigured pipeline that sends a thousand emails destroys the
sending domain permanently, and there is no recovery.

| Control | Variable | Default |
|---|---|---|
| Global pause | `OUTREACH_PAUSED` | `true` |
| Automatic sending (master; then `/autosend on`, `/stop`) | `OUTREACH_AUTOSEND_ENABLED` | `false` |
| Messages per day | `OUTREACH_DAILY_LIMIT` | 20 |
| Messages per domain | `OUTREACH_PER_DOMAIN_LIMIT` | 1 |
| Minimum score to contact | `OUTREACH_MIN_SCORE` | 60 |
| Maximum follow-ups | `OUTREACH_FOLLOWUP_MAX` | 2 |

`OUTREACH_PAUSED` is checked by WF-06 on every run, before anything else. It is
the stop button, and it must stay a single boolean that a person can flip from
their phone without thinking.

Start well below the limits. Twenty a day from a new domain is already
aggressive; five is a better first week.

## Backups

`make backup` writes a compressed `pg_dump` and encrypts it with GPG AES256
using `BACKUP_PASSPHRASE`. Backups are chmod 600 in a chmod 700 directory, and
pruned after `BACKUP_RETENTION_DAYS`.

A database dump contains every prospect's personal data and every conversation.
Treat a backup file exactly like the database:

- Never copy one to cloud storage unencrypted.
- Keep `BACKUP_PASSPHRASE` and `N8N_ENCRYPTION_KEY` somewhere that is not the
  machine being backed up, and not the same place as the backups.
- Test a restore at least once. An untested backup is a belief, not a backup.

## Prompt injection

Research reads pages written by other people, and the classifier reads email
written by strangers. Both are untrusted input reaching a model.

- Treat all fetched content and all inbound email as data, never as
  instructions. The prompts state this; the workflows must not concatenate
  fetched text into a position where it can be read as a directive.
- The agents have no tools. They return JSON that is validated against a schema
  before anything is written. A model that has been talked into something can
  produce a bad row; it cannot execute anything.
- The conversation agent's hard limits are checked in the workflow after the
  model returns, not only in the prompt. A prompt is a request; a check is a
  control.
- Nothing an agent returns is ever used to build SQL, a shell command or a URL
  to fetch.

## Checklist before going live

- [ ] `make secrets-scan` is clean
- [ ] `.env` is chmod 600 and not tracked
- [ ] `N8N_ENCRYPTION_KEY` is backed up off the machine
- [ ] `BACKUP_PASSPHRASE` is set and stored separately
- [ ] A restore has been tested at least once
- [ ] Own domain and current clients are in `suppression_list`
- [ ] n8n is not reachable without TLS and authentication
- [ ] PostgreSQL is on loopback only; Caddy is on loopback; remote access is `tailscale serve` only; Ollama is not reachable from outside the LAN
- [ ] Daily and per-domain limits are set low
- [ ] `OUTREACH_PAUSED=true` until a batch has been read by a human
- [ ] Every outreach template identifies the sender and how to opt out
