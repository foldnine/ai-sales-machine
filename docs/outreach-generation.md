# WF-05 Outreach Generation

Writes the first email for a scored lead and stops at `pending_approval`.
Nothing it produces is sent without a human, with one opt-in exception: while
the operator has guarded autosend on, a first message with no
blocker is approved by the workflow (*Guarded autosend*, below).

Artifact: `n8n/workflows/ai-sales-outreach-generation.json`
Prompt: `prompts/outreach.md` · Schema: `agents/outreach/schema.json`

```
Every Hour
  -> Read Outreach Prompt / Read Outreach Schema / Read Signature / Read Offers
  -> Outreach Window                   (night: regional leads, the 27B model; day: everyone else)
  -> Claim Leads                       (score >= OUTREACH_MIN_SCORE, reachable, not suppressed, no step-1 draft)
  -> Build Outreach Request -> Outreach Agent
  -> Validate And Check -> Usable Response?
       +-- no  -> Retry Once?
       |            +-- yes -> Outreach Agent Retry -> Validate And Check (again)
       |            +-- no  -> Close Run Error
       +-- yes -> Passed Checks?
                    +-- yes -> Queue For Approval        (outreach + lead to pending_approval)
                    |            +-> Autosend Check      (second branch: approve a clean first message
                    |                  |                  while autosend is on; pass on the rest)
                    |                  +-> Queue Draft Alert   (the approval message, + why autosend held it)
                    +-- no  -> Store Blocked Or Skipped  (draft kept with the reason, or lead to nurture)
```

## Serbian at night, English by day

A company whose country `OUTREACH_LANGUAGES` maps to a language with a block
in `prompts/outreach.md` (RS, HR, BA and ME to Serbian) is a *regional* lead.
Its first message is written in that language by `OUTREACH_NIGHT_MODEL`
(`qwen3.6:27b`), and only between `OUTREACH_NIGHT_HOUR_START` and
`OUTREACH_NIGHT_HOUR_END` (01:00-04:59 in `GENERIC_TIMEZONE`). Every other lead
is written in English by `OLLAMA_OUTREACH_MODEL` outside that window.
`Outreach Window` decides which half of the day a run is in; the claim takes
only the leads that belong to it.

Why the split, measured on 2026-09-24 with the real Build and Validate code fed
straight to Ollama:

- The 9B model's Serbian had grammar errors in every draft. The 27B model's is
  mostly natural, and it declined to write to one company for want of evidence,
  which is the right call. Its slips ("ruche", a Croatian "sinkronizaciju",
  anglicisms) are what the approval step is for: the operator reads Serbian.
- The 27B (17 GB) and the 9B (6.6 GB) do not fit in 24 GB together, so Ollama
  swaps them, and the day belongs to the 9B: research runs back to back. The
  first 27B draft waited 20 minutes for its turn; the second took 57 seconds.
- Research, enrichment and scoring are on schedules around the clock, so the
  night is not idle by itself. Each night run opens its `agent_runs` rows with
  `input.window = 'night'`, and while one is open `night_drafting()`
  (`0023_night_drafting.sql`) is true: WF-02, WF-03 and WF-04 claim nothing,
  the batches already going finish, and the 27B loads once for the whole
  batch (`OUTREACH_NIGHT_BATCH_SIZE`, 20). The flag stops counting a run after
  an hour, so one that died cannot hold the pipeline until morning.
- A night run does not claim while another night batch is open, so a long
  batch is not claimed over by the next hour's run.

With `OUTREACH_LANGUAGES` empty (or `none`) nothing is regional: every lead is
English and written by day, and the night runs claim nothing.

## Follow-ups

A lead that got a message and has not answered gets up to
`OUTREACH_FOLLOWUP_MAX` (2) follow-ups, each `OUTREACH_FOLLOWUP_DELAY_DAYS` (4)
after the previous one was **sent**. They were specified in
`prompts/outreach.md` from the start and never built; by 2026-09-24 four first
messages had gone out and none would ever have had a second.

