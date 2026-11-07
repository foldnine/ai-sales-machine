-- 0026: campaigns, the paid audit as a stage, and revenue.
--
-- 0024 made the funnel countable up to "won". Three things were still missing
-- to run the first controlled campaign for the Process Automation Audit
-- (agents/offers.json, process_audit, EUR 1,200) and learn from it:
--
-- 1. A campaign. outreach.segment and outreach.variant say which kind of
--    company a draft went to and which CTA it used, but not which experiment it
--    belonged to. When the webshop angle is rewritten, v2's replies must not be
--    counted as v1's. A campaign is a named, dated cohort: one segment, one
--    offer, one process hypothesis, one message variant. WF-05 stamps the
--    segment's active campaign on every first message, and a follow-up keeps
--    the campaign of the message it follows.
-- 2. The audit. The motion is conversation -> call -> paid audit -> proposal ->
--    build. There was no stage for "they bought the audit", which is the first
--    revenue this business expects, so it could only be recorded as "won" and
--    then could not be told apart from a build.
-- 3. Revenue. leads.deal_value_eur is one number that each /stage overwrites,
--    so an audit fee followed by a build proposal lost the fee. The amount now
--    lives on the lead_events row for the stage, and revenue is the latest
--    amount recorded at 'audit' plus the latest at 'closed_won'. The number is
--    what was invoiced: a build started within the credit window is entered net
--    of the audit fee.
--
-- Nothing here is estimated. Every number below counts rows a workflow or
-- the operator wrote; with no rows it is 0, never a projection.
--
-- Rollback (nothing else depends on these objects; run in one transaction):
--   re-run the view definitions from 0024_icp_segments.sql, then
--   DROP VIEW v_campaign_results, v_company_scores;
--   ALTER TABLE outreach DROP COLUMN campaign;
--   ALTER TABLE lead_events DROP COLUMN value_eur;
--   UPDATE leads SET status = 'meeting' WHERE status = 'audit';
--   restore leads_status_check from 0024; DROP TABLE campaigns;
--   DELETE FROM schema_migrations WHERE version = '0026_first_revenue';

-- 1. Campaigns.
CREATE TABLE campaigns (
    code            text PRIMARY KEY CHECK (code ~ '^[a-z0-9][a-z0-9_.-]*$'),
    name            text NOT NULL,
    segment         text NOT NULL REFERENCES icp_segments (code),
    -- An offer code from agents/offers.json. check-offers.py (make validate)
    -- fails when this list and the catalogue disagree.
    offer           text NOT NULL,
    -- The process we suspect, as a short label for the reports. What the email
    -- actually says about it is the segment's angle (icp_segments.angle); this
    -- is not a second copy of that instruction.
    hypothesis      text NOT NULL,
    message_variant text NOT NULL,
    active          boolean NOT NULL DEFAULT true,
    started_at      timestamptz NOT NULL DEFAULT now(),
    ended_at        timestamptz,
    notes           text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT campaigns_offer_check CHECK (offer IN (
        'infrastructure_audit', 'devops_improvement_sprint', 'fractional_devops_sre', 'process_audit'
    )),
    CONSTRAINT campaigns_ended_after_start CHECK (ended_at IS NULL OR ended_at >= started_at)
);

-- One running campaign per segment, so a draft's campaign is never a guess.
-- Starting v2 means ending v1 in the same transaction.
CREATE UNIQUE INDEX campaigns_one_active_per_segment ON campaigns (segment) WHERE active;

COMMENT ON TABLE campaigns IS
    'Named, dated outreach cohorts: segment, offer, process hypothesis, message variant. WF-05 stamps the active one on outreach.campaign. See 0026_first_revenue.sql.';

