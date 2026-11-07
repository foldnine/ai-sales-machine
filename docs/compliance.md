# Responsible use and compliance

This system finds companies, collects business contact details from public
sources and sends them unsolicited email. That is legal in many places for
business-to-business contact, under conditions, and illegal in others. **You,
the operator, are the sender and the data controller.** The software makes the
obligations easier to meet; it does not meet them for you.

> **Not legal advice.** This page summarises commonly cited rules as of late
> 2026 so you know what to ask about. Laws differ by country, change, and
> depend on facts this page cannot know. Check with a lawyer or your national
> regulator before you send.

## The rules, by region

| Region | Basis for B2B cold email | What it requires |
|---|---|---|
| **EU (GDPR)** | Legitimate interest (Art. 6(1)(f); recital 47 names direct marketing as a possible one) | A written **Legitimate Interest Assessment** done *before* you send; telling people where you got their data (Art. 14); an unconditional right to object; data minimisation; erasure on request |
| **EU (ePrivacy / national law)** | Varies by member state | Some countries require prior consent even between businesses. Germany (UWG §7) is the best-known strict case; check each country you write to, including whether a personal work address (`jane@`) is treated differently from a general one (`info@`) |
| **UK (PECR + UK GDPR)** | Corporate subscribers may be emailed without consent | Not sole traders or some partnerships - they are treated as individuals and need consent. Identify yourself and give an opt-out |
| **US (CAN-SPAM)** | No consent needed | Accurate headers and subject line, a valid **physical postal address**, a working opt-out honoured within **10 business days**, and no deceptive content |
| **Canada (CASL)** | No legitimate-interest route | Express or implied consent (e.g. a conspicuously published business address *and* a message relevant to the recipient's role). Narrow - get advice before writing to Canada |
| **Elsewhere** | Check | Australia (Spam Act) and others require consent or an existing relationship |

Two things are true almost everywhere: **every message must truthfully identify
the sender**, and **every message must offer a simple way to stop**.

## What the system enforces

These are built in and on by default. Do not remove them.

- **Suppression in three places.** Discovery skips suppressed domains, WF-06
  checks before every send, and a database trigger on `outreach` rejects any
  message to a suppressed address or domain - so a workflow bug produces a
  failed transaction, not an unwanted email (`docs/security.md`). Entries are
  permanent; there is no removal path in the workflows.
- **Opt-out detection.** WF-08 reads every reply. A stop request ("stop",
  "unsubscribe" and their Serbian equivalents) is recognised in code, not only
  by the classifier, and overrides whatever category the model chose: both the
  replying and the original address are suppressed, every unsent message is
  cancelled, and no confirmation is sent (`docs/inbox-classifier.md`).
- **Bounces suppress.** A hard bounce suppresses the address.
- **Provenance.** Every contact is stored with `source_url` and
  `discovery_method`, so "where did you get my details?" always has an answer
  (`docs/contact-enrichment.md`). Addresses are never guessed blind; only
  addresses published by the company, or derived from a pattern the company's
  own published addresses prove, are used.
- **Human approval.** Every message waits for `/approve` on Telegram.
  Guarded autosend is an opt-in, off by default, behind two switches only the
  operator controls (`docs/outreach-generation.md`).
- **Volume limits.** `OUTREACH_DAILY_LIMIT` (default 5), one message per domain
  (`OUTREACH_PER_DOMAIN_LIMIT`), working hours and days only, and
  `OUTREACH_PAUSED=true` as a single stop button - the default.
- **Plain text, no tracking.** No tracking pixel, no link rewriting, no HTML.
- **Polite crawling.** Research and enrichment honour `robots.txt`, requests to one domain are
  spaced out (`RESEARCH_DOMAIN_COOLDOWN_MINUTES`), and every request carries
  `BOT_USER_AGENT` so a site owner can see who is reading.
- **Minimal personal data.** A person is a name, a job title and seniority, a
  business address with its status and source, and optionally a LinkedIn URL
  (`0003_people.sql`). The research agent separates facts from inferences and
  is told never to invent.

## What you are responsible for

- **Your legal basis.** Write the Legitimate Interest Assessment (or get
  consent where that is the rule) for each country and segment you target.
  Keep it.
- **Your identity in every message.** `prompts/signature.md` ships with a
  placeholder. Put in your real name, registered business name and postal
  address where required.
- **Choosing who to write to.** Configure `DISCOVERY_OSM_COUNTRIES`,
  `OUTREACH_LANGUAGES` and the ICP segments (`docs/customizing.md`) so the
  pipeline only reaches countries where you know the rules. Leave out
  consumers, sole traders where they count as individuals, and any country
  where B2B cold email needs consent you do not have.
- **The privacy notice.** Have one on your website that explains this
  processing, and link it if asked. GDPR Art. 14 requires informing people of
  the source of their data, at the latest in the first message.
- **Requests.** Answer access and erasure requests. For erasure: delete the
  person's rows and add a suppression entry, so the pipeline does not
  rediscover them:

  ```sql
  INSERT INTO suppression_list (email, reason) VALUES ('<address>', 'requested_stop');
  ```

- **Retention.** Decide how long you keep data on companies that never
  answered, and delete it on that schedule.
- **Data sources' terms.** Check the terms of every source you add. GitHub's
  Acceptable Use Policies forbid using its data for unsolicited email, which is
  why commit-author enrichment is off by default (`ENRICH_GITHUB_ENABLED=false`).
- **Deliverability.** SPF, DKIM and DMARC on your sending domain, and a slow
  warm-up (`docs/mail.md`). Mailbox providers will block a sender with a high
  complaint rate whatever the law says.
- **Reading what goes out.** If you turn on autosend, read the daily report of
  what it sent.

## What this project will not add

Features whose main use is evading the controls above will not be merged:
tracking pixels, rotating sending domains or mailboxes to get past provider
limits, scraping personal social profiles, guessing addresses the company has
not published, or removing the suppression trigger.