They go through this workflow rather than a new one, so they get everything a
first message has: the window, the retry, every check, the envelope and the
Telegram approval. `Claim Leads` takes a lead at `contacted` whose last sent
step is due, whose next step has no row yet, and whose threads hold no inbound
message; any reply also moves the lead out of `contacted` (WF-08). Follow-ups
are claimed before first messages.

| | First message | Follow-up |
|---|---|---|
| Written | by day on the 9B (English), at night on the 27B (regional) | **at night on the 27B**, in the lead's language |
| Subject | the model's | `Re: ` + the first subject, set in code |
| Body ceiling | 120 words | 90 (the prompt asks for 70) |
| Below the signature | nothing | the previous message, quoted (`On <date> I wrote:` / `<datum>. sam napisao:`) |
| Extra checks | | no chasing ("did you see my last email"), no run of eight words from an earlier message |

All follow-ups are written at night because the 9B model's could not follow
the one rule that matters: on 2026-09-24 both of its test follow-ups reused
"I run bounded improvement sprints to fix exactly that" from the first message,
and one opened with its own "Hi Aleksey," above the one the workflow adds. The
27B's built on a fact the first message had not used (Terraform drift, the CDC
runtime) and passed, in English and in Serbian.

The subject and the quote are code for the same reason the greeting is: the
send carries no `In-Reply-To` header (`emailSend` has no option for one), so
"Re:" and the quoted text are what tell the recipient what this answers.

A follow-up that is blocked or rejected occupies its step, so it is never
rewritten; one the model declines (`send: false`) moves the lead to `nurture`.
`/reject` on a follow-up rejects the lead, like on a first message. After the
last follow-up the lead stays at `contacted` and nothing more is claimed.

WF-06 sends a follow-up like any approved row, inside the same daily and
per-domain limits.

## One retry on invalid JSON

The 27B model broke the JSON syntax in one of two drafts on 2026-09-24 - a
missing quote in `subject` - with strict `response_format`. That is a failure
of the transport, not a judgement, so it is the one failure asked again.

A response that does not parse is marked `retry` on its first attempt, and
`Retry Once?` sends **the same request** once more through `Outreach Agent
Retry`, whose answer goes back through `Validate And Check` and is judged
exactly like the first. Nothing is repaired: a response is either valid JSON
as the model wrote it or it is not. A second failure closes the run with
`Outreach validation failed after one retry`, and the lead is tried again next
hour as before. Any other error - a failed request, a truncated answer, a
missing `send` - is not retried here.

`Validate And Check` therefore runs twice in such an execution, the second
time on the retried requests only, so it finds each request and claim by
paired item and tells the attempts apart by `$prevNode`. The run's output
records `attempt`, and a draft from the second attempt carries a note with the
first attempt's error. Checked in a throwaway n8n 1.123.81 container: pairing,
`$prevNode` and the downstream `$('Validate And Check').item` all resolve to
the right item on the second pass.

## The approval message

A queued draft also queues the notification `docs/telegram.md` specifies, with
the hook and its source **above** the email body - the one thing worth checking
is whether the claim is true, and that takes five seconds when the link is at the
top - and the whole body, because an approval on a summary is not an approval.

Everything except the hook is read back out of `v_approval_queue`, so the message
describes the row that was actually written rather than what the workflow
believes it wrote. If the draft is not there at `pending_approval`, the query
returns no rows and nothing is queued: a refused write, not a silent success.

It hangs off `Queue For Approval` as a **second branch**. `Close Run Success`
resolves `$('Validate And Check').item` by paired item, and inserting a node into
that chain would break the lineage. The audit trail must not depend on a
notification succeeding.

`docs/notifications.md` has the delivery half.

## The greeting and the signature are not the model's

`prompts/outreach.md` asks for a body and nothing else, and until now that is
literally what was stored: no greeting, no sender, no way for a recipient to
say stop. A message like that identifies nobody, which is both the opposite of
looking like a business and the thing European commercial email is required to
do - `docs/security.md` rests the legitimate-interest basis on the sender being
identifiable.

