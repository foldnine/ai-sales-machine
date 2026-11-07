-- One company one email, and country facts (0027), run through the workflows'
-- own SQL (wf01_record, wf05_claim are prepared by infra/scripts/sql-test.sh).
-- Every block raises on a wrong answer.
UPDATE agent_runs SET status = 'error', error = 'closed by test', finished_at = now() WHERE status = 'running';

-- 1. domain_brand.
DO $$
DECLARE
    cases text[][] := ARRAY[
        ['shopbrand.example', 'shopbrand'], ['ba.shopbrand.example', 'shopbrand'], ['www.shopbrand.example', 'shopbrand'],
        ['officebrand-test.com.hr', 'officebrand-test'], ['officebrand.example', 'officebrand'], ['autoparts-test.co.rs', 'autoparts-test'],
        ['ba.appliance.example', 'appliance'], ['b2b.toolshop.example', 'toolshop'], ['localhost', 'localhost']];
    i int;
BEGIN
    FOR i IN 1 .. array_length(cases, 1) LOOP
        IF domain_brand(cases[i][1]) IS DISTINCT FROM cases[i][2] THEN
            RAISE EXCEPTION 'domain_brand(%) = %, expected %', cases[i][1], domain_brand(cases[i][1]), cases[i][2];
        END IF;
    END LOOP;
END $$;

-- 2. SEF is gone from the angles, and every regional country has facts.
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM icp_segments WHERE angle ~ '\mSEF\M') THEN
        RAISE EXCEPTION 'a segment angle still names SEF for every country';
    END IF;
    IF (SELECT count(*) FROM country_facts WHERE country IN ('RS', 'HR', 'SI', 'BA', 'ME', 'MK')) <> 6 THEN
        RAISE EXCEPTION 'a regional country has no country_facts row';
    END IF;
END $$;

-- 3. WF-01: a brand already in the table, or twice in one run, is one company.
INSERT INTO companies (id, name, domain, source, industry, country, status) VALUES
    ('00000000-0000-0000-0000-00000000d001', 'Shop Brand', 'axtest.example', 'radar_osm', 'OSM shop=doityourself', 'HR', 'scored');
DO $$
DECLARE r record;
BEGIN
    EXECUTE format('EXECUTE wf01_record(%L::jsonb)', jsonb_build_object('daily_limit', 10, 'candidates', jsonb_build_array(
        jsonb_build_object('source', 'radar_osm', 'external_id', 'ax-com', 'domain', 'ba.axtest.example', 'name', 'Shop Brand BA',
                           'country', 'BA', 'industry', 'OSM shop=doityourself', 'priority', 160),
        jsonb_build_object('source', 'radar_osm', 'external_id', 'arg-1', 'domain', 'argtest.example', 'name', 'Office Brand',
                           'country', 'HR', 'industry', 'OSM shop=jewelry', 'priority', 160),
        jsonb_build_object('source', 'radar_osm', 'external_id', 'arg-2', 'domain', 'shop.argtest.example', 'name', 'Office Brand',
                           'country', 'HR', 'industry', 'OSM shop=jewelry', 'priority', 155)))) INTO r;
    IF EXISTS (SELECT 1 FROM companies WHERE domain = 'ba.axtest.example') THEN
        RAISE EXCEPTION 'a second domain of a known brand became a company';
    END IF;
    IF (SELECT count(*) FROM companies WHERE domain_brand(domain::text) = 'argtest') <> 1 THEN
        RAISE EXCEPTION 'one brand twice in a run became % companies',
            (SELECT count(*) FROM companies WHERE domain_brand(domain::text) = 'argtest');
    END IF;
END $$;

-- 4. WF-05: two leads of one brand, both eligible: one first message.
INSERT INTO companies (id, name, domain, source, industry, country, status) VALUES
    ('00000000-0000-0000-0000-00000000d002', 'Twin Shop', 'twinshop.example', 'radar_osm', 'OSM shop=hardware', 'HR', 'scored'),
    ('00000000-0000-0000-0000-00000000d003', 'Twin Shop BA', 'ba.twinshop.example', 'radar_osm', 'OSM shop=hardware', 'BA', 'scored');
INSERT INTO people (id, company_id, full_name, email, email_status, kind, discovery_method, source_url) VALUES
    ('00000000-0000-0000-0000-00000000b002', '00000000-0000-0000-0000-00000000d002', NULL, 'info@twinshop.example', 'valid', 'role', 'published_page', 'https://twinshop.example/kontakt'),
    ('00000000-0000-0000-0000-00000000b003', '00000000-0000-0000-0000-00000000d003', NULL, 'info@ba.twinshop.example', 'valid', 'role', 'published_page', 'https://ba.twinshop.example/kontakt');
INSERT INTO leads (id, company_id, person_id, score, recommended_offer, status) VALUES
    ('44440000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-00000000b002', 50, 'process_audit', 'new'),
    ('44440000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000d003', '00000000-0000-0000-0000-00000000b003', 45, 'process_audit', 'new');
DO $$
DECLARE r record; got uuid[] := '{}'; facts text;
BEGIN
    FOR r IN EXECUTE $q$EXECUTE wf05_claim('{"min_score": 60, "followup_max": 2, "followup_delay_days": 4,
        "window": "night", "regional_countries": ["RS", "HR", "BA"], "batch_size": 20, "model": "test", "input": {"window": "night"}}')$q$
    LOOP
        IF r.lead_id::text LIKE '4444%' THEN got := got || r.lead_id; facts := r.country_e_invoicing; END IF;
    END LOOP;
    IF got <> ARRAY['44440000-0000-0000-0000-000000000002'::uuid] THEN
        RAISE EXCEPTION 'expected only the higher-scored twin, got %', got;
    END IF;
    IF facts NOT LIKE '%Fiskalizacija 2.0%' THEN
        RAISE EXCEPTION 'the Croatian lead did not carry its country facts: %', facts;
    END IF;
END $$;

-- Leave nothing claimable for the test files that run after this one.
UPDATE agent_runs SET status = 'error', error = 'closed by test', finished_at = now() WHERE status = 'running';
DELETE FROM leads WHERE id::text LIKE '4444%';
DELETE FROM people WHERE id::text LIKE '00000000-0000-0000-0000-00000000b00%';
