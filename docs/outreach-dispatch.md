# WF-06 Outreach Dispatch

The only workflow that sends anything.

Artifact: `n8n/workflows/ai-sales-outreach-dispatch.json`

```
Every 15 Minutes
  -> Claim Approved Outreach       (every guard; approved -> queued)
  -> Send Email                    (SMTP)
       +-- ok    -> Record Send            (outreach, conversation, message, lead)
       |             -> Dispatch Result
       +-- error -> Record Send Failure    (outreach -> failed, alert, no retry)
                     -> Dispatch Failure Result
```

It takes rows a human already approved and does not know or care how the
approval happened. That is what makes turning on automation later a change to
whatever sets `approved`, rather than a change here.

## Every guard is in the claim

The five guards `docs/workflows.md` specifies are all in the `WHERE` clause of
the claiming statement, in the order that document lists them, rather than in IF
nodes after it.

The reason is what a guard can still do once a row has been claimed: nothing but
refuse it. A refusal downstream leaves the row moved out of `approved` and
needing a human to put it back. A guard in the `WHERE` clause never claims the
row in the first place, so a closed window or a paused system is indistinguishable
from an idle one — the workflow runs, claims nothing, and ends.

| Guard | How |
|---|---|
| `OUTREACH_PAUSED` | Read first. Anything but the exact string `false` leaves it paused, so a typo stops sending rather than starting it. |
| Suppression | `NOT is_suppressed(pe.email)`, plus the trigger on `outreach` as the backstop. |
| Daily limit | `OUTREACH_DAILY_LIMIT` minus what today already spent. |
| Per-domain limit | Counted for today, then at most one row per domain per run. |
| Working hours | `OUTREACH_WORKING_*`, evaluated in `GENERIC_TIMEZONE`. |

**`queued` counts against the daily limit as well as `sent`.** A row in flight is
going to become sent, and counting it only once it has overshoots the limit by a
whole batch on every run.

**The window is evaluated in the configured timezone, not the server's.** The
schedule trigger cannot do this — it has no access to `GENERIC_TIMEZONE` — which
is why a 15-minute trigger runs around the clock and the claim decides.

**At most one message per domain per run.** The per-domain subquery counts what
is already sent or queued, and cannot see a sibling being claimed in the same
statement, so two messages to one company would both pass it. `DISTINCT ON
(domain)` closes that. At the default limit of 1 it is exact; above that it
under-sends and the next run 15 minutes later catches up, which is the side to
err on.

## Claiming moves the row to `queued`

`approved` to `queued` happens inside the claiming statement, under
`FOR UPDATE ... SKIP LOCKED`, so two runs cannot take the same row.

**A row stranded at `queued` is not reclaimed automatically.** If n8n dies
between the claim and the send, that row stays `queued` until a human looks at
it. This is deliberate: the workflow cannot tell a message that was never sent
from one that was sent by a process that died before it could say so, and of
those two mistakes a duplicate cold email to a prospect is much worse than a
delayed one.

## Sending

The `Send Email` node uses the n8n SMTP credential, not `SMTP_*` from `.env`.
Only the envelope — `EMAIL_FROM`, `EMAIL_FROM_NAME`, `EMAIL_REPLY_TO` — comes
from the environment. See `docs/mail.md` for the mailbox itself.

**`appendAttribution` is `false` and must stay that way.** Left at its default,
the node appends an advertisement for n8n to the bottom of every message. The
body a human approved would not be the body that was sent, which is the same
defect `docs/outreach-generation.md` rejects when it applies the signature before
the draft is stored rather than at send time.

## What a send writes

One transaction, four writes, each guarded on the state the claim left behind so
that replaying it cannot send twice or double-write a thread:

| Table | Write |
|---|---|
| `outreach` | `sent`, `sent_at`, `provider_message_id`; only `WHERE status = 'queued'` |
| `conversations` | The thread, at `awaiting_reply`, keyed on the Message-ID |
| `messages` | The outbound message, `direction = 'outbound'`, `author = 'agent'` |
| `leads` | `contacted` |

The `messages` row is not in the specification in `docs/workflows.md`, which
mentions only the conversation. It is written anyway, because WF-08 has to match
a reply to a thread and `conversations.external_thread_id` alone gives it a key
with nothing on the other end of it.

