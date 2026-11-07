-- Minimax's directory as a discovery source (0029), run through WF-01's own
-- Record Candidates (wf01_record). Every block raises on a wrong answer.

-- 1. An office from the directory is an accounting office, whatever research
--    later says about its map category.
DO $$ BEGIN
    IF segment_for('radar_minimax', 'Minimax accounting directory') IS DISTINCT FROM 'accounting_offices' THEN
        RAISE EXCEPTION 'a Minimax office went to %, not accounting_offices',
            segment_for('radar_minimax', 'Minimax accounting directory');
    END IF;
    IF (SELECT discovery_share FROM icp_segments WHERE code = 'accounting_offices') <> 30 THEN
        RAISE EXCEPTION 'accounting_offices does not have the 30%% share 0029 gives it';
    END IF;
END $$;

-- 2. Record Candidates inserts it with its source, and the listing becomes a
--    signal at the confidence the evidence states, not the directory default.
DO $$
DECLARE
    r record;
    cands jsonb := jsonb_build_array(
        jsonb_build_object('source', 'radar_minimax', 'external_id', 'RS/mmx-test-doo',
            'domain', 'mmx-test.example', 'name', 'MMX TEST DOO', 'country', 'RS',
            'industry', 'Minimax accounting directory', 'priority', 195,
            'evidence', jsonb_build_object('url', 'https://www.minimax.rs/sr-latn-rs/spisak-knjigovodstvenih-agencija',
                'confidence', 0.9, 'note', 'Listed in Minimax''s public directory of accounting services (RS).')),
        jsonb_build_object('source', 'radar_osm', 'external_id', 'node/mmx-shop',
            'domain', 'mmx-shop.example', 'name', 'MMX Shop', 'country', 'RS',
            'industry', 'OSM shop=furniture', 'priority', 185,
            'evidence', jsonb_build_object('url', 'https://www.openstreetmap.org/node/1', 'note', 'OpenStreetMap: shop=furniture.')));
BEGIN
    EXECUTE format('EXECUTE wf01_record(%L::jsonb)', jsonb_build_object('daily_limit', 10, 'candidates', cands)) INTO r;
    IF r.companies_inserted <> 2 THEN
        RAISE EXCEPTION 'expected 2 companies, got %', r.companies_inserted;
    END IF;
    IF (SELECT source || '/' || segment FROM companies WHERE domain = 'mmx-test.example')
            IS DISTINCT FROM 'radar_minimax/accounting_offices' THEN
        RAISE EXCEPTION 'the Minimax office was stored as %',
            (SELECT source || '/' || segment FROM companies WHERE domain = 'mmx-test.example');
    END IF;
    IF (SELECT s.confidence FROM signals s JOIN companies c ON c.id = s.company_id
        WHERE c.domain = 'mmx-test.example') <> 0.9 THEN
        RAISE EXCEPTION 'the directory signal did not keep its stated confidence';
    END IF;
    IF (SELECT s.confidence FROM signals s JOIN companies c ON c.id = s.company_id
        WHERE c.domain = 'mmx-shop.example') <> 0.20 THEN
        RAISE EXCEPTION 'a map signal lost the 0.20 default';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM discovery_seen WHERE source = 'radar_minimax' AND external_id = 'RS/mmx-test-doo') THEN
        RAISE EXCEPTION 'the Minimax candidate was not recorded as seen';
    END IF;
END $$;

-- 3. The snapshot table takes one row per directory and country.
INSERT INTO directory_snapshot (source, country, url, entries, elements)
VALUES ('radar_minimax', 'RS', 'https://www.minimax.rs/', '[]', 0);
DO $$ BEGIN
    BEGIN
        INSERT INTO directory_snapshot (source, country, url, entries, elements)
        VALUES ('radar_minimax', 'RS', 'https://www.minimax.rs/', '[]', 0);
        RAISE EXCEPTION 'a second RS row was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
END $$;
DELETE FROM directory_snapshot;
