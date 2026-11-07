-- 0016_git_commit_provenance.sql
-- Tell a commit address apart from a published one.
--
-- WF-03 recorded addresses taken from GitHub commit metadata as
-- 'published_page'. They are not: a commit records an address for attribution,
-- not as an invitation to write to it, and docs/security.md rests the
-- legitimate-interest basis on exactly that distinction. Recording both the same
-- way made "where did you get my details" impossible to answer honestly.
--
-- The GitHub route is now off by default (ENRICH_GITHUB_ENABLED=false). This
-- keeps the rows it already wrote, relabelled, so a human can decide what to do
-- with them rather than having that decided by a migration.

ALTER TABLE people DROP CONSTRAINT IF EXISTS people_discovery_method_check;
ALTER TABLE people ADD CONSTRAINT people_discovery_method_check
    CHECK (discovery_method IS NULL OR discovery_method IN (
        'published_page',    -- the address is literally on a page the company publishes
        'git_commit',        -- author metadata of a commit in the company's public repository
        'pattern_inferred',  -- derived from another address observed on the same domain
        'provider',          -- a paid lookup. Nothing does this yet.
        'manual'
    ));

-- WF-03 points source_url at the commit for these rows, which is the only
-- thing that distinguishes them after the fact.
UPDATE people
SET discovery_method = 'git_commit'
WHERE discovery_method = 'published_page'
  AND source_url ~ '^https://(api\.)?github\.com/.+/commits?/';
