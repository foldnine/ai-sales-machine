-- 0025: discovery allocated by ICP segment, not by source.
--
-- On 2026-09-29 the table held 204 infra_startups against 49 accounting
-- offices, 37 webshops, 27 agencies and 25 logistics firms. That is not a
-- decision anybody made: HN and YC were the first sources, and after them the
-- daily quota was per source (DISCOVERY_OSM_DAILY_SHARE), so inside
-- OpenStreetMap whichever category weighed most took the slots. An experiment
-- between segments needs each segment fed on purpose.
--
-- discovery_share is each segment's percentage of DISCOVERY_DAILY_LIMIT. WF-01
-- takes every segment's share first, then fills whatever a segment could not
-- use (its candidates ran out) from the rest by priority, so the daily limit is
-- still reached. Moving budget to the segment that answers is an UPDATE on this
-- column; v_segment_results is what it is decided from.
ALTER TABLE icp_segments
    ADD COLUMN discovery_share smallint NOT NULL DEFAULT 0
        CHECK (discovery_share BETWEEN 0 AND 100);

-- Shares follow supply as measured on 2026-09-29: the region's map holds about
-- 14,000 shops with a website against 210 accounting offices, 104 logistics
-- firms and 58 agencies in total, most of them already discovered. A segment
-- whose candidates run out gives its slots to the others the same day.
UPDATE icp_segments SET discovery_share = CASE code
    WHEN 'webshops'           THEN 45
    WHEN 'infra_startups'     THEN 15
    WHEN 'accounting_offices' THEN 10
    WHEN 'logistics'          THEN 10
    WHEN 'agencies'           THEN 10
    ELSE 0 END;

COMMENT ON COLUMN icp_segments.discovery_share IS
    'Percent of DISCOVERY_DAILY_LIMIT this segment gets first in WF-01; unused slots are filled from the others. See 0025_segment_allocation.sql.';

-- A segment's candidates come from its discovery_share while it has one, even
-- when it takes no outreach: regional_other (office=company and the rest) is
-- read so research can say what those companies actually are.
UPDATE icp_segments SET discovery_share = 10 WHERE code = 'regional_other';

-- What a regional company is, from what research found it does, not from its
-- map tag. Measured on 2026-09-29: OpenStreetMap holds 210 accounting offices,
-- 58 agencies and 104 logistics firms in the whole region, most of them already
-- discovered, while 1,183 businesses are tagged only office=company. And the tag
-- is sometimes wrong where it exists (a DSV depot tagged a local logistics
-- office, a web-design studio tagged an advertising agency).
--
-- Research writes an English company_summary; this reads it together with the
-- company's name, in English and the region's languages. It only ever moves a
-- company to a segment the text positively names. A summary that says nothing
-- (older research often returned just the name) leaves the segment as it was:
-- measured, a rule that also moved "no match" to regional_other took
-- "Markething Digitalna agencija" and "TNT Transport" out of their segments.
-- The outreach model still declines a real mismatch ("segment mismatch").
-- Software companies (not radar_osm) are never touched.
--
-- A text that also names the company's current segment keeps it there. Shops
-- say how they deliver ("ships by courier across Serbia"), so in a plain
-- first-match order a webshop's summary would have filed it under logistics,
-- emptying the segment the first campaign runs on.
CREATE OR REPLACE FUNCTION segment_from_research(p_source text, p_industry text, p_current text, p_text text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_source IS DISTINCT FROM 'radar_osm' OR COALESCE(btrim(p_text), '') = '' THEN p_current
        ELSE COALESCE((
            SELECT v.code
            FROM (VALUES
                (1, 'accounting_offices', '(accounting|bookkeep|payroll|tax advis|tax consult|ra[cč]unovod|knjigovod|porezn|knjigovez|računovodst|сметковод|рачуновод)'),
                (2, 'logistics',          '(logistic|freight|forwarding|courier|haulage|transport|spedi[ct]|warehous|customs brok|prevoz|prijevoz|kurirsk|carinsk|логистик|шпедиц|превоз)'),
                (3, 'agencies',           '(marketing agency|advertising|digital agency|creative agency|media agency|branding|pr agency|marketing services|social media|marketin[gš]k|agencij[ae] za|digitaln[ae] agencij|reklam|оглас|маркетинг)'),
                (4, 'webshops',           '(online shop|online store|webshop|web shop|e-?commerce|sells online|internet shop|web store|online retail|internet prodavnic|internet trgovin|spletna trgovina)')
            ) AS v(ord, code, rx)
            WHERE p_text ~* v.rx
            ORDER BY (v.code = p_current) DESC, v.ord
            LIMIT 1), p_current)
    END;
$$;

COMMENT ON FUNCTION segment_from_research(text, text, text, text) IS
    'The ICP segment of a regional company from its name and research summary; used by WF-02 Store Research. See 0025_segment_allocation.sql.';

-- The companies already researched, once.
UPDATE companies c
SET segment = segment_from_research(c.source, c.industry, c.segment, c.name || '. ' || COALESCE(r.summary, ''))
FROM (
    SELECT DISTINCT ON (company_id) company_id, output #>> '{analysis,company_summary}' AS summary
    FROM agent_runs
    WHERE agent_name = 'research' AND status = 'success'
    ORDER BY company_id, finished_at DESC NULLS LAST
) r
WHERE r.company_id = c.id
  AND c.source = 'radar_osm';
