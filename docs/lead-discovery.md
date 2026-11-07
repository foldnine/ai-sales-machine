# WF-01 Lead Discovery

Finds candidate companies. Does not research them, does not score them, does
not decide whether anyone should be emailed. It decides one thing: what is
worth paying a research model to look at.

Until it existed the funnel starved. Companies were inserted by hand, which
meant the pipeline could only ever be as busy as the person it was built to
replace.

Artifact: `n8n/workflows/ai-sales-lead-discovery.json`

```
Daily at 06:10
  -> Fetch YC Directory        (~10MB, read as text)
  -> Fetch HN Index            (the whoishiring account's recent stories)
  -> Pick HN Thread            (the one actually titled "Who is hiring?")
  -> Fetch HN Thread           (258 top-level comments)
  -> OSM Snapshot              (map data WF-12 saved; no network here)
  -> Select Candidates         (the filters below)
  -> Record Candidates         (insert, defer, and remember what was decided)
  -> Queue Discovery Alert     (one batched line)
```

## What it is looking for, which is the opposite of what it used to be

The buyer runs production software and has nobody whose job is to run it. So a
company advertising for a DevOps engineer is **rejected**, not ranked highly:
it has diagnosed the problem itself, has a salary approved, and will fill the
role. See `docs/scoring.md` for the same inversion applied to scoring.

## Two sources, no API key (and a third, below)

There is no `APOLLO_API_KEY` and no budget for one. Both sources below are
public, free, unauthenticated, and - this is the part that made them worth
using rather than merely affordable - they carry the specific signal this
rubric needs.

**Y Combinator company directory** (`yc-oss.github.io/api`, ~6,200 companies,
rebuilt daily). Carries `team_size` as an integer, which is the field that
decides everything: a 15-person company does not have a platform team, and
nothing else in the record needs checking to know that.

**Hacker News "Ask HN: Who is hiring?"** (Algolia API, monthly, ~258 listings).
Each top-level comment is one company listing its open roles, which means the
roles it does **not** list are readable. A company advertising three product
engineering positions and no infrastructure position is adding operational load
every month and nobody to carry it. That is the buying moment, stated publicly
by the company itself, for free.

## A third source, for the automation line: OpenStreetMap

YC and Hacker News list software companies. The automation line sells to
agencies, logistics and e-commerce in the region, and those are on the map:
OpenStreetMap records businesses by category, many with their website.

Checked on 2026-09-23 before choosing it:

| Source | Why not |
|---|---|
| Arbeitnow job API | Terms forbid using the materials "for any commercial purpose" |
| Himalayas job API | Attribution required; no company domain in the data |
| Wikidata (CC0) | 491 European e-commerce companies with a site, only 23 with a stated size of 10-200: mostly large firms |
| Clutch and similar directories | Terms forbid scraping |
| Business registers (APR) | No domains |

OpenStreetMap's licence (ODbL) permits this: the data is used internally and
never republished, and share-alike applies only to a database made public.
One query for all six countries timed out; one per country takes 10-60 s.

WF-01 never asks Overpass itself. It reads `osm_snapshot`.

### Geofabrik, not Overpass

Since the morning of 2026-09-24 the public Overpass instance has refused this
IP on every backend and port, so `osm_snapshot` stayed empty and not one
OpenStreetMap company reached WF-01. Geofabrik publishes the same map as one
file per country, updated daily, as a plain download.

`make osm-refresh` (`infra/scripts/osm-extract.sh`) downloads each country in
`DISCOVERY_OSM_COUNTRIES` into `tmp/osm/` (only when Geofabrik has a newer
file), keeps the offices and shops that list a website with `osmium`, and
saves them to `osm_snapshot` in the shape Overpass answered in, so WF-01 reads
them unchanged. It needs `brew install osmium-tool` on the host. Measured on
2026-09-24, all six countries, first download included:

| | RS | HR | SI | BA | MK | ME | Total |
|---|---|---|---|---|---|---|---|
| Download (MB) | 229 | 193 | 305 | 160 | 29 | 33 | 949 |
| Offices and shops with a website | 7,581 | 5,310 | 4,253 | 1,809 | 619 | 480 | 20,052 |
| WF-01 candidates | 1,579 | 1,039 | 1,036 | 428 | 139 | 105 | **4,326** |

Two minutes in all, practically the 4,374 the Overpass query gave the day
before. About half the Serbian records carry an `email` tag as well; WF-01 does
not read it yet.

