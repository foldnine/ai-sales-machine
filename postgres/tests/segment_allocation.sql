-- Discovery by ICP segment and segments from research (0025), run through the
-- workflows' own SQL (wf01_record, wf03_claim are prepared by
-- infra/scripts/sql-test.sh from n8n/workflows/). Every block raises on a
-- wrong answer.

-- 1. segment_from_research moves a company only to a segment its text names,
--    and a text that also names its current segment keeps it there.
DO $$ BEGIN
    IF segment_from_research('radar_osm', 'OSM shop=car_parts', 'webshops',
            'Moto Test. Sells car parts through its webshop and ships by courier across Serbia.') <> 'webshops' THEN
        RAISE EXCEPTION 'a webshop that names its courier was moved out of webshops';
    END IF;
    IF segment_from_research('radar_osm', 'OSM office=company', 'regional_other',
            'Knjigovodstvo Test. An accounting and payroll office in Novi Sad.') <> 'accounting_offices' THEN
        RAISE EXCEPTION 'an accounting office tagged office=company was not reclassified';
    END IF;
    IF segment_from_research('radar_osm', 'OSM office=logistics', 'logistics',
            'DSV Test. Online store for garden furniture.') <> 'webshops' THEN
        RAISE EXCEPTION 'a mis-tagged shop stayed in logistics';
    END IF;
    IF segment_from_research('radar_osm', 'OSM office=accountant', 'accounting_offices', 'Test d.o.o.. ') <> 'accounting_offices' THEN
        RAISE EXCEPTION 'a summary that names nothing moved the company';
    END IF;
    IF segment_from_research('radar_yc', NULL, 'infra_startups', 'An e-commerce analytics startup.') <> 'infra_startups' THEN
        RAISE EXCEPTION 'a software company was reclassified';
    END IF;
END $$;

-- 2. WF-01 Record Candidates shares a day of 10 by discovery_share: webshops
--    25% (3), infra_startups 15% (2), accounting_offices 30% (3, since
--    0029), and the slots logistics, agencies and regional_other cannot use
--    go to the best of the rest. Webshops are given the lowest priority on purpose: by priority
--    alone the software companies would take every slot.
DO $$
DECLARE
    cands jsonb := '[]'::jsonb;
    r record;
BEGIN
    FOR i IN 1..20 LOOP
        cands := cands || jsonb_build_object('source', 'radar_osm', 'external_id', 'shop' || i,
            'domain', 'shop' || i || '.example', 'name', 'Shop ' || i, 'country', 'RS',
            'industry', 'OSM shop=electronics', 'priority', 100 + i);
    END LOOP;
    FOR i IN 1..5 LOOP
        cands := cands || jsonb_build_object('source', 'radar_osm', 'external_id', 'acc' || i,
            'domain', 'acc' || i || '.example', 'name', 'Books ' || i, 'country', 'RS',
            'industry', 'OSM office=accountant', 'priority', 200 + i);
    END LOOP;
    FOR i IN 1..10 LOOP
        cands := cands || jsonb_build_object('source', 'radar_yc', 'external_id', 'yc' || i,
            'domain', 'yc' || i || '.example', 'name', 'SaaS ' || i, 'country', 'DE',
            'priority', 500 + i);
    END LOOP;
    EXECUTE format('EXECUTE wf01_record(%L::jsonb)', jsonb_build_object('daily_limit', 10, 'candidates', cands)) INTO r;
    IF r.accepted <> 10 OR r.companies_inserted <> 10 THEN
        RAISE EXCEPTION 'expected 10 accepted, got % (% inserted)', r.accepted, r.companies_inserted;
    END IF;
    IF (SELECT count(*) FROM companies WHERE domain LIKE 'shop%.example') <> 3 THEN
        RAISE EXCEPTION 'webshops got % slots, not their 3', (SELECT count(*) FROM companies WHERE domain LIKE 'shop%.example');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM companies WHERE domain = 'shop20.example') THEN
        RAISE EXCEPTION 'the best webshop was not among the three';
    END IF;
    IF (SELECT count(*) FROM companies WHERE domain LIKE 'acc%.example') <> 3 THEN
        RAISE EXCEPTION 'accounting offices got % slots, not their 3', (SELECT count(*) FROM companies WHERE domain LIKE 'acc%.example');
    END IF;
    IF (SELECT count(*) FROM companies WHERE domain LIKE 'yc%.example') <> 4 THEN
        RAISE EXCEPTION 'infra startups should have 2 slots plus the 2 left over by priority, got %',
            (SELECT count(*) FROM companies WHERE domain LIKE 'yc%.example');
    END IF;
    -- The deferred webshops are not recorded, so they come back tomorrow.
    IF EXISTS (SELECT 1 FROM discovery_seen WHERE external_id = 'shop1') THEN
        RAISE EXCEPTION 'a deferred candidate was recorded as seen';
    END IF;
END $$;

-- 3. WF-03 Claim Companies looks up a contact for a regional company in an
--    active segment well below its bar, ahead of a software company above it,
--    and never for a segment without an offer.
-- An earlier test file can leave a night batch open; it would (rightly) stop
-- every claim.
UPDATE agent_runs SET status = 'error', error = 'closed by test', finished_at = now() WHERE status = 'running';
INSERT INTO companies (id, name, domain, source, industry, country, status, fit_score, research_score) VALUES
    ('00000000-0000-0000-0000-00000000e001', 'Low Shop', 'lowshop.example', 'radar_osm', 'OSM shop=furniture', 'RS', 'scored', 20, 5),
    ('00000000-0000-0000-0000-00000000e002', 'Big SaaS', 'bigsaas.example', 'radar_yc', NULL, 'DE', 'scored', 45, 35),
    ('00000000-0000-0000-0000-00000000e003', 'Low SaaS', 'lowsaas.example', 'radar_yc', NULL, 'DE', 'scored', 25, 5),
    ('00000000-0000-0000-0000-00000000e004', 'Chain Shop', 'chainshop.example', 'radar_osm', 'OSM shop=furniture', 'RS', 'scored', 10, 0);
DO $$
DECLARE
    params jsonb := '{"batch_size": 1, "min_score": 60, "candidate_pool": 15, "retry_days": 30,
                      "domain_cooldown_minutes": 60, "model": "test", "input": {}}';
    r record;
    got text[] := '{}';
BEGIN
    FOR r IN EXECUTE format('EXECUTE wf03_claim(%L::jsonb)', params) LOOP got := got || r.domain; END LOOP;
    IF got <> ARRAY['lowshop.example'] THEN
        RAISE EXCEPTION 'first claim should be the regional shop, got %', got;
    END IF;
    got := '{}';
    FOR r IN EXECUTE format('EXECUTE wf03_claim(%L::jsonb)', jsonb_set(params, '{batch_size}', '5')) LOOP got := got || r.domain; END LOOP;
    IF got <> ARRAY['bigsaas.example'] THEN
        RAISE EXCEPTION 'second claim should be only the software company above its bar, got %', got;
    END IF;
END $$;
