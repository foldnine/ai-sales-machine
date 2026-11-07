# Setting up the sending mailbox

Outreach is sent from this mailbox, and WF-08 reads replies from it. The
example below uses Google Workspace and the domain `example.com` with the address
`you@example.com`; substitute your own. Credentials go in `.env`
(`EMAIL_FROM`, `SMTP_*`, `IMAP_*`), never in the repository.

## Why not a transactional provider

Resend, Postmark and SendGrid all prohibit cold outreach in their acceptable-use
policies, and all three suspend on detection rather than warn. They run shared
IP pools, so one customer's complaint rate is everyone's problem, and refusing
prospecting mail is the only way that model survives.

That rules out the whole category, not just those three. It costs nothing here:
WF-08 has to read replies over IMAP, and a transactional API is one-way, so this
system needs an ordinary mailbox regardless.

## Which provider

Any mailbox with SMTP, IMAP, DKIM signing and a custom domain works. Two lessons
from the reference deployment:

- **Do not run on a trial.** One provider's trial blocked outbound SMTP without
  saying so - IMAP authenticated and SMTP answered
  `535 5.7.8 Authentication credentials invalid` on the same credentials - and
  issued no DKIM keys until the domain was activated, so the published DKIM
  CNAMEs resolved to a placeholder. Both unblocked only by paying.
- **Google Workspace or Microsoft 365 are the safe default.** The companies you
  write to are mostly on one of the two themselves, and Gmail-to-Gmail carries
  the strongest reputation signal available. Calendar comes with it, which
  Phase 11 needs anyway.

Use a separate domain or subdomain for cold outreach if you want to protect the
reputation of the domain your normal business mail comes from.

## Which address sends

A person's address (`you@example.com`), not `admin@` or `sales@`.

A role address reads as automation before a word of the message is, and
`prompts/signature.md` signs every draft with a person's name - a message from
`admin@` signed with a name contradicts itself in its own headers. WF-03 also
refuses to write a role address into `people`, on the grounds that nobody is
behind one; sending cold mail *from* one is that same judgement turned around
and ignored.

If the Workspace account was created as `admin@`, rename it rather than adding a
second seat: Admin console > Directory > Users > the user > **Rename user**,
leaving **Create email alias** checked. Google keeps `admin@` as an alias, so
administrative mail still arrives, and it stays one paid seat. `EMAIL_FROM`,
`SMTP_USER`, `IMAP_USER` and the DMARC `rua` should all name the same address.

## Order of operations

The DNS half and the console half interleave, and doing them out of order is what
costs an afternoon. Steps 4 and 6 are the two that are easy to leave undone and
silent when undone.

1. **Buy the mailbox plan** for your domain. A paid plan, not a trial.
2. **Remove any old mail records** (MX, SPF, DKIM of a previous provider). A DNS
   import usually adds rather than replaces, and a second SPF record is as
   invalid as none.
3. **Verify the domain.** Admin console > Account > Domains. Publish the
   `google-site-verification` TXT it gives you.
4. **Publish MX and SPF.** For Google: one MX, `smtp.google.com` priority 1 -
   not the five legacy `aspmx` records - and
   `v=spf1 include:_spf.google.com ~all`.
5. **Generate DKIM.** Admin console > Apps > Google Workspace > Gmail >
   Authenticate email. 2048-bit, selector `google`. Publish the TXT, wait for
   propagation, **then come back and click Start authentication.** Generating the
   key does not start signing, and nothing tells you it has not started.
6. **Enable IMAP** for the mailbox in the admin console. Off by default on some
   plans, and WF-08 is silent about why it sees nothing.
7. **Publish DMARC**, starting at `p=none` with a `rua` address you read:
   `_dmarc.example.com TXT "v=DMARC1; p=none; rua=mailto:you@example.com"`.
   Gmail and Yahoo throttle or reject bulk senders without one.
8. **Turn on 2-Step Verification, then generate an app password** at
   `myaccount.google.com/apppasswords`. Basic auth for SMTP/IMAP was disabled in
   May 2025; app passwords are the surviving exception and 2SV is a precondition.
   The password is shown once. Put it in `SMTP_PASSWORD` and `IMAP_PASSWORD`.

## Verifying, rather than assuming

A provider that silently refuses SMTP is invisible for days if nobody
authenticates against SMTP specifically. Check both protocols, separately:

```bash
python3 - <<'PY'
import smtplib, ssl, imaplib
env = dict(l.strip().split('=', 1) for l in open('.env')
           if l.strip() and not l.startswith('#') and '=' in l)
s = smtplib.SMTP_SSL(env['SMTP_HOST'], int(env['SMTP_PORT']), timeout=15,
                     context=ssl.create_default_context())
s.login(env['SMTP_USER'], env['SMTP_PASSWORD']); s.quit(); print("SMTP OK")
m = imaplib.IMAP4_SSL(env['IMAP_HOST'], int(env['IMAP_PORT']))
m.login(env['IMAP_USER'], env['IMAP_PASSWORD']); m.select('INBOX')
m.logout(); print("IMAP OK")
PY
```

And that DKIM is actually being signed, which step 5 leaves undone by default:

```bash
dig +short TXT google._domainkey.example.com @1.1.1.1
```

A `v=DKIM1; k=rsa; p=...` answer means the record is published. It does not mean
signing is on.

**Do not test that by mailing yourself.** A message from `you@example.com` to
`you@example.com` never leaves Google, so it arrives with no `DKIM-Signature`
and no `Authentication-Results` whether signing is on or off. The absence proves
nothing, and reads exactly like failure.

Signing is only observable in a message some other domain received. An automated
verifier is the cheapest way to see one:

- `ping@tools.mxtoolbox.com` replies within a couple of minutes. The reply is
  HTML and its verdicts are **status icons, not text** - `problem.png` or
  `ok.png` in the DMARC, SPF and DKIM rows - so grepping the body for "pass"
  finds nothing. Read the `<img>` filenames per row.
- `check-auth@verifier.port25.com`, the usual suggestion, accepted the message
  and never replied when tried. Do not rely on it.

What a good result looks like:

| | |
|---|---|
| SMTP auth | OK, `smtp.gmail.com:465`, app password |
| IMAP auth | OK, `imap.gmail.com:993`, same password |
| SPF | pass |
| DKIM | pass - signing is on |
| DMARC | `p=none` while warming up; flagged as a problem by MXToolbox, deliberately |

DMARC is reported as a problem because `p=none` does not enforce. That is the
intended setting while the domain has no sending history. It becomes a real
finding only if it is still `none` after a month of clean reports.

MXToolbox may list a Google outbound IP on a blacklist such as 0SPAM. That is a
shared Google address, not your domain's reputation. Nothing to act on.

## Warm-up

A new domain has no sending history. One opening at 20 messages a day looks like
a domain bought to spam from, so `OUTREACH_DAILY_LIMIT` starts at 5.

Roughly double weekly while the DMARC aggregate reports stay clean, to a
ceiling of about 20 a day per mailbox. Hold, and investigate, on any bounce that
is not a dead address.

DMARC stays at `p=none` until a month of clean reports, and must not move to
`quarantine` while DKIM is unpublished - that would quarantine your own mail.