Both now come from `prompts/signature.md`, read from disk on every run exactly
as the prompt and the schema are, and are applied in `Validate And Check`:

```
Hi {first_name},        <- greeting, the one placeholder, from people.full_name
                           (a role contact gets "Hello," / "Poštovani," instead)

<the model's body>

--                      <- signature, verbatim from the file
```

Three decisions worth keeping:

**The model does not write them.** A greeting is a fact about the recipient the
system already has, and a signature is a claim about the sender. A model given
a field nothing checks invents one - `A schema value in the prose` below is the
same failure in a different field.

**They are applied before the draft is stored, not at send time.** The approval
message says an approval on a summary is not an approval; approving a body and
sending a body plus a signature nobody read would be the same defect.

**A role contact is greeted without a name.** A lead on the company's general
address (`kind = 'role'`, `docs/contact-enrichment.md`) has no name, and none is
made up: the greeting is `## Greeting (role)` or `## Greeting (role, sr)` from
`prompts/signature.md`, the brief tells the model in as many words that there is
no named recipient, and both system prompts in `prompts/outreach.md` forbid
inventing one. A role draft whose body opens with a greeting of its own is
blocked, since that greeting can only be to somebody the model made up. The
"no first name to greet" block still applies to a person.

**The checks still run on the model's body alone.** The signature is forty words
and carries its own question mark, so counting it would spend a third of the
120-word ceiling on boilerplate and trip the one-question rule on every draft.
Measured on a real draft: 33 words as written, 52 with the envelope.

The opt-out line is an obligation rather than a formality. WF-08 does not exist,
so nothing reads replies, and a "stop" has to be honoured by hand with a row in
`suppression_list` - after which the trigger on `outreach` refuses that address
for good.

## The checks are mechanical

`prompts/outreach.md` has a list of hard rules and a longer list of phrases that
must never appear. `docs/workflows.md` names the checks as WF-05's job. They are
enforced in code, not requested in a prompt, and a draft that fails one is
**stored, not fixed**.

| Check | Blocks the draft when |
|---|---|
| Word ceiling | The body is over 120 words. Counted from the body, not taken from `word_count` |
| Banned phrases | "reaching out", "circling back", "hope this finds you well", "companies like yours", "leverage", "synergy" and the rest of the NEVER WRITE list |
| Calendar link | calendly, cal.com, savvycal, hubspot meetings, "book a call" |
| Emoji | Any emoji in the body or subject |
| One question | More than one `?` in the body |
| Hook is checkable | `hook_source` is empty, or is not one of the URLs the research actually found |
| Offer | Outside the three in the schema |
| Subject | Contains the recipient's first name |
| No name, no greeting | A role-contact draft whose body opens with a greeting ("Hi Marko,", "Poštovani") |
| Greeting twice | Any draft whose body opens with a greeting: the workflow adds one, so it would be sent twice |

Notes that do not block: a subject outside four to seven words, a body with no
question at all, a `word_count` that disagrees with the body, and an offer that
differs from the one scoring recommended.

**`hook_source` is the important one.** It exists so a human approving the draft
can check the single claim the message rests on in five seconds. The known
sources are assembled from the research run's `analysis.sources` and every
`signals.source_url` for that company. A hook pointing anywhere else cannot be
verified, which defeats the field, so it is blocked.

Nothing is edited to comply. A blocked draft is one a human can read and learn
from; a quietly corrected one teaches nobody anything.

### A schema value in the prose

The agent picks `recommended_service` from an enum, and one draft came back
reading "I run a bounded devops_improvement_sprint": the identifier itself,
inside the sentence, in a message addressed to a person. It passed every check
there was, because none of them looked for it.

Any snake_case token in the subject or body now blocks the draft. Nobody writes
an underscore in an email, so such a token is the model quoting its own schema
back at the reader. `docs/company-research.md` records the same failure in the
research agent, where `why_now` came back as
`active_hiring_for_infrastructure_fixes` instead of a sentence, so this is a
habit of the local models rather than a one-off.

## Three outcomes