Cron runs it weekly (`docs/setup.md`), which keeps every snapshot younger
than `DISCOVERY_OSM_REFRESH_DAYS`, so **WF-12 OSM Refresh** only acts as the
fallback it describes: daily at 05:20 it fetches the countries whose snapshot is
missing or older than `DISCOVERY_OSM_REFRESH_DAYS` (7), at most
`DISCOVERY_OSM_REFRESH_PER_DAY` (3), one at a time with a pause between them.
That is about six whole-country queries a week. A failed country saves nothing,
stays due, and is asked again the next morning, while WF-01 keeps using its
last snapshot.

It used to fetch all six every morning, with five retries each. On 2026-09-24
the public instance refused connections from this IP on every backend and port,
after a day of those plus manual test runs; the map changes too slowly for
daily queries to have bought anything. A country with no snapshot yet is simply
absent from that day's candidates (origin `none` in the run's stats).

The filter, measured against the region on 2026-09-23 (16,823 map points,
9,257 distinct domains):

| | |
|---|---|
| No company website (social profile, marketplace, site builder) | -370 |
| Chain: the domain on more than 3 map points | -403 |
| Category outside the allowlist (bookmakers, supermarkets, fuel, bakeries...) | -4,480 |
| **Candidates** | **4,374** (RS 1,596, HR 1,048, SI 1,046, BA 435, MK 143, ME 106) |

Categories are an allowlist of businesses whose work is orders, stock,
shipments or clients: logistics, couriers and advertising agencies first, then
shops that sell things that ship, then `office=company`. Since 2026-09-29 the day's slots are shared by ICP segment, not by source:
each active segment in `icp_segments` gets its `discovery_share` of
`DISCOVERY_DAILY_LIMIT` first (webshops 45%, infra startups 15%, accounting
offices, logistics, agencies and `regional_other` 10% each), and slots a
segment cannot fill go to the best remaining candidates of the others
(`0025_segment_allocation.sql`). The shares follow supply: the region's map
holds about 14,000 shops with a website against 210 accounting offices, 104
logistics firms and 58 agencies. `regional_other` (mostly `office=company`)
takes no outreach; research reads those companies and
`segment_from_research` files them by what they actually do. With the share at 30 the region lasts about five months. It was 10 of
25 until the first snapshot existed; Hacker News and YC had filled the rest
with companies scoring rejected two times in three.

Map data (c) OpenStreetMap contributors, available under the ODbL.

## A fourth source, for accounting offices: Minimax's directory

Added 2026-10-02 (`0029_minimax_directory.sql`), because the accounting-office
segment answered early and OpenStreetMap cannot feed it: the six countries'
extracts hold 232 accounting offices, 60 with a website, and 49 were already
in `companies`.

Minimax, the bookkeeping program most of the region's small offices use,
publishes the offices that use it so entrepreneurs can find a bookkeeper:

| Country | Page | Offices | With a domain |
|---|---|---|---|
| SI | minimax.si/sl-si/seznam-racunovodskih-servisov | 572 | 264 |
| RS | minimax.rs/sr-latn-rs/spisak-knjigovodstvenih-agencija | 464 | 94 |
| HR | minimax.hr/hr-hr/popis-racunovodstvenih-servisa | 541 | 77 |

The domain is the office's website, or its email's own domain; an office with
only a free mailbox (gmail.com, siol.net, eunet.rs and the rest) has nothing to
research and is left out. That is most of Serbia's list.

`make minimax-refresh` (`infra/scripts/minimax-directory.sh`) fetches the three
pages, parses them (`minimax-directory.py`) and saves `directory_snapshot`; a
page that parses to fewer than 50 offices leaves the last snapshot as it was.
WF-01's `Directory Snapshot` node reads it. Candidates are `radar_minimax`,
segment `accounting_offices`, and the listing is a signal at confidence 0.9:
it is a sourced fact about the office (it works in Minimax), which is what the
segment email opens with. The angle tells the model never to imply a Minimax
partnership.

Nothing ran `make minimax-refresh` for the first three weeks: on 2026-10-25
`directory_snapshot` was empty and the segment had gained no company since the
map's 51. So the refresh no longer depends on someone remembering it.
`make deploy` refreshes any country missing or older than a week, a weekly
cron entry keeps it current between deploys (`docs/setup.md`), and
`make health` warns while the snapshot is empty or more than 14 days old.

The same migration moves the budget: accounting offices 30% of the daily
limit (was 10%), webshops 25% (was 45%), so the directory is read in about two
weeks.

## The perishable source goes first

The one ordering decision in this workflow that matters.

The YC directory is permanent: a company deferred today is still there next
week. The HN thread is a one-month window replaced on the first of the month,
so a listing not taken now is not deferred - it is **lost**.

The first version scored HN candidates below every hiring YC company. At 25
companies a day it would have taken about three weeks to reach them, by which
time the thread they came from no longer existed. HN candidates now carry
priority 200, above every YC candidate, and each month's thread is consumed in
about four days before YC resumes filling the rest.

