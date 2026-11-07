-- WF-05 Claim Leads (wf05_claim): a role contact at a firm whose own site names
-- its director carries that person as `attention`; a name with no title does
-- not count.
UPDATE agent_runs SET status = 'error', error = 'closed by test', finished_at = now() WHERE status = 'running';

INSERT INTO companies (id, name, domain, source, industry, country, status) VALUES
    ('00000000-0000-0000-0000-00000000a101', 'Named Shop', 'namedshop.example', 'radar_osm', 'OSM shop=hardware', 'RS', 'scored'),
    ('00000000-0000-0000-0000-00000000a102', 'Staff Shop', 'staffshop.example', 'radar_osm', 'OSM shop=hardware', 'RS', 'scored');
INSERT INTO people (id, company_id, full_name, email, email_status, kind, discovery_method, source_url, title) VALUES
    ('00000000-0000-0000-0000-00000000a201', '00000000-0000-0000-0000-00000000a101', NULL, 'info@namedshop.example', 'valid', 'role', 'published_page', 'https://namedshop.example/kontakt', NULL),
    ('00000000-0000-0000-0000-00000000a202', '00000000-0000-0000-0000-00000000a101', 'Petar Petrović', NULL, 'unknown', 'person', 'published_page', 'https://namedshop.example/impressum', 'Direktor'),
    ('00000000-0000-0000-0000-00000000a203', '00000000-0000-0000-0000-00000000a102', NULL, 'info@staffshop.example', 'valid', 'role', 'published_page', 'https://staffshop.example/kontakt', NULL),
    ('00000000-0000-0000-0000-00000000a204', '00000000-0000-0000-0000-00000000a102', 'Ana Anić', NULL, 'unknown', 'person', 'published_page', 'https://staffshop.example/tim', NULL);
INSERT INTO leads (id, company_id, person_id, score, recommended_offer, status) VALUES
    ('55550000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000a101', '00000000-0000-0000-0000-00000000a201', 50, 'process_audit', 'new'),
    ('55550000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000a102', '00000000-0000-0000-0000-00000000a203', 50, 'process_audit', 'new');

DO $$
DECLARE r record; named json; staff json; seen int := 0;
BEGIN
    FOR r IN EXECUTE $q$EXECUTE wf05_claim('{"min_score": 60, "followup_max": 2, "followup_delay_days": 4,
        "window": "night", "regional_countries": ["RS"], "batch_size": 20, "model": "test", "input": {"window": "night"}}')$q$
    LOOP
        IF r.lead_id = '55550000-0000-0000-0000-000000000001' THEN named := r.attention; seen := seen + 1; END IF;
        IF r.lead_id = '55550000-0000-0000-0000-000000000002' THEN staff := r.attention; seen := seen + 1; END IF;
    END LOOP;
    IF seen <> 2 THEN RAISE EXCEPTION 'expected both leads claimed, got %', seen; END IF;
    IF named ->> 'name' IS DISTINCT FROM 'Petar Petrović' OR named ->> 'title' IS DISTINCT FROM 'Direktor' THEN
        RAISE EXCEPTION 'the director was not carried as attention: %', named;
    END IF;
    IF staff IS NOT NULL THEN
        RAISE EXCEPTION 'a name with no title became the attention line: %', staff;
    END IF;
END $$;

UPDATE agent_runs SET status = 'error', error = 'closed by test', finished_at = now() WHERE status = 'running';
DELETE FROM leads WHERE id::text LIKE '5555%';
DELETE FROM people WHERE id::text LIKE '00000000-0000-0000-0000-00000000a2%';