| Outcome | `outreach` | `leads` | Run |
|---|---|---|---|
| `queued` | `pending_approval` | `pending_approval` | success |
| `blocked` | `draft` with `rejection_reason` | unchanged | success |
| `not_sending` | nothing | `nurture` | success |
| model error | nothing | unchanged, retried next hour | error |

Invalid JSON is asked once more in the same execution before it counts as a
model error (*One retry on invalid JSON*).

`send: false` is a legitimate answer, not a failure - `prompts/outreach.md` says
sending nothing is always acceptable. The lead moves to `nurture` so it leaves
the queue instead of being regenerated every hour.

A blocked draft leaves the lead at `new`, but the unique index on
`(lead_id, sequence_step)` means the next pass updates that draft rather than
adding another.

## The recipient has to have an address

The claim query requires one: `p.email IS NOT NULL` and an `email_status` of
`valid`, `catch_all` or `guessed` - the same three the schema's
`people_contactable_idx` already calls contactable.

WF-04 checks this before it creates a lead, which looked like enough. It is not,
because the address can go away afterwards and the lead stays. Measured on
one company: WF-03 derived `pieter.berg@` for the chief executive at 06:00,
WF-04 created the lead on it at 06:15 and scored the decision maker 7 for an
address it called `guessed`, the address was withdrawn at 07:26 because his
surname is "van der Berg" and no observed address on that domain proved the
form, and at 08:00 WF-05 wrote a draft for a lead with no recipient and queued
it for approval. A bounce clearing an address would do the same thing.

Nothing caught it downstream. `is_suppressed(NULL)` is false, so the claim's
suppression check passed; `outreach` stores no recipient column, so the trigger
had nothing to compare; and the approval message reads the row back out of
`v_approval_queue`, which shows the empty address rather than refusing.

## Suppression is enforced twice

The claim query skips suppressed recipients so they never cost a model call.
The `outreach_enforce_suppression` trigger on the table rejects the insert
outright if the workflow ever slips. Verified: inserting a draft for a
suppressed address raises `outreach blocked: <email> is on the suppression
list`.

## The worked example is left out of the prompt

`prompts/outreach.md` ends with a full example email. It is deliberately not
sent to the model: a local model copies an example rather than learning from it.
The system prompt, the structure, the subject-line rules and the offer table are
sent; everything from `## Example` onward is not.

## Running it

Schedule, hourly, once activated. By hand: open it and click **Test workflow**.

It needs a lead at `status = 'new'` with `score >= OUTREACH_MIN_SCORE`
(currently 60), which means a person, which means WF-03 - or a person inserted by
hand, which is what `docs/workflows.md` expects at this stage.

## Measured

Full chain on one company, all local, all free:

| Step | Model | Time |
|---|---|---|
| WF-02 triage | `llama3.1:8b` | 9s |
| WF-02 research | `qwen9-64k` | 135s |
| WF-04 scoring | `qwen9-64k` | 19s |
| WF-05 outreach | `qwen9-64k` | 15s |

Scored 93, band `HOT`, and the draft passed every check. What it wrote:

```
Subject: 45-minute builds blocking daily deploys

Your GitLab CI pipeline takes 45 minutes per the blog post on your site.

That latency forces a twice-a-week release cadence instead of daily. It also
means engineers are likely skipping safety checks or forgetting manual steps
during releases, as seen in recent incidents.

I can run an infrastructure audit to map where those build minutes go and
identify which Terraform modules need refactoring for EKS migration.

Is this a priority right now?
```

73 words, one question, hook sourced to the blog post it came from. That is a
draft worth reading, from a model that costs nothing to run.

The judgement to watch is "engineers are likely skipping safety checks" - an
inference, flagged as one by "likely", and sourced to the incidents the blog
actually describes. The line between that and an invented claim is exactly what
the human approval step is for.

## Guarded autosend

An opt-in, off by default: first messages go out without per-message
approval until the operator says stop. Built in `0030_autosend.sql`; the phase 14
preconditions it skipped are written down in `docs/roadmap.md`.

