-- 0024: ICP segments, sales stages and the numbers that say what works.
--
-- On 2026-09-29, 362 companies had been discovered and six emails sent. One bar
-- (OUTREACH_MIN_SCORE 60) applied to everything, and it was written for one
-- buyer: a funded software company with nobody running its infrastructure. A
-- ten-person Serbian webshop cannot score 60 on that scale - it posts no job
-- adverts, its site names no systems, and decision_maker is 3 for info@ - so the
-- automation line produced nothing to send. Nothing recorded which kind of
-- company an email went to either, so even a reply would not have said which
-- approach worked.
--
-- A segment is a testable ICP: which companies (by source and category), the
-- bar a lead in it must clear, and the concrete offer an email to it makes.
-- Companies get their segment from the table by trigger, so discovery needs no
-- change and a new segment is an INSERT. Every draft records its segment and
-- variant, and the views at the bottom count the funnel per segment and per
-- variant. The first number that matters is sales_conversations: leads that
-- answered with interest, a question, a price request or a referral, or that
-- the operator moved to a meeting, proposal or won.

-- 1. Segments.
CREATE TABLE icp_segments (
    code        text PRIMARY KEY CHECK (code ~ '^[a-z0-9_]+$'),
    name        text NOT NULL,
    line        text NOT NULL CHECK (line IN ('infrastructure', 'automation')),
    active      boolean NOT NULL DEFAULT true,
    -- The bar for a first message in this segment. Inactive segments use
    -- OUTREACH_MIN_SCORE like everything else.
    min_score   smallint NOT NULL CHECK (min_score BETWEEN 0 AND 100),
    -- Which companies: any of these sources, and (when set) an industry that is
    -- LIKE one of these patterns. Lower priority number wins.
    sources     text[] NOT NULL,
    industry_like text[],
    priority    smallint NOT NULL DEFAULT 100,
    -- What the email offers this segment, handed to the outreach model. NULL
    -- keeps the line's own prompt unchanged.
    angle       text,
    created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE icp_segments IS
    'Testable ICP segments: who (sources, industry), the bar (min_score) and the offer (angle). See 0024_icp_segments.sql.';

-- The bar 40 is the NURTURE floor: a company the scoring capped to IGNORE
-- (competitor, chain, research confidence below 0.3, no automation signal at
-- all) is never written to, in any segment. What 40 lets through is a company
-- with one sourced observation and an ICP fit, and that is what a segment email
-- is built on: the observation, and the segment's usual process asked as a
-- question rather than claimed.
INSERT INTO icp_segments (code, name, line, min_score, sources, industry_like, priority, angle) VALUES
('infra_startups', 'Software companies with no infrastructure owner', 'infrastructure', 60,
 ARRAY['radar_yc', 'radar_hn', 'radar_jobs'], NULL, 10, NULL),

('webshops', 'Regional shops that sell through their own webshop', 'automation', 40,
 ARRAY['radar_osm'], ARRAY['OSM shop=%'], 20,
 'A shop of 5-50 people that sells through its own webshop. The repetitive work such shops usually do by hand: '
 'each web order typed again into the accounting or ERP program, courier shipments created by hand and tracking '
 'numbers copied back to the customer, stock kept in sync between the webshop and the warehouse, e-invoices '
 'entered into SEF by hand. Offer: a short analysis of the path from a web order to the invoice and the shipment, '
 'with the steps worth automating ranked by what they cost.'),

('accounting_offices', 'Accounting offices', 'automation', 40,
 ARRAY['radar_osm'], ARRAY['OSM office=accountant'], 20,
 'An accounting office. The repetitive work such offices usually do by hand: collecting documents from clients '
 'over email and WhatsApp and chasing the missing ones every month, matching bank statements against invoices, '
 'typing in purchase invoices, pulling invoices out of SEF, reminding clients about deadlines. Offer: a short '
 'analysis of how documents come in from clients and get booked, with the steps worth automating ranked by the '
 'hours they take each month.'),

('logistics', 'Freight forwarders, logistics and courier firms', 'automation', 40,
 ARRAY['radar_osm'], ARRAY['OSM office=logistics', 'OSM office=courier'], 20,
 'A freight forwarding, logistics or courier firm. The repetitive work such firms usually do by hand: transport '
 'orders that arrive by email typed into their system, shipment statuses copied from carrier portals into emails '
 'to clients, delivery documents collected and matched by hand, invoices made from delivered shipments one by '
 'one. Offer: a short analysis of the path from an incoming order to the invoice, with the steps worth '
 'automating ranked by what they cost.'),

('agencies', 'Marketing and advertising agencies', 'automation', 40,
 ARRAY['radar_osm'], ARRAY['OSM office=advertising_agency', 'OSM office=marketing'], 20,
 'A marketing or advertising agency. The repetitive work agencies usually do by hand: the monthly client report '
 'assembled from Meta Ads, Google Ads and Analytics exports and screenshots, hours tracked and invoiced per '
 'client, briefs and approvals chased over email. Offer: a short analysis of client reporting and invoicing, '
 'with the steps worth automating ranked by the hours they take.'),

-- Everything else from the map, kept as a control: it is scored and counted,
-- and written to only if it clears the global bar.
('regional_other', 'Other regional businesses', 'automation', 60,
 ARRAY['radar_osm'], NULL, 90, NULL);

UPDATE icp_segments SET active = false WHERE code = 'regional_other';

-- 2. The company's segment, assigned from the table.
ALTER TABLE companies ADD COLUMN segment text REFERENCES icp_segments (code);
CREATE INDEX companies_segment_idx ON companies (segment);

CREATE OR REPLACE FUNCTION segment_for(p_source text, p_industry text) RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT s.code
    FROM icp_segments s
    WHERE p_source = ANY (s.sources)
      AND (s.industry_like IS NULL
           OR EXISTS (SELECT 1 FROM unnest(s.industry_like) pat WHERE COALESCE(p_industry, '') LIKE pat))
    ORDER BY s.priority, s.code
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION companies_assign_segment() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.segment IS NULL
       OR (TG_OP = 'UPDATE' AND (NEW.source IS DISTINCT FROM OLD.source
                                 OR NEW.industry IS DISTINCT FROM OLD.industry)
           AND NEW.segment IS NOT DISTINCT FROM OLD.segment) THEN
        NEW.segment := segment_for(NEW.source, NEW.industry);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER companies_assign_segment
    BEFORE INSERT OR UPDATE OF source, industry ON companies
    FOR EACH ROW EXECUTE FUNCTION companies_assign_segment();

UPDATE companies SET segment = segment_for(source, industry) WHERE segment IS NULL;

-- The bar a company's first message must clear: its active segment's, or the
-- global one passed in (OUTREACH_MIN_SCORE).
CREATE OR REPLACE FUNCTION outreach_min_score(p_segment text, p_default int) RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT COALESCE((SELECT s.min_score FROM icp_segments s WHERE s.code = p_segment AND s.active), p_default);
$$;

-- 3. What each draft was: segment, offer, language, CTA variant, model.
ALTER TABLE outreach ADD COLUMN segment text;
ALTER TABLE outreach ADD COLUMN variant jsonb NOT NULL DEFAULT '{}'::jsonb;

-- 4. Sales stages after a reply. Set by the operator from Telegram (/stage), because a
--    meeting or a proposal happens outside this system. Every change is kept.
ALTER TABLE leads DROP CONSTRAINT leads_status_check;
ALTER TABLE leads ADD CONSTRAINT leads_status_check CHECK (status IN (
    'new', 'pending_approval', 'approved', 'rejected', 'queued', 'contacted',
    'replied', 'opportunity', 'meeting', 'proposal', 'nurture',
    'closed_won', 'closed_lost', 'suppressed'
));
ALTER TABLE leads ADD COLUMN deal_value_eur integer CHECK (deal_value_eur IS NULL OR deal_value_eur >= 0);

CREATE TABLE lead_events (
    id          bigserial PRIMARY KEY,
    lead_id     uuid NOT NULL REFERENCES leads (id) ON DELETE CASCADE,
    stage       text NOT NULL,
    note        text,
    actor       text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX lead_events_lead_idx ON lead_events (lead_id, created_at);

-- 5. The numbers.
--
-- A sales conversation: a lead that replied with interest, a question, a price
-- request or a referral, or that reached a meeting, a proposal or won - ever,
-- so a meeting that later went nowhere still counts as the conversation it was.
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
      OR l.status IN ('opportunity', 'meeting', 'proposal', 'closed_won')
      OR EXISTS (SELECT 1 FROM lead_events e WHERE e.lead_id = l.id
                 AND e.stage IN ('opportunity', 'meeting', 'proposal', 'closed_won')) AS conversation,
    l.status IN ('meeting', 'proposal', 'closed_won')
      OR EXISTS (SELECT 1 FROM lead_events e WHERE e.lead_id = l.id
                 AND e.stage IN ('meeting', 'proposal', 'closed_won')) AS meeting,
    l.status IN ('proposal', 'closed_won')
      OR EXISTS (SELECT 1 FROM lead_events e WHERE e.lead_id = l.id
                 AND e.stage IN ('proposal', 'closed_won')) AS proposal,
    l.status = 'closed_won' AS won,
    EXISTS (SELECT 1 FROM people p JOIN suppression_list s ON s.email = p.email
            WHERE p.id = l.person_id AND s.reason = 'hard_bounce')
      OR EXISTS (SELECT 1 FROM people p WHERE p.id = l.person_id AND p.email_status = 'bounced') AS bounced,
    EXISTS (SELECT 1 FROM people p JOIN suppression_list s ON s.email = p.email
            WHERE p.id = l.person_id AND s.reason = 'unsubscribe_request') AS unsubscribed
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
    COALESCE(sum(deal_value_eur) FILTER (WHERE won), 0)::int                           AS won_eur
FROM v_lead_outcomes;

CREATE OR REPLACE VIEW v_segment_results AS
SELECT
    s.code AS segment,
    s.active,
    s.min_score,
    (SELECT count(*) FROM companies c WHERE c.segment = s.code)::int AS companies,
    (SELECT count(*) FROM companies c WHERE c.segment = s.code AND c.status IN ('scored', 'enriching')
        AND c.total_score >= outreach_min_score(c.segment, 60))::int AS qualified,
    count(o.lead_id)::int                                  AS leads,
    count(*) FILTER (WHERE o.contacted)::int               AS contacted,
    count(*) FILTER (WHERE o.replied)::int                 AS replied,
    count(*) FILTER (WHERE o.conversation)::int            AS conversations,
    count(*) FILTER (WHERE o.meeting)::int                 AS meetings,
    count(*) FILTER (WHERE o.won)::int                     AS won,
    count(*) FILTER (WHERE o.bounced)::int                 AS bounced,
    round(100.0 * count(*) FILTER (WHERE o.replied) / NULLIF(count(*) FILTER (WHERE o.contacted), 0), 1) AS reply_rate_pct
FROM icp_segments s
LEFT JOIN v_lead_outcomes o ON o.segment = s.code
GROUP BY s.code, s.active, s.min_score, s.priority
ORDER BY s.priority, s.code;

CREATE OR REPLACE VIEW v_variant_results AS
SELECT
    COALESCE(segment, 'none')                         AS segment,
    COALESCE(first_variant ->> 'cta', 'none')         AS cta,
    COALESCE(first_variant ->> 'language', 'none')    AS language,
    count(*)::int                                     AS contacted,
    count(*) FILTER (WHERE replied)::int              AS replied,
    count(*) FILTER (WHERE conversation)::int         AS conversations
FROM v_lead_outcomes
WHERE contacted
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
