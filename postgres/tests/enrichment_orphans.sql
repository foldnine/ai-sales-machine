-- WF-03 Claim Companies (wf03_claim, prepared by infra/scripts/sql-test.sh):
-- a company left at 'enriching' with no live run goes back to 'scored', and a
-- site that failed three times is not claimed again.
UPDATE agent_runs SET status = 'error', error = 'closed by test', finished_at = now() WHERE status = 'running';

INSERT INTO companies (id, name, domain, source, industry, country, status, fit_score, research_score) VALUES
    ('00000000-0000-0000-0000-00000000f001', 'Stuck Shop', 'stuckshop.example', 'radar_osm', 'OSM shop=furniture', 'SI', 'enriching', 20, 10),
    ('00000000-0000-0000-0000-00000000f002', 'Fresh Shop', 'freshshop.example', 'radar_osm', 'OSM shop=furniture', 'SI', 'enriching', 20, 10),
    ('00000000-0000-0000-0000-00000000f003', 'Broken Shop', 'brokenshop.example', 'radar_osm', 'OSM shop=furniture', 'SI', 'scored', 20, 10);
-- updated_at is set by trigger on write, so age the rows after the insert.
ALTER TABLE companies DISABLE TRIGGER USER;
UPDATE companies SET updated_at = now() - interval '5 hours' WHERE domain = 'stuckshop.example';
ALTER TABLE companies ENABLE TRIGGER USER;
INSERT INTO agent_runs (agent_name, company_id, input, status, error, started_at, finished_at)
SELECT 'enrichment', '00000000-0000-0000-0000-00000000f003', '{}', 'error', 'test', now() - interval '1 hour', now()
FROM generate_series(1, 3);

DO $$
DECLARE
    params jsonb := '{"batch_size": 5, "min_score": 60, "candidate_pool": 50, "retry_days": 30,
                      "domain_cooldown_minutes": 60, "model": "test", "input": {}}';
    r record;
    got text[] := '{}';
BEGIN
    FOR r IN EXECUTE format('EXECUTE wf03_claim(%L::jsonb)', params) LOOP got := got || r.domain; END LOOP;
    IF (SELECT status FROM companies WHERE domain = 'stuckshop.example') <> 'scored' THEN
        RAISE EXCEPTION 'an orphaned enriching company was not requeued';
    END IF;
    IF (SELECT status FROM companies WHERE domain = 'freshshop.example') <> 'enriching' THEN
        RAISE EXCEPTION 'a company enriched minutes ago was requeued';
    END IF;
    IF 'brokenshop.example' = ANY (got) THEN
        RAISE EXCEPTION 'a site that failed three times was claimed again';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM agent_runs WHERE company_id = '00000000-0000-0000-0000-00000000f001'
                   AND input ->> 'stage' = 'orphan_sweep') THEN
        RAISE EXCEPTION 'the orphan was not recorded as a failed run';
    END IF;
END $$;

-- Leave nothing claimable for the test files that run after this one.
DELETE FROM agent_runs WHERE company_id IN (SELECT id FROM companies WHERE domain LIKE '%shop.example' AND id::text LIKE '00000000-0000-0000-0000-00000000f%');
DELETE FROM companies WHERE id::text LIKE '00000000-0000-0000-0000-00000000f%';