**Two switches, both the operator's.** `OUTREACH_AUTOSEND_ENABLED` in `.env` is the
master: anything but the exact string `true` and nothing is ever approved by
the machine. `app_settings` `autosend` is the runtime switch, flipped on
Telegram (`docs/telegram-commands.md`): `/autosend on` (refused while the
master is off), `/autosend off`, `/stop`, and `/autosend` for the state. A coding
agent flips neither (`CLAUDE.md`).

**What happens to a draft.** `Autosend Check` runs on the second branch after
`Queue For Approval` and calls `autosend_decide()`. With both switches on and
`autosend_blockers()` empty, the draft becomes `approved`, `approved_by =
'autosend'`, the lead `approved`, exactly as `/approve` leaves them, and no
approval message is sent. Anything else comes out of the node and reaches
`Queue Draft Alert` as before; with autosend on, the message ends with one line,
`Autosend held it: <reasons>`. Every decision is a row in
`autosend_decisions`. A failure inside the checks holds the draft; it never
loses one.

**What holds a draft** (`autosend_blockers()`, each reason `kind: detail`):

| Kind | When |
|---|---|
| `follow-up` | `sequence_step` is not 1. Follow-ups always wait for `/approve`: a reply read in a mail client while WF-08 was down is never recorded, and the lead still looks unanswered |
| `status`, `channel`, `text` | Not at `pending_approval`, not email, or no message between the greeting and the signature |
| `cyrillic` | Any letter in U+0400-U+04FF in the subject or body; every outreach language is Latin |
| `phrase` | A pattern in `app_settings` `autosend_deny_patterns` (JSON array of regular expressions, case-insensitive), seeded with "Ponudim", "Ponudite", the 27B's slips ("ruche", "sinkronizacij"), a hypothesis stated as fact ("you type", "vaš tim troši"), the worst of the NEVER WRITE list, and template leftovers (`{first_name}`, `undefined`) |
| `greeting` | The greeting is not one WF-05 writes, addresses a role or title ("Poštovani direktore", "Dear CEO", "Hi Sales Team"), greets a named contact without a name, or names somebody at a general address |
| `recipient`, `suppressed`, `bounced` | No contactable address; the address or domain on `suppression_list`; any earlier bounce on that domain or company |
| `lead`, `conversation` | The lead is past `contacted`, has a thread, or was already written to; anybody at the same brand has written to us, was written to, or is at a sales stage or rejected |
| `company`, `size` | Company status ignored/suppressed/won/lost; more than 50 employees; the research or description reads as a national, chain or multinational firm (there is no size flag on `companies`; the research is the evidence) |
| `segment` | The company is in no ICP segment or its segment is not active |
| `language` | `OUTREACH_LANGUAGES` gives the country another language than the draft was written for, or the text reads as another language (function words; "unclear" also holds) |
| `boilerplate` | A sentence of eight words or more that another company's email of the last 60 days already has |

The deny list is data: `UPDATE app_settings SET value = value ||
'["\\mnovi izraz\\M"]' WHERE key = 'autosend_deny_patterns';` and the next draft
uses it. A pattern that is not a valid regular expression holds every draft
until it is fixed.

**What does not change.** WF-06 sends an autosent row like any approved one:
within `OUTREACH_DAILY_LIMIT`, the per-domain limit and working hours, and not
at all while `OUTREACH_PAUSED` is not `false`. The daily report lists every
message autosend approved and sent in the last 24 hours, by lead id, company
and subject, so a human reads each one after the fact.

**`/stop`** turns the runtime switch off and puts every draft autosend approved
and WF-06 has not claimed back to `pending_approval` (a recipient suppressed
meanwhile is cancelled instead). A row already `queued` is in flight and cannot
be recalled.

## Not implemented

The daily send limit, the per-domain limit and the working-hours window are
WF-06's job, not this one. `OUTREACH_PAUSED` is not read here: nothing in this
workflow sends anything. `OUTREACH_AUTOSEND_ENABLED` is read only by
`Autosend Check`, which can approve, never send.
