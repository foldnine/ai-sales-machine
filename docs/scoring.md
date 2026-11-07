# Lead scoring

The rubric the scoring agent applies is in `prompts/scoring.md`. This document
is the reference for how the score is stored, computed and used.

## What the rubric selects for

A company that **runs production software and has nobody whose job is to run
it**. Not a company with a platform team, and not a company that just posted a
DevOps role - both have already bought the solution.

This was inverted on 2026-09-22. Until then the rubric paid its highest points
for open SRE roles and Kubernetes adoption, which describe a company that
already employs the person being sold. The first email this system ever sent
went to a company scoring 73 on the strength of 23 open infrastructure roles -
precisely the wrong target, correctly scored by the wrong rubric.

The components kept their column names and their JSON keys, because WF-04 and
the `agent_runs` history depend on them. Only what they measure changed.

## 100 points

| Component | Max | JSON key | Stored in |
|---|---|---|---|
| Company fit | 20 | `company_fit` | `companies.fit_score` |
| Operational load | 20 | `technology_fit` | `companies.fit_score` |
| Capacity gap | 20 | `hiring_signal` | `companies.research_score` |
| Pain evidence | 20 | `pain_evidence` | `companies.research_score` |
| Decision maker | 10 | `decision_maker` | `companies.decision_maker_score` |
| Commercial potential | 10 | `commercial_potential` | `companies.fit_score` |

Three stored columns, six components:

```
fit_score            = company_fit + operational_load + commercial_potential   (0-50)
research_score       = capacity_gap + pain_evidence                            (0-40)
decision_maker_score = decision_maker                                          (0-10)
```

`companies.total_score` and `companies.score_band` are **generated columns**.
The agent writes the three components; PostgreSQL computes the total and the
band. They cannot disagree, and a workflow cannot write a band that does not
match its own numbers.

## Absence is the evidence, and it has to be counted

The rubric buys on something not being there, which is the hardest kind of
claim to make honestly. Two fields carry the whole weight:

| Field | Meaning | Scores as |
|---|---|---|
| `infra_people_found: 0` | Counted off a page that was read | The strongest signal in the system |
| `infra_people_found: null` | Nobody looked, or the page was unreadable | Ignorance. Mid band at best. |

They are not interchangeable and a scorer that treats them as equal will send
email to companies it knows nothing about. Every negative claim must have a
matching entry in the research output's `absence_checks` with result `absent`;
one with result `unreadable` is an honest failure and scores nothing.

See `prompts/research.md` for how the research agent is required to record it.

## Bands

| Total | Band | What happens |
|---|---|---|
| 0-39 | `IGNORE` | Nothing further. No enrichment, no draft, no cost. |
| 40-59 | `NURTURE` | Kept. Re-scored in 90 days. No outreach. |
| 60-74 | `OUTREACH` | Enriched, drafted, queued for approval. |
| 75-89 | `HIGH_PRIORITY` | Same, at the top of the approval queue. |
| 90-100 | `HOT` | Same, plus a Telegram notification on reaching the band. |

`OUTREACH_MIN_SCORE` (default 60) is the floor for generating a draft at all.
It is separate from the bands so the threshold can be raised without changing
the rubric.

## Hard overrides

Applied by WF-04 after the model returns, regardless of the total:

| Condition | Effect |
|---|---|
| Domain or email on `suppression_list` | `companies.status = 'suppressed'`, no lead created |
| Sells DevOps/SRE/platform consulting | Forced `IGNORE` |
| Existing or former client | Forced `IGNORE`, handled by a human |
| Research `confidence` below 0.3 | Total capped at 39 until re-researched |
| No contactable person | A lead may exist but cannot reach `OUTREACH` |
| `runs_production` is false | Forced `IGNORE` - nothing to operate |
| A named platform / SRE / infrastructure team | Forced `IGNORE` - they employ the person being sold |
| An infrastructure role posted within 60 days | Total capped at 59 - they are hiring the solution |

The last three came with the inversion. The 60-day cap is a cap and not an
`IGNORE` on purpose: the company is a genuine prospect on a delay, and when the
role passes 120 days unfilled the capacity-gap band moves it back up on its own.

## The guards, which are code rather than instructions

The rubric is a prompt, and a local model will not obey a prompt reliably. The
rules that are checkable against the database are therefore enforced in WF-04's
`Validate And Guard` node, every cap is recorded on the run, and a score can be
explained afterwards without rerunning anything.

