# CLAUDE.md

Context for Claude Code (or any coding agent) working in this repository.
Read `README.md` for what the system is; this file is how to work on it
without breaking it or sending something nobody approved.

## Where you are

- **Next to a running stack** (a checkout with a `.env` and `aisales-*`
  containers): this is someone's production. Real companies, real mailboxes,
  a real suppression list.
- **Anywhere else** (a fresh clone, CI, a laptop without `.env`): a development
  checkout. Nothing to break but the code.

Check with `ls .env && docker ps --format '{{.Names}}'` before assuming either.

## Rules that are not negotiable

1. **Never send outreach, and never flip a switch that sends.** Guarded
   autosend is an opt-in only the operator controls: the master switch
   `OUTREACH_AUTOSEND_ENABLED` in `.env`, and `/autosend on`, `/autosend off`
   and `/stop` on Telegram (`0030_autosend.sql`,
   `docs/outreach-generation.md`). An agent never flips either switch, never
   sets `OUTREACH_PAUSED` to anything but `true`, never approves drafts, never
   triggers WF-06, and never loosens a blocker without being asked. `/stop` is
   final until the operator turns autosend back on themselves.
2. **Back up before touching the database.** `make backup` before
   `make migrate`, an image upgrade, or any SQL that writes.
3. **Never edit a migration that has been released.** Add a new numbered one.
   `migrate.sh` checksums applied migrations and reports DRIFT.
4. **Never print, log, commit or paste secrets.** Not `.env`, not
   `.env.bak-*`, not n8n credentials. Refer to variables by name.
5. **Never widen exposure.** Everything binds to `127.0.0.1`. Remote access is
   `tailscale serve` (or a Cloudflare Tunnel for webhooks), never
   `tailscale funnel`, never `0.0.0.0`, never a router port forward.
6. **Never delete data.** `make clean` and `make db-reset` refuse without
   `CONFIRM=yes`; do not pass it. Do not remove a Docker volume unless the
   human has agreed to that specific one.
7. **Ask before restarting n8n while a workflow is running.** A restart kills
   the run in flight and costs a research batch (`docs/company-research.md`).
8. **System settings, logins and anything needing a password are the human's.**
   Say exactly what to click; do not try to work around it.
9. **Never put a real company, person or address in a commit.** Tests and seeds
   use reserved example domains (`example.com`, `example.org`) only.

## Commands

```bash
make help            # everything
make ps              # container status
make health          # full health check - run after any change
make logs SERVICE=n8n
make backup          # encrypted dump; required before migrate/upgrade
make migrate-status  # applied vs pending
make migrate         # apply pending (after backup)
make env-upgrade     # what in .env is out of date; APPLY=yes to fix it
make validate        # compose, scripts, workflow exports - before any commit
make test            # migrations + SQL tests in a throwaway PostgreSQL
make secrets-scan    # before any commit
make deploy          # origin/main to the stack: drains, backs up, migrates, imports, restarts
```

## Changing things

- Workflows: the JSON in `n8n/workflows/` is the source of truth. After editing
  in the n8n UI, export and commit (`n8n/README.md`). After editing JSON,
  `make validate`, then re-import.
- Prompts: `prompts/*.md` are read at run time; a change takes effect on the
  next run. Every `extractFromFile` node must set `options.encoding: utf8`
  (`docs/workflows.md` explains the incident).
- Rules belong in the database where possible, not in a prompt
  (`docs/architecture.md`). A limit stated in a prompt is also checked in code
  after the model returns.
- Business-specific content (who the sender is, what they sell) belongs in
  `agents/offers.json`, `prompts/signature.md` and the `CUSTOMIZE` blocks in
  `prompts/` - see `docs/customizing.md`. Do not hardcode it anywhere else.
- Commit on a branch and open a pull request; CI runs `make validate`,
  `make test`, `make secrets-scan` and shellcheck. Commit messages say why.
