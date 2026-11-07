-- 0020_osm_snapshot.sql
-- The last good OpenStreetMap response per country, for WF-01.
--
-- The public Overpass instance is unreliable: on 2026-09-24 at 06:10 it
-- refused every connection, and an hour later it answered 504. The data it
-- serves changes slowly, and discovery_seen already remembers every candidate
-- decided on, so a response from last week is as good as today's. WF-01 stores
-- each successful response here and falls back to it when a fetch fails.
CREATE TABLE osm_snapshot (
    country     text PRIMARY KEY CHECK (country ~ '^[A-Z]{2}$'),
    payload     text NOT NULL,
    elements    integer NOT NULL CHECK (elements >= 0),
    fetched_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE osm_snapshot IS
    'Last successful Overpass response per country (WF-01). Map data (c) '
    'OpenStreetMap contributors, ODbL; used internally, never republished.';
