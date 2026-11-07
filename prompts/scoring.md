# Scoring agent

Used by **WF-04 Lead Scoring**. Reads the research output and the `signals`
rows; writes `companies.fit_score`, `companies.research_score`,
`companies.decision_maker_score` and the `leads` row.

`companies.total_score` and `companies.score_band` are generated columns - the
agent must never write them. Write the three components and let the database
compute the rest, so the band can never disagree with the parts.

---

<!-- CUSTOMIZE: the rubric scores fit for the reference offers (DevOps/SRE
and process automation). Adapt the criteria to your own ideal customer; keep
the JSON keys, the point totals and the bands, which the database enforces. -->

## Who this rubric is for

The buyer is a company that **runs production software and has nobody whose job
is to run it**. Twelve engineers, real customers, deploys that happen on a
Friday because someone remembered to, and not one person with Platform or SRE
in their title.

A company with a platform team is not a prospect. Neither is a company that
posted a DevOps role last month - they have diagnosed the problem themselves,
have budget approved for a salary, and will fill it. There is nothing to sell
except what they have already decided to buy.

This inverts the obvious reading of every signal. A sophisticated stack is not
a qualification, it is a *load*; what qualifies is that load sitting on people
who were hired to do something else. Read every component below that way.

## The rubric: 100 points

| Component | Max | Column | What it now measures |
|---|---|---|---|
| Company fit | 20 | `fit_score` | Small enough to have no platform team, big enough to pay |
| Operational load | 20 | `fit_score` | How much there is to operate |
| Capacity gap | 20 | `research_score` | How little of it is owned |
| Pain evidence | 20 | `research_score` | Whether the gap is already hurting |
| Decision maker | 10 | `decision_maker_score` | Reachable, and senior enough to decide alone |
| Commercial potential | 10 | `fit_score` | Can pay for an audit |

`fit_score` = company fit + operational load + commercial potential (0-50)
`research_score` = capacity gap + pain evidence (0-40)
`decision_maker_score` = decision maker (0-10)

The column names in the database still read `fit_score` and `research_score`.
The JSON keys still read `technology_fit` and `hiring_signal`, because WF-04
and the `agent_runs` history depend on them. Only the meaning changed.

### Company fit (20)

| Points | Condition |
|---|---|
| 18-20 | 8-60 engineers, product company, real customers, **zero infra people counted on a team page that was read** |
| 13-17 | 5-100 engineers, ships production software, infra ownership unclear |
| 7-12 | Size unknown, or software important but not the product |
| 1-6 | Under 5 engineers, pre-product, or an agency selling the same service |
| 0 | A competitor, an existing client, already suppressed, or **a visible platform/SRE team** |

`infra_people_found = 0` is worth the top band. `infra_people_found = null` is
not - it is the same ignorance as an empty research run, and it belongs in the
13-17 band at best. A company above roughly 150 engineers has a platform team
whether or not it is visible, and a procurement process a solo consultant
cannot economically enter.

### Operational load (20) - JSON key `technology_fit`

Not how modern the stack is. How much of it has to be kept alive, weighed
against who is keeping it alive.

| Points | Condition |
|---|---|
| 18-20 | Kubernetes, multi-service or multi-region, **and no infra people found** - a loaded gun nobody was hired to carry |
| 13-17 | Cloud plus Docker plus some IaC, small team, deploys visibly manual |
| 8-12 | Cloud plus containers, ownership unclear |
| 3-7 | Managed PaaS end to end - little to operate, so little to audit |
| 1-2 | Static site or no product infrastructure |
| 0 | No technology evidence at all, or `runs_production` is false |

Only count technology with a source. An empty `technology` array scores 0.

**The top band is conditional.** Kubernetes at a company with four platform
engineers scores 3, not 19. The same Kubernetes at a company with none scores
19. The technology alone tells you nothing; the ratio does.

### Capacity gap (20) - JSON key `hiring_signal`

The inversion is sharpest here. Under the old rubric an open senior DevOps role
was the strongest signal in the system. It is now close to the weakest.

| Points | Condition |
|---|---|
| 18-20 | Multiple open engineering roles, **none of them infrastructure**, on a careers page that was read |
| 13-17 | An infrastructure role open more than 120 days - the need is real and they cannot hire it |
| 8-12 | Engineering headcount growing, hiring page not readable |
| 3-7 | No hiring activity either way |
| 1-2 | An infrastructure role open 60-120 days |
| 0 | An infrastructure role posted within 60 days, **or** a named platform/SRE team |

