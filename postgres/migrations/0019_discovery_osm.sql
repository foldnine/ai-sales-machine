-- 0019_discovery_osm.sql
-- A third discovery source: OpenStreetMap.
--
-- The automation line sells to agencies, logistics and e-commerce in the
-- region, and neither the YC directory nor Hacker News lists them. OSM does:
-- businesses that put their website on the map, by category and country.
-- docs/lead-discovery.md records the sources that were checked and rejected
-- first, and why this one's licence (ODbL) permits internal use.
--
-- Numbered 0019, not 0018: 0018 is proposed separately (/add) and the two are
-- independent. migrate.sh applies pending files in name order, gaps included.

ALTER TABLE discovery_seen DROP CONSTRAINT IF EXISTS discovery_seen_source_check;
ALTER TABLE discovery_seen ADD CONSTRAINT discovery_seen_source_check
    CHECK (source IN ('radar_yc', 'radar_hn', 'radar_osm'));

ALTER TABLE companies DROP CONSTRAINT IF EXISTS companies_source_check;
ALTER TABLE companies ADD CONSTRAINT companies_source_check
    CHECK (source IN (
        'manual', 'apollo', 'radar_github', 'radar_jobs', 'radar_blog',
        'radar_funding', 'referral', 'import', 'radar_yc', 'radar_hn',
        'radar_osm'
    ));
