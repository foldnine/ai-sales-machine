# WF-08 Inbox Classifier

Reads replies and acts on them. Until it existed, an opt-out had to be noticed
by a human reading the mailbox and honoured with an INSERT by hand, and the risk
of missing one grew with every message sent.

Artifact: `n8n/workflows/ai-sales-inbox-classifier.json`
Prompt: `prompts/classifier.md` · Schema: `agents/classifier/schema.json`

```
Email Received                    (IMAP, every message by uid; flags untouched)
  -> Read Classifier Prompt / Schema
  -> Prepare Inbound              (headers, auto-reply and bounce detection)
  -> Match Thread                 (by Message-ID, then by sender)
  -> New Message?                 (drops a message already in `messages`)
  -> Classify?
       +-- no  -> Record Unhandled        (auto-reply, bounce, or no thread)
       +-- yes -> Classify Local          (llama3.1:8b)
                    -> Confident?
                         +-- yes -> Apply Classification
                         +-- no  -> Classify Escalated (qwen3.6:27b) -> Apply
```

## Why IMAP and not a webhook

The same reason as WF-11: nothing can call this machine. An IMAP connection is
outbound, so it needs no domain, no tunnel and no open port.

**`INBOX_RECONNECT_MINUTES` is the real latency floor, not IDLE.** IDLE fires
when mail *arrives*. It does not fire for a message that landed while the socket
was down. A reconnect re-runs the search, so the worst case before a reply is
seen is that interval. Five minutes on a mailbox this quiet costs nothing.

**Every message, not `UNSEEN`, and the read flag is never touched** (since
2026-11-06). Until then the trigger searched `UNSEEN` and marked what it fetched
as read. The operator also reads this mailbox in a mail client, so any reply
they opened before the next reconnect was never seen here: for more than three
weeks no reply was recorded at all while outreach kept going out. Leads were one
approval away from an automatic follow-up as a result - including one that had
asked for more information and one that had written "STOP". And a reply WF-08
did catch showed up in the mail client already read.

Now: `customEmailConfig` `["ALL"]`, `postProcessAction` `nothing`,
`trackLastMessageId` on. The node remembers the highest uid it fetched and asks
only for higher ones; before it has one, it asks for mail since the activation
day. The old warning against `trackLastMessageId` was about `postProcessAction:
read`, which flags *every* fetched message `\Seen`, including the ones the uid
filter then drops. With `nothing` no flag is set, so that cannot happen
(n8n-nodes-base `EmailReadImap/v2/utils.js`: fetch uses `markSeen: false`;
`addFlags` runs only for `read`).

Re-reading the activation day after a re-activation is expected. `Match Thread`
returns `already_recorded` (the Message-ID is already in `messages`), and
`New Message?` stops there, so nothing is classified twice and no second reply
draft is queued.

## Matching a reply to a thread

Two ways, in order:

1. **Message-ID.** WF-06 stores the id it submitted as
   `conversations.external_thread_id`; a reply quotes it in `In-Reply-To`, and a
   reply to a reply carries the whole chain in `References`. Both are searched.
2. **Sender address**, against a person on a lead that was actually contacted.

The second exists because a reply can arrive from a colleague the message was
forwarded to, or from a different alias. Matching nothing is a normal outcome —
this mailbox also receives newsletters and service mail, and those must never
reach a classifier or a `messages` row.

**`Match Thread` always returns exactly one row**, matched or not, and carries
the inbound fields back out. A node that returns nothing breaks the paired-item
lineage, and the unmatched branch then reads empty strings for every field: the
first unmatched message produced an alert whose dedup key was the md5 of `""`.

## A stop request overrides the category

`prompts/classifier.md` is explicit about the order, and it is enforced in SQL
rather than trusted to the model:

1. Suppress — **both** the address that replied and the address that was written
   to. They are usually the same. When they are not, it is because a colleague
   answered "stop", and suppressing only the colleague would leave the original
   recipient in the follow-up queue.
2. Cancel every `outreach` row not yet sent.
3. Conversation to `unsubscribed`, lead to `suppressed`.
4. Log it. **Do not reply** — a confirmation is another email.

`requested_stop` does this whatever the category says, so a message the model
filed as `QUESTION` still suppresses.

## What each category does

| Category | Conversation | Lead | Alert |
|---|---|---|---|
| `UNSUBSCRIBE`, or `requested_stop` | `unsubscribed` | `suppressed` | immediate |
| `POSITIVE` | `awaiting_human` | `opportunity` | immediate |
| `NEGATIVE` | `closed_lost` | `closed_lost` | normal |
| `NOT_NOW` | `nurture` | `nurture` | normal |
| `QUESTION`, `PRICE`, `REFERRAL` | `awaiting_human` | `replied` | normal |
| `OUT_OF_SCOPE` | unchanged | unchanged | none |
| confidence < 0.7, or `human_required` | `awaiting_human` | `replied` | normal |

`QUESTION` and `PRICE` stop at a human because WF-09 does not exist. When it
does, they are the two that it answers.

## Escalation goes to a bigger local model, not to an API

The prompt specifies re-running a low-confidence classification on the external
LLM. There is no `LLM_API_KEY`, and there is no budget for one. A larger local
model is the same idea at no cost: ask something slower and better when the fast
answer is not trustworthy. `llama3.1:8b` first, `qwen3.6:27b` on anything under
0.7, and still under 0.7 means a human.

An unparseable response is not a licence to guess. It becomes
`OUT_OF_SCOPE` at confidence 0 with `human_required`, which routes it to a
person.

## Bounces

A bounce is not a reply and never reaches the classifier. It is detected from
the sender (`mailer-daemon@`, `postmaster@`), from `X-Failed-Recipients`, or
from the subject, and it **suppresses the lead's address** — not the
postmaster's that reported it — with reason `hard_bounce`. An address that hard
bounces will not start working, and continuing to send to it is what damages a
young domain's reputation.

## Verified

Every branch against the live database, in transactions that were rolled back:

| Case | Result |
|---|---|
| Match by `In-Reply-To` | matched, `matched_by = thread` |
| Match by `References`, unknown sender | matched — the forwarded case |
| Match by sender with no thread header | matched, `matched_by = sender` |
| Newsletter | no match, one row out, fields intact |
| `UNSUBSCRIBE` | suppressed, cancelled, `unsubscribed` / `suppressed` |
| `QUESTION` with `requested_stop` | identical to `UNSUBSCRIBE` |
| Colleague replies "stop" from another address | both addresses suppressed |
| `POSITIVE` | `awaiting_human` / `opportunity`, immediate alert |
| `NEGATIVE` | `closed_lost` both |
| confidence 0.4 | `awaiting_human`, not acted on by category |
| `OUT_OF_SCOPE` | nothing changed |
| Bounce | lead's address suppressed, `hard_bounce` |
| Auto-reply on a known thread | recorded, no alert, no model call |

And end to end through real IMAP on 2026-09-22: a reply carrying
`In-Reply-To: <wf08-thread-test@example.com>` and the text *"Please remove me
from your list and do not contact me again. This is spam."* was classified
`UNSUBSCRIBE` at confidence 1.00 by the local model, the conversation went to
`unsubscribed`, the lead to `suppressed`, and the inbound message was recorded.
The disposable company, lead and thread used for it were deleted afterwards.
