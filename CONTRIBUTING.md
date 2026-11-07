# Contributing

Thanks for wanting to help. This project is small on purpose - three
containers, prompts and SQL - and contributions that keep it that way are the
easiest to merge.

## Before you start

- **Open an issue first** for anything bigger than a bug fix or a doc
  correction, so we can agree on the approach before you spend time on it.
- Read [`docs/architecture.md`](docs/architecture.md). The short version:
  rules belong in the database, the model's output is checked in code, and no
  change may make it easier to send something a human did not approve.

## Development setup

You do not need the full stack to work on most things:

```bash
make validate       # compose config, shell syntax, workflow JSON structure
make test           # every migration + postgres/tests in a throwaway PostgreSQL (needs Docker)
make secrets-scan   # nothing credential-shaped is tracked
```

For workflow or prompt changes, run the stack locally (README, *Quick start*)
with `OUTREACH_PAUSED=true` and use `make seed-demo` - it only uses reserved
example domains.

## Rules for pull requests

1. **No real data.** No real company, person, email address or domain in code,
   tests, seeds, fixtures or screenshots. Use `example.com` / `example.org`.
2. **Never edit a released migration.** Add a new numbered file in
   `postgres/migrations/`, and a test in `postgres/tests/` for anything that
   enforces a rule.
3. **Workflows are exported JSON.** Edit in the n8n UI, export
   (`n8n/README.md`), then `make validate`. Credentials are referenced by id,
   never embedded.
4. **Safety defaults stay restrictive.** `OUTREACH_PAUSED=true`,
   `OUTREACH_AUTOSEND_ENABLED=false` and low limits in `.env.example` are not
   up for a convenience change.
5. **Explain why.** Commit messages and PR descriptions say why the change is
   needed, not only what it does. Docs move with the code.

CI runs `make validate`, `make test`, `make secrets-scan` and shellcheck on
every pull request.

## Good first contributions

- Adapters for more discovery sources (public directories, job boards)
- Translations of the outreach envelope and opt-out detection for more
  languages (`prompts/signature.md`, `prompts/classifier.md`)
- Running on other model providers or hardware, documented in `docs/ollama.md`
- WF-07 (follow-ups) and WF-09 (conversation) - see `docs/roadmap.md`

## Code of conduct

Participation is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