A company hiring four product engineers and no infrastructure engineer is
adding load every month and nobody to carry it. That is the buying moment.

A company that posted "Senior DevOps Engineer" three weeks ago has already
decided, already has the salary approved, and will not retain a consultant
instead. Score it 0 and move on - being early here is not an advantage, it is
a wasted email.

The 120-day exception is the one case where an infrastructure advert helps: a
role nobody has filled in four months is a need the market is not supplying,
and a fractional arrangement is the answer they have not thought of.

### Pain evidence (20)

| Points | Condition |
|---|---|
| 18-20 | Public, dated, specific: an incident write-up, a cost post, a stated migration in trouble |
| 13-17 | A stated problem in a job advert, or a product-engineer advert quietly asking for Kubernetes |
| 8-12 | Structural mismatch established from counted evidence: heavy infrastructure, `infra_people_found = 0` |
| 3-7 | Weak or undated indications |
| 0 | None, or an absence with no `absence_check` behind it |

The 8-12 band is the one that changed. Under the old rubric, pain inferred from
a mismatch was capped because it was guesswork. It is no longer guesswork when
`infra_people_found` is an integer counted off a page in `absence_checks` - that
is an observation, and it scores as one. An absence *asserted* without a check
still scores 0, and always will.

### Decision maker (10)

| Points | Condition |
|---|---|
| 9-10 | Founder or CTO of a company under 60 people, with a verified email |
| 6-8 | Named CTO/VP Eng, email guessed or catch-all |
| 3-5 | Role identified, person not |
| 0 | No route to anyone who could decide |

Seniority matters less than whether they can say yes without a committee. In a
30-person company the CTO is that person; in a 300-person company nobody is.

### Commercial potential (10)

| Points | Condition |
|---|---|
| 9-10 | Funded or profitable, and small enough that an audit is a decision one person makes |
| 6-8 | Can plausibly afford an audit and a follow-on sprint |
| 3-5 | Could afford a one-off audit only |
| 0 | Pre-revenue with no funding, or a non-paying sector |

Seed and Series A companies score well here, not badly. They have money and no
internal platform function - the two conditions this whole rubric is looking
for.

## Bands

| Total | Band | Action |
|---|---|---|
| 0-39 | `IGNORE` | No further spend. Do not enrich, do not draft. |
| 40-59 | `NURTURE` | Keep, re-check in 90 days. No outreach. |
| 60-74 | `OUTREACH` | Enrich contacts, draft, queue for human approval. |
| 75-89 | `HIGH_PRIORITY` | Same, moved to the top of the approval queue. |
| 90-100 | `HOT` | Same, plus a Telegram notification when the band is reached. |

## Hard overrides

Applied after scoring. These set the band regardless of the total:

- Domain or email on `suppression_list` -> company `status = 'suppressed'`, no lead.
- Competitor (sells DevOps/SRE/platform consulting) -> `IGNORE`.
- Existing or former client -> `IGNORE`, handled by a human.
- Research `confidence` below 0.3 -> cap the total at 39 until re-researched.
- No contactable person -> the lead may exist but cannot reach `OUTREACH`.
- **`runs_production` is false** -> `IGNORE`. Nothing to operate, nothing to audit.
- **A named platform, SRE or infrastructure team** -> `IGNORE`. They employ the
  person being sold.
- **An infrastructure role posted within 60 days** -> cap the total at 59. They
  are hiring the solution.

## System prompt

```
You are scoring a company as a prospect for a senior DevOps/SRE consultant.

The consultant sells to companies that RUN production software and have NOBODY
whose full-time job is to run it. A company with a platform team, an SRE team,
or a DevOps role posted in the last 60 days is NOT a prospect, no matter how
impressive its engineering looks. It has already bought the solution.

Apply the rubric in this document literally. Award points only for evidence
present in the supplied research output.

Two rules about absence, because this rubric buys on absence:

  - An absence backed by an entry in `absence_checks` with result `absent` is
    EVIDENCE and scores as evidence. `infra_people_found: 0` counted off a
    team page is one of the strongest signals available.
  - An absence with no such entry is NOT evidence. `infra_people_found: null`
    scores as ignorance, never as zero infra people. If the research agent did
    not look, you did not find anything.

Everything else follows the old rule: absent evidence scores zero, never
"average".

You are calibrating a machine that will spend money and someone's attention. A
score that is too generous is more expensive than one that is too harsh,
because it produces an email to a company that did not need one.

Return valid JSON only, no prose, no markdown fences:

{
  "company_fit": { "points": 0, "reason": "" },
  "technology_fit": { "points": 0, "reason": "" },
  "hiring_signal": { "points": 0, "reason": "" },
  "pain_evidence": { "points": 0, "reason": "" },
  "decision_maker": { "points": 0, "reason": "" },
  "commercial_potential": { "points": 0, "reason": "" },
  "fit_score": 0,
  "research_score": 0,
  "decision_maker_score": 0,
  "total_score": 0,
  "band": "",
  "recommended_offer": "",
  "reason": "",
  "overrides_applied": []
}

The JSON keys `technology_fit` and `hiring_signal` are historical names. They
now carry Operational load and Capacity gap respectively - score them by the
rubric text, not by the key.

`reason` is one sentence, written for a human deciding whether to approve an
email. It must name the specific evidence, not the score.

`total_score` and `band` are returned for logging and for the workflow to
cross-check. The database recomputes both; if they disagree, the database wins
and WF-99 raises the mismatch.
```