-- An example first experiment; replace it with your own campaign. The other segments keep
-- running as before and are reported as "no campaign" until one is started.
INSERT INTO campaigns (code, name, segment, offer, hypothesis, message_variant, notes) VALUES
('ecommerce-process-audit-v1',
 'Webshops: order to ERP/fulfilment, question first',
 'webshops',
 'process_audit',
 'order / inventory / fulfilment / customer communication workflow',
 'question-first-v1',
 'Growing webshops often have manual or fragmented steps between the shop, the ERP or accounting '
 'program, the courier and the customer. First message: one sourced fact, the process asked as a '
 'question, the audit in one line. Human approval required; autosend off.');

ALTER TABLE outreach ADD COLUMN campaign text REFERENCES campaigns (code);
CREATE INDEX outreach_campaign_idx ON outreach (campaign) WHERE campaign IS NOT NULL;

-- The campaign a lead's messages belong to: the one its first message
-- recorded, otherwise its segment's running campaign.
CREATE OR REPLACE FUNCTION campaign_for_lead(p_lead_id uuid) RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(
        (SELECT o.campaign FROM outreach o
         WHERE o.lead_id = p_lead_id AND o.sequence_step = 1 AND o.campaign IS NOT NULL),
        (SELECT k.code FROM leads l
         JOIN companies c ON c.id = l.company_id
         JOIN campaigns k ON k.segment = c.segment AND k.active
         WHERE l.id = p_lead_id));
$$;

-- 2. The paid audit as a stage, between the call and the proposal.
ALTER TABLE leads DROP CONSTRAINT leads_status_check;
ALTER TABLE leads ADD CONSTRAINT leads_status_check CHECK (status IN (
    'new', 'pending_approval', 'approved', 'rejected', 'queued', 'contacted',
    'replied', 'opportunity', 'meeting', 'audit', 'proposal', 'nurture',
    'closed_won', 'closed_lost', 'suppressed'
));

-- 3. What each stage change was worth, when the operator gave an amount.
ALTER TABLE lead_events ADD COLUMN value_eur integer CHECK (value_eur IS NULL OR value_eur >= 0);