| Guard | Effect |
|---|---|
| No technology with a source | Operational load to 0 |
| No signal carries a `source_url` | Pain evidence capped at 12 |
| `infra_people_found` is 0 with no `absence_check` returning `absent` | Discarded, treated as null |
| `infra_people_found` is not the integer 0 | Company fit capped at 17, operational load at 12 |
| `employee_count` above 150 | Company fit capped at 12 |
| `employee_count` above 400 | Total capped at 39 |
| Infrastructure role posted within 60 days, or undated | Capacity gap to 0, total capped at 59 |
| Infrastructure role open 60-120 days | Capacity gap capped at 2 |
| Infrastructure role open past 120 days | Capacity gap capped at 17 |
| Fewer than two open non-infrastructure roles | Capacity gap capped at 12, or 7 with none |
| `infra_people_found` greater than 0 | Total capped at 39 |
| `runs_production` is false | Total capped at 39 |
| Decision maker | Replaced outright from the `people` table, not capped |

**A counted zero is derived, not believed.** Asked about Monzo - a bank with a
large platform organisation - the research model wrote two `absence_checks`
entries both saying `unreadable`, meaning it could not open a team page at all,
and then wrote `infra_people_found: 0` anyway. The prompt says in as many words
to write null in that case. So the guard recomputes it: a counted zero requires
at least one check that actually came back `absent`, and without one the answer
is null. Only that direction is enforced - a non-zero count can stand
unverified, because it can only lower the score.

**An undated infrastructure role is treated as recent.** There is no evidence
for either reading, and of the two the one that costs something is sending the
email. The company keeps its `NURTURE` band and comes back when the posting
acquires a date or passes 120 days.

Until 2026-09-22 this node held the opposite rule - capacity gap was capped at
17 *unless* a senior infrastructure role had been posted within 60 days. The
prose inverted first and the guard did not, which would have left the inversion
cosmetic: the top band withheld from every company that qualifies for it, and
reserved for the ones that no longer do.

## Calibration

The rubric is only useful if it separates. Three failure modes, the first two
visible in one query:

```sql
SELECT score_band, count(*), round(avg(total_score)) AS avg
FROM companies
WHERE score_band <> 'UNSCORED'
GROUP BY score_band ORDER BY avg;
```

**Everything clusters at 60-75.** The model is scoring absent evidence as
average instead of zero. Re-read the "absent evidence scores zero" instruction
and check the worked example still produces 92.

**Nothing scores above 50.** Either discovery is feeding the wrong companies,
or research is not finding material that exists. Check `agent_runs` for
research runs with empty `sources` before touching the rubric.

**The third is specific to the inversion** and no distribution will show it:

```sql
SELECT count(*) FILTER (WHERE (payload -> 'infra_people_found') = 'null'::jsonb) AS unknown,
       count(*) FILTER (WHERE (payload ->> 'infra_people_found') = '0')          AS counted_zero
FROM agent_runs
WHERE agent_name = 'research' AND status = 'success'
  AND created_at > now() - interval '30 days';
```

If `counted_zero` stays near zero while scores rise, the scorer has started
reading `null` as `0` and is buying on ignorance. That is the one calibration
error this rubric can make that looks like success from every other angle.

The number that matters is not the average score. It is the proportion of
`OUTREACH` and above that a human actually approves. If approvals run below
about half, the scoring is too generous no matter what the distribution looks
like.

## Re-scoring

A nightly sweep re-scores companies whose evidence changed: a new signal, a new
contact, or research older than 90 days. Scores go down as often as up - and
under this rubric they go down for a reason that did not exist before: a
company that has since hired a platform engineer has stopped being a prospect,
and nothing else in the system will notice if the sweep does not run.

## Two lines

Since migration 0017 every company is scored twice: once against the
infrastructure rubric above, and once against the automation rubric at the end
of `prompts/scoring.md` (`agents/offers.json`, line `automation`). WF-04 sends
both requests, applies each line's own guards, and keeps the higher total. A
tie goes to infrastructure.

Both rubrics use the same six components, JSON keys, bands and 0-100 scale, so
the totals compare directly. On the automation line `technology_fit` carries
*process load* and `hiring_signal` carries *capacity gap* - people being hired
to do repetitive work by hand.

The automation line has its own guards, mirroring the infrastructure ones:

| Guard | Automation line |
|---|---|
| No evidence | No `hiring_manual_ops`, `manual_process`, `tool_sprawl` or `volume_growth` signal: process load 0, forced to `IGNORE` |
| They are buying it | An automation, RevOps, business systems or internal tools role within 60 days: capacity gap 0, total capped at 59 |
| Unfilled need | Such a role open past 120 days: capacity gap up to 17 |
| Competitor | Sells automation, integration or RPA services: `IGNORE` |
| Size | Company fit capped at 12 above 300 people; `IGNORE` above 400 |
| Decision maker | Founder, CEO, COO, head of operations or managing director count, as well as the CTO |

The infrastructure guards (counted absence, `runs_production`, infrastructure
roles) apply to the infrastructure line only. Companies researched before 0017
carry no automation-line signals, so they stay on the infrastructure line until
they are re-researched.

The lead's `recommended_offer` comes from the winning line: `process_audit` on
automation; on infrastructure, research's offer as before, or the
infrastructure audit if research picked an automation offer. `agent_runs`
records both lines' totals in `notes` and `line_scores`.