## Worked example - a prospect

Research shows: 22-person B2B SaaS, team page read and listing 14 engineers of
whom **zero** are infrastructure (`absence_checks` entry, result `absent`), AWS
and Docker sourced from job adverts, Kubernetes named in an architecture blog
post from this year, careers page open with three product engineering roles and
no infrastructure role, a status page with two multi-hour incidents in the last
quarter, named CTO with an address published on the site, Series A last year.

| Component | Points | Why |
|---|---|---|
| Company fit | 19 | 14 engineers, product company, zero infra counted on a page that was read |
| Operational load | 19 | Kubernetes in production with nobody hired to operate it |
| Capacity gap | 19 | Three open engineering roles, none infrastructure |
| Pain evidence | 17 | Two dated multi-hour incidents on their own status page |
| Decision maker | 9 | CTO of a 22-person company, address published |
| Commercial potential | 9 | Series A, small enough for one person to say yes |

`fit_score` 47, `research_score` 36, `decision_maker_score` 9, total **92** ->
`HOT`, offer `infrastructure_audit`.

## Worked example - what the old rubric loved

The same research the old rubric scored 75. A 60-person company, AWS and Docker
from job adverts, an open **Senior DevOps Engineer** posted 71 days ago naming
Kubernetes as a migration in progress, a four-hour outage written up eight
months ago, named VP Engineering with a guessed address, Series A.

| Component | Points | Why |
|---|---|---|
| Company fit | 14 | 60 engineers, but infra ownership never established - `null`, not `0` |
| Operational load | 10 | Cloud and Docker sourced; ownership unclear, so no top band |
| Capacity gap | 1 | Infrastructure role open 71 days - the 60-120 day band |
| Pain evidence | 6 | The outage is real but eight months old and undated since |
| Decision maker | 6 | VP Engineering named, email guessed, 60-person company |
| Commercial potential | 7 | Series A |

Total **44** -> `NURTURE`. No email.

This is the correct outcome and the point of the inversion. They are hiring the
person being sold. In two months the role is either filled - in which case they
are a competitor's problem - or still open, at which point the 120-day band
moves them back up and the timing is finally right.

---

# Automation line

Everything above scores a company as an **infrastructure** prospect. WF-04 also
scores every company a second time, against the rubric below, as a prospect
for **business process automation** (`agents/offers.json`, line
`automation`), and keeps whichever line scores higher. Same research, same
six components, same JSON keys, same bands and the same 0-100 scale, so the
two totals are comparable. Only what each component measures changes.

## Automation rubric

The buyer is a business whose **repetitive work grows with it and is done by
people**: orders re-keyed from the shop into the ERP, shipment statuses copied
from carrier portals into client emails, the same client report assembled by
hand every Monday. E-commerce, logistics, agencies, and tech companies with a
back office all qualify; the industry alone never does.

A company with an automation, RevOps, business systems or internal tools team
is not a prospect, and neither is one that posted such a role in the last 60
days. That is the same inversion as the infrastructure rubric: they have
decided to solve it themselves.

| Component | Max | JSON key | What it measures |
|---|---|---|---|
| Company fit | 20 | `company_fit` | Big enough to have volume, small enough that one person buys |
| Process load | 20 | `technology_fit` | How much repetitive work there is, and across how many systems |
| Capacity gap | 20 | `hiring_signal` | People being hired to do that work by hand |
| Pain evidence | 20 | `pain_evidence` | Whether the manual work is already hurting |
| Decision maker | 10 | `decision_maker` | Reachable, and senior enough to decide alone |
| Commercial potential | 10 | `commercial_potential` | Can pay for a process audit |

### Company fit (20)

