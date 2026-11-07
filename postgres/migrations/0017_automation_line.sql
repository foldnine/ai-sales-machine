-- 0017_automation_line.sql
-- A second line of business: business process automation.
--
-- Until now every company was judged as an infrastructure prospect and offered
-- one of three infrastructure engagements. The business sells automation
-- too, and the first
-- automation sale is a process audit, the same reasoning that makes the
-- infrastructure audit the default first offer. agents/offers.json is the
-- catalogue; this migration makes the schema accept what it lists.
--
-- Nothing existing changes meaning. Every infrastructure value stays valid and
-- every existing row still satisfies both constraints.

-- 1. The offer. leads.recommended_offer is written by WF-04 from the winning
--    line's offer.
ALTER TABLE leads DROP CONSTRAINT IF EXISTS leads_recommended_offer_check;
ALTER TABLE leads ADD CONSTRAINT leads_recommended_offer_check
    CHECK (recommended_offer IS NULL OR recommended_offer IN (
        'infrastructure_audit',
        'devops_improvement_sprint',
        'fractional_devops_sre',
        'process_audit',
        'none'
    ));

-- 2. What research can observe about a process. The infrastructure signals
--    describe load and who carries it; these describe repetitive work and who
--    does it by hand.
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
    'infra_ownership_gap',
    'hiring_without_infra',
    -- Hiring people whose job is repetitive back-office work: operations
    -- coordinators, data entry, order processing, dispatch, billing. Paying a
    -- salary for the work is the clearest sign it is worth automating.
    'hiring_manual_ops',
    -- A process the company itself describes as manual: spreadsheets,
    -- re-keying between systems, copy-paste, "manually".
    'manual_process',
    -- Several systems named that have to agree with each other: a CRM, an ERP,
    -- a shop, a helpdesk, accounting.
    'tool_sprawl',
    -- Stated growth in orders, shipments, clients or transactions: the manual
    -- work grows with it.
    'volume_growth',
    -- An automation, RevOps, internal tools or business systems role. The
    -- automation analogue of hiring_devops: they are buying the solution.
    'hiring_automation',
    'other'
));

COMMENT ON COLUMN signals.signal_type IS
    'What was observed. infra_ownership_gap and hiring_without_infra are '
    'absence signals and require a recorded absence_check behind them. '
    'hiring_manual_ops, manual_process, tool_sprawl, volume_growth and '
    'hiring_automation belong to the automation line (0017).';
