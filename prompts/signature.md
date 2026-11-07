# Outreach envelope

> **Edit this file before anything is sent.** The signatures below ship with
> the placeholder `Your Name`, and the taglines and URLs they pull in from
> `agents/offers.json` say `Your Company` and `example.com`. Replace all of
> them with your real identity.

The outreach agent writes the middle of the message and nothing else. The
greeting and the signature are assembled in code, from this file, and appended
by WF-05 before the draft is stored - so the text a human approves is the text
that gets sent, not a summary of it.

They are not left to the model on purpose. A greeting is a fact about the
recipient and the system already knows their name; a signature is a claim about
the sender, and a model that writes its own signature is a model inventing a
job title, a company or a promise. `docs/outreach-generation.md` records what
happens when the model is trusted with a field nothing checks.

**Never write anything here that claims a size, a team or a client the business
does not have.** The recipients are European companies, commercial email there
has to identify its sender, and `docs/security.md` rests the whole
legitimate-interest basis on that identification being true.

Edit this file and the next run picks it up. There is no copy inside the
workflow JSON.

## Greeting

`{first_name}` is the recipient's first name as `people.full_name` records it.
It is the only placeholder in the greeting; anything else in braces is left
alone.

```
Hi {first_name},
```

## Greeting (role)

For a role contact: the company's published general address (`info@`,
`office@`, `kontakt@`), used only when no named person with an address was
found (`docs/contact-enrichment.md`, decided 2026-09-24). There is no name to
greet and none is invented, so the greeting has no placeholder. Whoever reads a
general inbox is greeted as a reader, not as a guess.

```
Hello,
```

## Signature

The opt-out line is an obligation, not a formality. Until WF-08 exists nothing
reads replies, so a "stop" has to be honoured by hand:

    INSERT INTO suppression_list (email, reason) VALUES ('<address>', 'requested_stop');

```
--
Your Name
{tagline}
{url}

Not the right person, or not interested? Reply "stop" and you will not hear
from us again.
```

`{tagline}` is the line's tagline from `agents/offers.json`: *"Your Company -
infrastructure audits, DevOps and SRE"* on the infrastructure line, *"Your Company -
business process automation"* on the automation line. The signature names the
offer the message makes, so a recipient reads one description of the business,
not two. `{url}` is the line's page on the site: `/infrastructure/` for the
infrastructure line, the home page for automation, so the link lands on the
offer the message made.

It used to read *"DevOps, backend and frontend engineering"*. That was wider
than what the site sells and wider than what the first message offers, so a
recipient who clicked through met a third description of the business. The line
now names the default offer in `prompts/outreach.md` - the audit - and stops.

## Greeting (sr)

For companies whose country is mapped to Serbian in `OUTREACH_LANGUAGES`
(see `prompts/outreach.md` → *Serbian*). "Dobar dan" is polite
without needing the recipient's gender, which "Poštovani/Poštovana" would.

```
Dobar dan, {first_name},
```

## Greeting (role, sr)

The Serbian greeting for a role contact. "Poštovani," addressed to a company's
general inbox is the ordinary formal opening of a business letter and needs no
name; the gender question above only arises when it is followed by one.

```
Poštovani,
```

## Signature (sr)

```
--
Your Name
{tagline}
{url}

Niste prava osoba ili vas ovo ne zanima? Odgovorite „stop“ i više vam se
nećemo javljati.
```

`{tagline}` is the line's `tagline_sr` in `agents/offers.json`. WF-08 recognises
"stop" and the Serbian ways of asking to be removed in code, not only through
the classifier (`prompts/classifier.md`).

**Add your registered identity.** Commercial email has to identify its sender
truthfully: in the EU the legitimate-interest basis in `docs/security.md` rests
on it, and in the US CAN-SPAM requires a valid physical postal address in every
message. A name and a URL are not a registered business name, address and,
where it applies, a company or tax number. Put yours in both signatures above
(and on your site), and do not fill them in by guessing.

**Plain text, and no image.** No logo, no HTML table, no tracking pixel. A cold
message that arrives as a multipart HTML document with a remote image in the
signature is a cold message that arrives in a spam folder, and a pixel that
reports back is a thing this system has decided not to do.