-- 4. The numbers. The views keep every column 0024 gave them, in order, and
--    add new ones at the end (CREATE OR REPLACE VIEW can only append).
--
--    Stages count as reached "ever, or anything after it": a lead at proposal
--    had its call. The audit is the exception: a lead can go from a call
--    straight to a build proposal, so 'audit' counts only audits recorded.
CREATE OR REPLACE VIEW v_lead_outcomes AS
SELECT
    l.id AS lead_id,
    l.company_id,
    c.segment,
    l.status,
    l.deal_value_eur,
    EXISTS (SELECT 1 FROM outreach o WHERE o.lead_id = l.id AND o.status = 'sent') AS contacted,
    (SELECT min(o.sent_at) FROM outreach o WHERE o.lead_id = l.id AND o.status = 'sent') AS first_sent_at,
    (SELECT count(*) FROM outreach o WHERE o.lead_id = l.id AND o.status = 'sent')::int AS emails_sent,
    (SELECT o.variant FROM outreach o WHERE o.lead_id = l.id AND o.sequence_step = 1 LIMIT 1) AS first_variant,
    EXISTS (SELECT 1 FROM conversations cv JOIN messages m ON m.conversation_id = cv.id
            WHERE cv.lead_id = l.id AND m.direction = 'inbound'
              AND COALESCE(m.classification, '') <> 'OUT_OF_SCOPE') AS replied,
    EXISTS (SELECT 1 FROM conversations cv JOIN messages m ON m.conversation_id = cv.id
            WHERE cv.lead_id = l.id AND m.direction = 'inbound'
              AND m.classification IN ('POSITIVE', 'QUESTION', 'PRICE', 'REFERRAL'))
      OR l.status IN ('opportunity', 'meeting', 'audit', 'proposal', 'closed_won')
      OR EXISTS (SELECT 1 FROM lead_events e WHERE e.lead_id = l.id
                 AND e.stage IN ('opportunity', 'meeting', 'audit', 'proposal', 'closed_won')) AS conversation,
    l.status IN ('meeting', 'audit', 'proposal', 'closed_won')
      OR EXISTS (SELECT 1 FROM lead_events e WHERE e.lead_id = l.id
                 AND e.stage IN ('meeting', 'audit', 'proposal', 'closed_won')) AS meeting,
    l.status IN ('proposal', 'closed_won')
      OR EXISTS (SELECT 1 FROM lead_events e WHERE e.lead_id = l.id
                 AND e.stage IN ('proposal', 'closed_won')) AS proposal,
    l.status = 'closed_won' AS won,
    EXISTS (SELECT 1 FROM people p JOIN suppression_list s ON s.email = p.email
            WHERE p.id = l.person_id AND s.reason = 'hard_bounce')
      OR EXISTS (SELECT 1 FROM people p WHERE p.id = l.person_id AND p.email_status = 'bounced') AS bounced,
    EXISTS (SELECT 1 FROM people p JOIN suppression_list s ON s.email = p.email
            WHERE p.id = l.person_id AND s.reason = 'unsubscribe_request') AS unsubscribed,
    -- Added in 0026.
    (SELECT o.campaign FROM outreach o WHERE o.lead_id = l.id AND o.sequence_step = 1 LIMIT 1) AS campaign,
    l.status = 'audit'
      OR EXISTS (SELECT 1 FROM lead_events e WHERE e.lead_id = l.id AND e.stage = 'audit') AS audit,
    l.status = 'closed_lost' AS lost,
    -- Invoiced: the latest amount given at 'audit', plus the latest at
    -- 'closed_won' (or, for a win recorded with no amount, the deal value).
    (COALESCE((SELECT e.value_eur FROM lead_events e
               WHERE e.lead_id = l.id AND e.stage = 'audit' AND e.value_eur IS NOT NULL
               ORDER BY e.created_at DESC, e.id DESC LIMIT 1), 0)
     + CASE WHEN l.status = 'closed_won' THEN
           COALESCE((SELECT e.value_eur FROM lead_events e
                     WHERE e.lead_id = l.id AND e.stage = 'closed_won' AND e.value_eur IS NOT NULL
                     ORDER BY e.created_at DESC, e.id DESC LIMIT 1),
                    CASE WHEN EXISTS (SELECT 1 FROM lead_events e
                                      WHERE e.lead_id = l.id AND e.stage = 'audit' AND e.value_eur IS NOT NULL)
                              -- The deal value then still holds the audit fee
                              -- (or a later proposal's amount): only a win
                              -- with its own amount adds to the audit.
                         THEN 0 ELSE l.deal_value_eur END, 0)
       ELSE 0 END)::int AS revenue_eur
FROM leads l
JOIN companies c ON c.id = l.company_id;

CREATE OR REPLACE VIEW v_sales_kpis AS
SELECT
    (SELECT count(*) FROM companies)::int                                              AS companies,
    (SELECT count(*) FROM companies WHERE created_at > now() - interval '7 days')::int AS companies_7d,
    (SELECT count(*) FROM companies c WHERE c.status IN ('scored', 'enriching')
        AND c.total_score >= outreach_min_score(c.segment, 60))::int                   AS qualified,
    (SELECT count(*) FROM leads)::int                                                  AS leads,
    (SELECT count(*) FROM outreach WHERE status = 'pending_approval')::int             AS awaiting_approval,
    (SELECT count(*) FROM outreach WHERE status = 'sent')::int                         AS emails_sent,
    (SELECT count(*) FROM outreach WHERE status = 'sent'
        AND sent_at > now() - interval '7 days')::int                                  AS emails_sent_7d,
    count(*) FILTER (WHERE contacted)::int                                             AS leads_contacted,
    count(*) FILTER (WHERE replied)::int                                               AS replied,
    count(*) FILTER (WHERE conversation)::int                                          AS sales_conversations,
    count(*) FILTER (WHERE meeting)::int                                               AS meetings,
    count(*) FILTER (WHERE proposal)::int                                              AS proposals,
    count(*) FILTER (WHERE won)::int                                                   AS clients,
    count(*) FILTER (WHERE bounced)::int                                               AS bounced,
    count(*) FILTER (WHERE unsubscribed)::int                                          AS unsubscribed,
    round(100.0 * count(*) FILTER (WHERE replied) / NULLIF(count(*) FILTER (WHERE contacted), 0), 1)      AS reply_rate_pct,
    round(100.0 * count(*) FILTER (WHERE conversation) / NULLIF(count(*) FILTER (WHERE contacted), 0), 1) AS conversation_rate_pct,
    round(100.0 * count(*) FILTER (WHERE bounced) / NULLIF(count(*) FILTER (WHERE contacted), 0), 1)      AS bounce_rate_pct,
    COALESCE(sum(deal_value_eur) FILTER (WHERE status IN ('opportunity', 'meeting', 'proposal')), 0)::int AS pipeline_eur,
    COALESCE(sum(deal_value_eur) FILTER (WHERE won), 0)::int                           AS won_eur,
    -- Added in 0026.
    count(*) FILTER (WHERE audit)::int                                                 AS audits,
    count(*) FILTER (WHERE lost)::int                                                  AS lost,
    COALESCE(sum(revenue_eur), 0)::int                                                 AS revenue_eur,
    -- The last 24 hours, for the daily picture.
    (SELECT count(*) FROM companies WHERE created_at > now() - interval '24 hours')::int AS companies_24h,
    (SELECT count(*) FROM outreach WHERE created_at > now() - interval '24 hours')::int  AS drafted_24h,
    (SELECT count(*) FROM outreach WHERE approved_at > now() - interval '24 hours')::int AS approved_24h,
    (SELECT count(*) FROM outreach WHERE sent_at > now() - interval '24 hours')::int     AS sent_24h,
    (SELECT count(*) FROM messages WHERE direction = 'inbound'
        AND COALESCE(classification, '') <> 'OUT_OF_SCOPE'
        AND created_at > now() - interval '24 hours')::int                               AS replies_24h
FROM v_lead_outcomes;

-- Per campaign: the whole funnel, from leads to revenue. Leads written to
-- before any campaign existed appear under '(none)'.
CREATE OR REPLACE VIEW v_campaign_results AS
SELECT
    COALESCE(k.code, '(none)')                     AS campaign,
    k.segment,
    k.offer,
    k.hypothesis,
    k.message_variant,
    k.active,
    k.started_at,
    count(o.lead_id)::int                          AS leads,
    count(*) FILTER (WHERE o.contacted)::int       AS contacted,
    count(*) FILTER (WHERE o.replied)::int         AS replied,
    count(*) FILTER (WHERE o.conversation)::int    AS conversations,
    count(*) FILTER (WHERE o.meeting)::int         AS calls,
    count(*) FILTER (WHERE o.audit)::int           AS audits,
    count(*) FILTER (WHERE o.proposal)::int        AS proposals,
    count(*) FILTER (WHERE o.won)::int             AS won,
    count(*) FILTER (WHERE o.lost)::int            AS lost,
    count(*) FILTER (WHERE o.bounced)::int         AS bounced,
    COALESCE(sum(o.revenue_eur), 0)::int           AS revenue_eur,
    round(100.0 * count(*) FILTER (WHERE o.replied) / NULLIF(count(*) FILTER (WHERE o.contacted), 0), 1)      AS reply_rate_pct,
    round(100.0 * count(*) FILTER (WHERE o.conversation) / NULLIF(count(*) FILTER (WHERE o.contacted), 0), 1) AS conversation_rate_pct
FROM (SELECT * FROM v_lead_outcomes WHERE contacted OR campaign IS NOT NULL) o
FULL JOIN campaigns k ON k.code = o.campaign
GROUP BY k.code, k.segment, k.offer, k.hypothesis, k.message_variant, k.active, k.started_at
ORDER BY k.started_at DESC NULLS LAST;

-- 5. Four questions about a company, answered separately.
--
--    WF-04 already scores fit, process load, capacity gap, pain and the
--    decision maker (docs/scoring.md). One total hides which of them is weak,
--    and for a first message they fail differently: a good fit with no
--    evidence is a question worth asking; strong evidence with only info@ is a
--    contact problem. These are read off what is stored - the latest scoring
--    run's components, the signals and the recipient - and none is a new
--    model judgement. Each is 0-100 for reading, rounded to 5 because the
--    inputs are not finer than that.
--
--    icp_fit            company fit + commercial potential (of 30)
--    opportunity        process/operational load + capacity gap + pain (of 60),
--                       on the line that won; `line` says which
--    process_confidence the best confidence among the automation-line signals
--                       that carry a source URL; 0 with none. An unsourced
--                       signal is a hypothesis and counts nothing here.
--    buyer_confidence   the lead's recipient: a named decision maker with a
--                       verified address 100, guessed 60, the general address
--                       30, nobody 0
CREATE OR REPLACE VIEW v_company_scores AS
SELECT
    c.id AS company_id,
    c.name,
    c.segment,
    c.total_score,
    c.score_band,
    CASE WHEN r.components IS NULL THEN NULL
         ELSE round(20.0 * (COALESCE((r.components ->> 'company_fit')::numeric, 0)
                            + COALESCE((r.components ->> 'commercial_potential')::numeric, 0)) / 30) * 5 END::int AS icp_fit,
    CASE WHEN r.components IS NULL THEN NULL
         ELSE round(20.0 * (COALESCE((r.components ->> 'technology_fit')::numeric, 0)
                            + COALESCE((r.components ->> 'hiring_signal')::numeric, 0)
                            + COALESCE((r.components ->> 'pain_evidence')::numeric, 0)) / 60) * 5 END::int AS opportunity,
    CASE WHEN r.notes ~ 'kept automation' THEN 'automation'
         WHEN r.components IS NULL THEN NULL
         ELSE 'infrastructure' END AS line,
    (round(20 * COALESCE(sig.best_confidence, 0)) * 5)::int AS process_confidence,
    COALESCE(sig.sourced, 0)::int   AS process_signals_sourced,
    COALESCE(sig.unsourced, 0)::int AS process_signals_unsourced,
    CASE WHEN rc.email IS NULL THEN 0
         WHEN rc.kind = 'role' THEN 30
         WHEN rc.email_status = 'valid' THEN 100
         WHEN rc.email_status IN ('guessed', 'catch_all') THEN 60
         ELSE 0 END AS buyer_confidence,
    rc.kind AS recipient_kind,
    rc.email_status AS recipient_email_status
FROM companies c
LEFT JOIN LATERAL (
    SELECT a.output -> 'components' AS components,
           (SELECT string_agg(n, ' ') FROM jsonb_array_elements_text(COALESCE(a.output -> 'notes', '[]'::jsonb)) n) AS notes
    FROM agent_runs a
    WHERE a.company_id = c.id AND a.agent_name = 'scoring' AND a.status = 'success'
    ORDER BY a.finished_at DESC NULLS LAST
    LIMIT 1
) r ON true
LEFT JOIN LATERAL (
    SELECT max(s.confidence) FILTER (WHERE s.source_url IS NOT NULL AND s.source_url <> '') AS best_confidence,
           count(*) FILTER (WHERE s.source_url IS NOT NULL AND s.source_url <> '')        AS sourced,
           count(*) FILTER (WHERE s.source_url IS NULL OR s.source_url = '')              AS unsourced
    FROM signals s
    WHERE s.company_id = c.id
      AND s.signal_type IN ('hiring_manual_ops', 'manual_process', 'tool_sprawl', 'volume_growth', 'hiring_automation')
) sig ON true
LEFT JOIN LATERAL (
    SELECT p.email, p.kind, p.email_status
    FROM leads l JOIN people p ON p.id = l.person_id
    WHERE l.company_id = c.id
    ORDER BY l.score DESC NULLS LAST, l.created_at
    LIMIT 1
) rc ON true;

COMMENT ON VIEW v_company_scores IS
    'ICP fit, opportunity, process confidence and buyer confidence, each read off stored scores, signals and the recipient. See 0026_first_revenue.sql.';