**Threading depends on the Message-ID surviving submission.** The id recorded is
the one the SMTP library reported, which is the one that was submitted. If a
provider rewrites it in transit, the reply carries an id this row does not have,
and WF-08 will need to fall back to `In-Reply-To` and `References` rather than
trusting this key alone. That is a note for WF-08, not a defect here.

## A failed send is parked, never retried

An SMTP error routes to the second output of the send node — the batch is not
aborted, so one bad recipient does not stop the other four.

The row goes to `failed` with the provider's error text, and a `system`
notification at `immediate` priority goes into the outbox with a dedup key per
outreach row.

Nothing is retried. An SMTP error can arrive after the message was in fact
accepted, so an automatic retry is how one rejected message becomes two delivered
ones. The lead is deliberately not touched either: the claim moved the outreach
row and nothing else, so the lead is still where the approval left it.

## Configuration

| Variable | Default | Effect |
|---|---|---|
| `OUTREACH_PAUSED` | `true` | The stop button. Anything but `false` is paused. |
| `OUTREACH_DAILY_LIMIT` | `5` | Messages per day. See the warm-up in `docs/mail.md`. |
| `OUTREACH_PER_DOMAIN_LIMIT` | `1` | Messages per company domain per day. |
| `OUTREACH_DISPATCH_BATCH_SIZE` | `5` | Per run. The daily limit still applies. |
| `OUTREACH_WORKING_HOUR_START` | `9` | Inclusive, 24h, in `GENERIC_TIMEZONE`. |
| `OUTREACH_WORKING_HOUR_END` | `17` | Exclusive. |
| `OUTREACH_WORKING_DAYS` | `1,2,3,4,5` | ISO days; 1 is Monday. |

All of them must also appear in the `n8n` service's `environment` block in
`docker-compose.yml`. A variable in `.env` and not there is invisible to n8n,
and the workflow falls back to its default without saying so.

## Installed

The SMTP credential is `smtpOutbound`, named
`SMTP account`, and the workflow is `wf06OutreachDispatch`, imported and
**inactive**.

The credential was created with the CLI rather than through the UI, because the
CLI encrypts it with `N8N_ENCRYPTION_KEY` exactly as the UI would and leaves the
id known instead of discovered:

```bash
# creds.json: [{"id","name":"SMTP account","type":"smtp","data":{user,password,
#              host:"smtp.gmail.com",port:465,secure:true,hostName:"example.com"}}]
docker cp creds.json aisales-n8n:/tmp/creds.json
docker exec aisales-n8n n8n import:credentials --input=/tmp/creds.json \
    --projectId=<personal project id>
docker exec -u root aisales-n8n rm -f /tmp/creds.json    # root: docker cp writes as root
```

The password never enters the repository. Verify a credential round-trips with
`n8n export:credentials --id=<id> --decrypted`, and delete that file afterwards.

Re-import the workflow after editing the JSON:

```bash
docker exec aisales-n8n n8n import:workflow --input=/workflows/ai-sales-outreach-dispatch.json
```

## The last step, deliberately last

**`OUTREACH_PAUSED=false`, then restart n8n**, and activate the workflow.

Nothing before this point can send. `.env` alone is not enough: the variable has
to reach the container, which means a restart, which is why this is one step and
not two.

Do it only once the drafts in `pending_approval` have been read and approved by
a person, and only with `OUTREACH_DAILY_LIMIT` still at the warm-up value in
`docs/mail.md`.

## Verified

Against the live database, every case in a transaction that was rolled back:

| Case | Result |
|---|---|
| `OUTREACH_PAUSED=true` | 0 claimed |
| Outside working hours | 0 claimed |
| Outside working days | 0 claimed |
| `OUTREACH_DAILY_LIMIT=0` | 0 claimed |
| Recipient on `suppression_list` | 0 claimed |
| Normal, 3 approved on 3 domains | 3 claimed |
| `OUTREACH_DISPATCH_BATCH_SIZE=1` | 1 claimed |
| `OUTREACH_DAILY_LIMIT=2` | 2 claimed |
| Two approved at one company, limit 1 | 1 claimed |
| `Record Send` replayed | second run writes nothing; 1 conversation, 1 message |
| `Record Send Failure` with no claimed row | writes nothing, queues no alert |
| `Record Send Failure` normally | `failed` + error, one `system` alert, lead untouched |

The send path itself has not run against a real mailbox. `docs/mail.md` records
that SMTP authenticates and that DKIM signs; what is untested here is this
workflow driving it.