## The funnel, measured

Against the real directories on 2026-09-22:

| Y Combinator | |
|---|---|
| In the directory | 6,245 |
| Not `Active` | -1,923 |
| Team size outside 10-120 | -2,805 |
| Batch older than 8 years | -198 |
| Sells infrastructure tooling | -93 |
| Nonprofit | -24 |
| No usable domain | -7 |
| **Candidates** | **1,195** |

| Hacker News, September 2026 | |
|---|---|
| Top-level listings | 258 |
| Hiring an infrastructure role | -33 |
| Sells or operates infrastructure tooling | -16 |
| No engineering role at all | -89 |
| No usable domain (ATS links, shorteners) | -35 |
| **Candidates** | **85** |

The size band is the crudest filter and the most load-bearing. Below 10 there
is no production infrastructure worth auditing; above 120 there is a platform
team and the person being sold to is already employed. YC reports whole-company
headcount, so the engineering team inside those numbers is considerably smaller.

## Discovery is deliberately slower than the sources

`DISCOVERY_DAILY_LIMIT` (25) is the throttle on the whole pipeline. The sources
hold over a thousand qualifying companies; a local research model reads about
ten an hour. Raising the limit does not produce more email - `OUTREACH_DAILY_LIMIT`
does that - it only produces a longer research backlog.

**Deferred candidates are deliberately not recorded.** `discovery_seen` holds
every candidate a run *decided* about, accepted or rejected, and the surplus is
left out of it entirely. Its absence from that table is the only thing that
brings it back tomorrow. Recording the whole pool on the first run would have
discovered 25 companies and silently discarded the other 1,255.

## What `discovery_seen` is for

A rejected candidate is not a company row - there is nothing to insert - so the
rejection has nowhere else to live. Without it, a daily re-read of the same
6,000-row directory re-evaluates every company it has already turned down,
every morning, forever.

It also makes the filters tunable, because the reasons are counted rather than
guessed at:

```sql
SELECT source, coalesce(rejected, '(accepted)') AS outcome, count(*)
FROM discovery_seen GROUP BY 1, 2 ORDER BY 1, 2;
```

## What it cannot do, and where that is handled

**A company that never says what it sells.** Better Stack was discovered on the
first live run. It sells uptime monitoring and incident management - it employs
the SREs this system exists to replace, and is adjacent to a competitor. Its
entire Hacker News post says "we are engineers, making the tools we always
wanted" and names no product. No text filter reaches that.

This is correct layering rather than a defect. WF-02 fetches the company's own
site, WF-04 applies the competitor override, and the company is forced to
`IGNORE` one stage later at the cost of a single research run. WF-01 is a cheap
pre-filter and should not be asked to be the scorer.

**Size, for anything from Hacker News.** The listings carry no headcount, so
`employee_count` is null and company fit is decided downstream.

## Two corrections the first live run produced

Both were found by reading what actually landed in `companies`, not by
reasoning about the code.

**`careers.snowflake.com` became a company.** A recruiting subdomain is not a
company, and the row would have been researched as though it were distinct from
`snowflake.com`. Hosts beginning `careers.`, `jobs.`, `apply.`, `join.` and
six others now have that label stripped before the domain is taken.

**Infrastructure vendors passed through the HN branch.** The YC branch tested
`one_liner` and tags against a vendor pattern; the HN branch tested nothing.
`rootly.com`, `coder.com`, `victoriametrics.com` and `astronomer.io` were all
discovered. A narrower pattern - product phrases only, never a word that
appears in ordinary prose - now runs against the whole post and removes 16 of
258. It deliberately also rejects a company that merely mentions an on-call
rotation: having one is evidence of the infrastructure practice this system
exists to supply.

## Verified

| Case | Result |
|---|---|
| YC filter against the live directory | 1,195 of 6,245, funnel above |
| HN filter against the September thread | 85 of 258, funnel above |
| `Pick HN Thread` with "Who wants to be hired?" newest | picks "Who is hiring?" |
| No "Who is hiring?" thread at all | `story_id` null, item 0 404s, YC-only run |
| Second run, same payload | takes the **next** 25, not the same 25 |
| Domain on `suppression_list` | recorded `suppressed`, not inserted |
| Domain already in `companies` | recorded `already_known`, not inserted |
| Daily limit of 3 against 5 candidates | 3 inserted, 5 recorded, 2 deferred |

And live, through the real schedule trigger, twice: 41 companies discovered
from the September thread in 3.7 seconds a run, each with a `signals` row
citing the comment it came from, and one batched Telegram notification per day.

WF-02 claimed the first four for research without being asked.
