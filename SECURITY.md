# Security policy

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Use GitHub's private reporting instead: **Security → Report a vulnerability**
on this repository. You will get an acknowledgement within a few days, and we
will agree a disclosure date with you once a fix exists.

Useful in a report: the affected file or workflow, what an attacker controls
(a web page the research agent reads, an inbound email, a Telegram message),
and what they can make the system do.

## Scope

In scope:

- Anything that makes the system **send email nobody approved**, bypass the
  suppression list, ignore `OUTREACH_PAUSED`, or exceed the rate limits
- Prompt injection from fetched web pages or inbound replies that changes what
  is written to the database or sent
- SQL injection in workflow queries, secrets leaking into logs, exports or
  `agent_runs`
- Defaults that expose PostgreSQL, Ollama or the n8n editor beyond loopback

Out of scope: vulnerabilities in n8n, PostgreSQL, Ollama or Caddy themselves
(report those upstream), and deployments where the operator changed the
bind addresses or disabled the guards.

## Hardening built in

The design is in [`docs/security.md`](docs/security.md): loopback-only
binds, a database trigger that rejects mail to suppressed addresses, model
output validated against a schema and re-checked in code, encrypted backups,
and `make secrets-scan` in CI.
