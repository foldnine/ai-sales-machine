# WF-11 Telegram Commands

Reads commands back from Telegram. The other half of `docs/telegram.md`, whose
outbound half is WF-10.

Artifact: `n8n/workflows/ai-sales-telegram-commands.json`
Migration: `postgres/migrations/0014_telegram_commands.sql`

```
Every 30 Seconds
  -> Telegram Configured?     (enabled, chat id and token all set)
  -> Read Offset              (app_settings)
  -> Get Updates              (getUpdates, long-poll disabled)
  -> Parse Commands           (authorise, split command and argument)
  -> Apply Command            (record, apply and compose the answer, one statement)
  -> Reply Needed?            (an unauthorised chat is answered with silence)
       +-- yes -> Send Reply -> Save Offset
       +-- no  -> Save Offset
```

## Polling, because a webhook has nothing to arrive on

`docs/telegram.md` specifies a Telegram Trigger. A Telegram Trigger is a
webhook, which means Telegram has to call this machine, and it cannot: n8n is
bound to `127.0.0.1`, Caddy aborts anything that is not localhost, and
`N8N_HOST` is still `n8n.example.com`.

The alternative to polling is making n8n reachable from the internet - a real
domain, a tunnel, TLS - to approve five messages a day. That is a large new
attack surface bought with a latency saving of under a minute, against a system
whose own `docs/security.md` says n8n is never public without TLS and
authentication. Polling every 30 seconds costs one HTTPS request per 30 seconds
and exposes nothing.

## The token had to move, so the rule moved with it

`docs/telegram.md` says the bot token deliberately does not go into
`TELEGRAM_BOT_TOKEN`, because an HTTP node would put it in the URL of every
saved execution.

Polling makes that impossible to honour literally. The Telegram API carries the
token in the URL path - `/bot<token>/getUpdates` - and offers no header to put
it in instead, and n8n's `telegramApi` credential has no `authenticate` block,
so an HTTP Request node cannot have the token injected for it.

So the intent was kept and the mechanism changed:

- `TELEGRAM_BOT_TOKEN` exists, in `.env` and in the container, nowhere else.
- **WF-11 saves no execution data at all** - `saveDataSuccessExecution` and
  `saveDataErrorExecution` are both `none`. There is no saved execution for the
  URL to appear in.
- The audit trail n8n's execution history would have given is the `command_log`
  table instead. It is the better of the two: it survives execution pruning, it
  can be queried, and it holds what was asked rather than what was transmitted.
- Replies still go out through the n8n credential, so `Send Reply` never sees
  the token.

## Authorisation

Checked in `Parse Commands` against `TELEGRAM_CHAT_ID`, and checked again in
SQL, because the first check is a convenience and the second is the one that
guards the `UPDATE`.

A command from any other chat is **recorded and not answered**. `docs/telegram.md`
asks for it to be ignored, and it is - silence is the answer. It is still written
to `command_log` with outcome `unauthorised`, because a command arriving from a
chat that is not yours is how you learn the bot token has leaked, and a record is
not a reply.

## Replay is a no-op

`getUpdates` returns everything newer than the stored offset, and the offset is
saved **after** the command has been applied. If the workflow dies in between,
the same update arrives again on the next pass.

`command_log.update_id` is `UNIQUE`, and every `UPDATE` in `Apply Command` is
guarded on `EXISTS (SELECT 1 FROM logged)` - the insert that the second attempt
does not make. So the second attempt changes nothing.

The alternative - saving the offset first - loses commands instead of repeating
them, and a lost `/reject` is worse than a repeated one.

`Save Offset` uses `GREATEST`, because it runs once per command in a batch and
n8n promises no order; a smaller number arriving late must not walk the offset
backwards and replay the batch forever.

## Short ids

The approval message prints the first four characters of the outreach uuid,
because it gets typed on a phone. `resolve_outreach_prefix()` resolves the
prefix and **refuses rather than guesses**:

| Prefix | Result |
|---|---|
| Matches exactly one draft at `pending_approval` | that draft |
| Matches none | `not_found` |
| Matches more than one | `ambiguous` - the reply asks for more characters |
| Fewer than 4 characters, or empty | `not_found` |

The minimum length is not cosmetic. An empty prefix matches every row, so with
exactly one draft queued a bare `/approve` with no argument would have approved
it.

Only a row at `pending_approval` is eligible. Approving something already sent,
rejected or failed does not quietly succeed.

## Autosend: /autosend on|off, /stop

Guarded autosend (`0030_autosend.sql`, `docs/outreach-generation.md`), an opt-in
the operator turns on. `Apply Command` calls `autosend_command()` once per
logged update, only for `TELEGRAM_CHAT_ID`; a replayed update answers
"Već obrađeno." and does nothing.

| Command | Effect |
|---|---|
| `/autosend on` | Refused, outcome `refused`, while `OUTREACH_AUTOSEND_ENABLED` is not `true`: the master switch is `.env`, never a phone. Otherwise turns autosend on and sweeps the queue: every draft at `pending_approval` goes through `autosend_blockers()`, the clean ones are approved. The reply counts both and names the commonest reasons |
| `/autosend off`, `/stop` | Turns it off. Every draft autosend approved that WF-06 has not claimed goes back to `pending_approval` (`/leads`). Reply: "Autosend isključen. Novi draftovi idu na odobrenje." |
| `/autosend` | On or off, approved automatically today (and how many of those were sent), held today with the commonest reasons, and whether `OUTREACH_PAUSED` is stopping WF-06 anyway |

Replies are in Serbian; the reasons are the blockers' own `kind: detail` text.
`/stop` stays in force until the operator sends `/autosend on` again.

## Configuration

| Variable | Effect |
|---|---|
| `TELEGRAM_ENABLED` | `true` or WF-11 claims nothing |
| `TELEGRAM_CHAT_ID` | The only chat that may issue commands |
| `TELEGRAM_BOT_TOKEN` | Required by WF-11. WF-10 still uses the credential. |
| `OUTREACH_AUTOSEND_ENABLED` | Master switch for `/autosend on`; anything but `true` refuses it |
| `OUTREACH_LANGUAGES`, `GENERIC_TIMEZONE` | The language check of the sweep, and what "today" means in `/autosend` |

All three must also be in the `n8n` service's `environment` block in
`docker-compose.yml`, and a change needs `docker compose up -d n8n` - not
`restart`, which reuses the old environment.

## Verified

Against the live database, in transactions that were rolled back:

| Case | Result |
|---|---|
| `/approve <prefix>` | `outreach` and `leads` to `approved`, `approved_by` set |
| `/reject <prefix> <reason>` | `rejected`, reason stored |
| The same update applied twice | one `command_log` row, no second effect |
| Unknown prefix | `not_found`, nothing written |
| No argument | `not_found`, nothing written |
| Prefix matching two drafts | `ambiguous`, nothing written |
| Unknown command | `unknown`, reply lists the real ones |
| A chat that is not `TELEGRAM_CHAT_ID` | recorded `unauthorised`, reply is NULL |
| Offset 500, then 900, then 700 | stays 900 |

And end to end through real Telegram on 2026-09-22:

```
100000001  /status        applied  14:14:00
100000002  /leads         applied  14:14:00
100000003  /approve 342c  applied  14:14:30
```

`342c` (an example lead) moved to `approved`, `approved_by = telegram:123456789`,
and the offset advanced to `100000003`.
