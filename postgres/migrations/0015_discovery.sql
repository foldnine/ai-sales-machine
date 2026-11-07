-- 0015_discovery.sql
-- Discovery, and the inversion of what this system considers a good company.
--
-- The buyer is a company with little or no DevOps: it ships software to
-- production, the engineering team is small enough that nobody is a full-time
-- platform person, and the work is being carried part-time by whoever built it.
-- That is the opposite of what the rubric rewarded until now, which paid points
-- for open SRE roles and Kubernetes blog posts. Those describe a company that
-- already employs the person being sold.
--
-- Two consequences reach the schema.

-- 1. Where a company came from. WF-01 reads two free sources; neither is Apollo
--    and neither has an API key, which is why they were chosen. 'radar_jobs'
--    would have covered the HN one loosely, but provenance that says "a job
--    board" cannot be audited later against the thread it actually came from.
ALTER TABLE companies DROP CONSTRAINT companies_source_check;
ALTER TABLE companies ADD CONSTRAINT companies_source_check CHECK (source IN (
    'manual', 'apollo', 'radar_github', 'radar_jobs', 'radar_blog',
    'radar_funding', 'referral', 'import',
    'radar_yc',   -- Y Combinator public company directory
    'radar_hn'    -- Hacker News "Ask HN: Who is hiring?", monthly thread
));

-- 2. The signal that this system now buys on. Every existing signal_type names
--    something a company HAS. The two below name something it does not have,
--    and absence is only a signal when the looking was done and recorded -
--    hence research.absence_checks, see prompts/research.md.
ALTER TABLE signals DROP CONSTRAINT signals_signal_type_check;
ALTER TABLE signals ADD CONSTRAINT signals_signal_type_check CHECK (signal_type IN (
    'hiring_devops',
    'hiring_engineering_growth',
    'kubernetes_adoption',
    'cloud_migration',
    'infrastructure_scaling',
    'reliability_problem',
    'cloud_cost_problem',
    'leadership_change',
    'funding',
    'technology_announcement',
    -- New. Production infrastructure exists and no one owns it full-time.
    'infra_ownership_gap',
    -- New. Hiring engineers, none of them infrastructure. The load grows and
    -- the capacity to carry it does not.
    'hiring_without_infra',
    'other'
));

COMMENT ON COLUMN signals.signal_type IS
    'What was observed. infra_ownership_gap and hiring_without_infra are '
    'absence signals and require a recorded absence_check behind them.';

-- Discovery re-runs daily over the same 6000-row directory. Without this it
-- re-reads every candidate it has already rejected, every day, forever.
-- A rejected candidate is not a company row - there is nothing to insert - so
-- the rejection has to be remembered somewhere of its own.
CREATE TABLE discovery_seen (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    source      text NOT NULL CHECK (source IN ('radar_yc', 'radar_hn')),
    -- Stable per source: the YC slug, or the HN comment id.
    external_id text NOT NULL CHECK (length(btrim(external_id)) > 0),
    domain      citext,
    -- Why it did not become a company. NULL means it did.
    rejected    text,
    seen_at     timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX discovery_seen_key ON discovery_seen (source, external_id);
CREATE INDEX discovery_seen_rejected_idx ON discovery_seen (rejected)
    WHERE rejected IS NOT NULL;

COMMENT ON TABLE discovery_seen IS
    'Every candidate WF-01 has evaluated, accepted or not. Kept so a daily '
    're-read of the same directory is cheap, and so the rejection reasons can '
    'be counted when the filters are tuned.';