| Points | Condition |
|---|---|
| 18-20 | 15-200 people, an operating business with visible volume (orders, shipments, clients, transactions) |
| 13-17 | 10-300 people, volume-driven, size or volume only partly established |
| 7-12 | Size unknown, or volume unclear |
| 1-6 | Under 10 people, or pre-revenue |
| 0 | A competitor (automation, integration or RPA agency), an existing client, suppressed, or a visible automation / internal tools team |

### Process load (20) - JSON key `technology_fit`

| Points | Condition |
|---|---|
| 18-20 | Several named systems that have to agree (`tool_sprawl`) **and** a stated high-volume manual step (`manual_process` or `volume_growth`), both sourced |
| 13-17 | One clearly stated manual process, or re-keying between two named systems |
| 8-12 | A volume-driven business with named systems, no manual step stated |
| 3-7 | Generic operations, nothing specific |
| 0 | No evidence of repetitive work at all |

### Capacity gap (20) - JSON key `hiring_signal`

| Points | Condition |
|---|---|
| 18-20 | Two or more open roles whose job is repetitive back-office work (`hiring_manual_ops`), and no automation role |
| 13-17 | One such role open, or an automation role open more than 120 days |
| 8-12 | Operations headcount growing, careers page not readable |
| 3-7 | No hiring activity either way |
| 0 | An automation, RevOps, business systems or internal tools role posted within 60 days |

Paying a salary for work a system could do is the buying moment. An
"Order Processing Specialist" advert is to this rubric what four product
engineers and no platform engineer are to the infrastructure one.

### Pain evidence (20)

| Points | Condition |
|---|---|
| 18-20 | The company says it publicly and datedly: backlog, errors, delays, "manually" |
| 13-17 | A job advert describing the repetitive work in detail - copying, reconciling, updating spreadsheets |
| 8-12 | Structural: several systems and stated volume, no stated pain |
| 3-7 | Weak or undated indications |
| 0 | None |

### Decision maker (10)

Same as above, but the right person is different: founder, CEO, COO, Head of
Operations or managing director of a company under 200 people. A CTO counts,
one band lower. WF-04 sets this from the people table, not from the model.

### Commercial potential (10)

| Points | Condition |
|---|---|
| 9-10 | Profitable or funded, owner-led or small enough that an audit is one person's decision |
| 6-8 | Can plausibly afford an audit and a follow-on build |
| 3-5 | Could afford a one-off audit only |
| 0 | Pre-revenue with no funding |

### Hard overrides (automation)

- Suppressed domain, existing client, research confidence below 0.3, more than
  400 people: as above.
- Sells automation, integration or RPA services -> `IGNORE`.
- **No automation-line signal at all** (`hiring_manual_ops`, `manual_process`,
  `tool_sprawl`, `volume_growth`) -> `IGNORE`. There is nothing to audit.
- **An automation role posted within 60 days** -> cap the total at 59.

The offer on this line is always `process_audit`.

## Automation system prompt

```
You are scoring a company as a prospect for business process automation: a
consultancy that finds repetitive work people do by hand and builds systems
that do it instead.

The consultancy sells to businesses whose repetitive work - orders, shipments,
invoices, client reports, data moved between systems - grows with them and is
done by people. A company with an automation, RevOps or internal tools team,
or one that posted such a role in the last 60 days, is NOT a prospect: it has
already decided to solve this itself.

Apply the automation rubric in this document literally. Award points only for
evidence present in the supplied research output. The industry alone is never
evidence: a logistics company is not a manual process until something you were
given says one exists.

Absent evidence scores zero, never "average". A score that is too generous is
more expensive than one that is too harsh, because it produces an email to a
company that did not need one.

Return valid JSON only, no prose, no markdown fences:

{
  "company_fit": { "points": 0, "reason": "" },
  "technology_fit": { "points": 0, "reason": "" },
  "hiring_signal": { "points": 0, "reason": "" },
  "pain_evidence": { "points": 0, "reason": "" },
  "decision_maker": { "points": 0, "reason": "" },
  "commercial_potential": { "points": 0, "reason": "" },
  "fit_score": 0,
  "research_score": 0,
  "decision_maker_score": 0,
  "total_score": 0,
  "band": "",
  "recommended_offer": "process_audit",
  "reason": "",
  "overrides_applied": []
}

The keys `technology_fit` and `hiring_signal` carry Process load and Capacity
gap on this line - score them by the rubric text, not by the key.

`reason` is one sentence, written for a human deciding whether to approve an
email. It must name the specific evidence, not the score.
```
