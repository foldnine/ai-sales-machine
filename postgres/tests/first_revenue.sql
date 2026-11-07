-- First-revenue funnel: campaign attribution, stages, revenue, and the safety
-- rules around them, run through the workflows' own SQL (wf05_queue,
-- wf11_apply, wf08_apply are prepared by infra/scripts/sql-test.sh from
-- n8n/workflows/). Every block raises on a wrong answer.

-- Fixtures: one webshop with a named owner, one accounting office, and a
-- software company that belongs to no campaign.
INSERT INTO companies (id, name, domain, source, industry, country, status) VALUES
    ('00000000-0000-0000-0000-00000000c001', 'Test Shop', 'testshop.example', 'radar_osm', 'OSM shop=electronics', 'RS', 'scored'),
    ('00000000-0000-0000-0000-00000000c002', 'Test Books', 'testbooks.example', 'radar_osm', 'OSM office=accountant', 'RS', 'scored'),
    ('00000000-0000-0000-0000-00000000c003', 'Test SaaS', 'testsaas.example', 'radar_yc', NULL, 'DE', 'scored');
INSERT INTO people (id, company_id, full_name, email, email_status, kind) VALUES
    ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000c001', 'Ana Test', 'ana@testshop.example', 'valid', 'person'),
    ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-00000000c002', 'Bojan Test', 'bojan@testbooks.example', 'guessed', 'person'),
    ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-00000000c003', 'Cara Test', 'cara@testsaas.example', 'valid', 'person');
INSERT INTO leads (id, company_id, person_id, score, recommended_offer, status) VALUES
    ('11110000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000a001', 48, 'process_audit', 'new'),
    ('22220000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000c002', '00000000-0000-0000-0000-00000000a002', 45, 'process_audit', 'new'),
    ('33330000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000c003', '00000000-0000-0000-0000-00000000a003', 70, 'infrastructure_audit', 'new');

-- 1. Segments are assigned by trigger, and the webshop has a running campaign.
DO $$ BEGIN
    IF (SELECT segment FROM companies WHERE domain = 'testshop.example') IS DISTINCT FROM 'webshops' THEN
        RAISE EXCEPTION 'webshop not in the webshops segment';
    END IF;
    IF campaign_for_lead('11110000-0000-0000-0000-000000000001') IS DISTINCT FROM 'ecommerce-process-audit-v1' THEN
        RAISE EXCEPTION 'webshop lead has no campaign: %', campaign_for_lead('11110000-0000-0000-0000-000000000001');
    END IF;
    IF campaign_for_lead('33330000-0000-0000-0000-000000000003') IS NOT NULL THEN
        RAISE EXCEPTION 'software lead got a campaign it does not belong to';
    END IF;
END $$;

-- 2. One running campaign per segment.
DO $$ BEGIN
    BEGIN
        INSERT INTO campaigns (code, name, segment, offer, hypothesis, message_variant)
        VALUES ('ecommerce-process-audit-v2', 'v2', 'webshops', 'process_audit', 'x', 'y');
        RAISE EXCEPTION 'a second active webshop campaign was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO campaigns (code, name, segment, offer, hypothesis, message_variant, active)
        VALUES ('bad-offer', 'x', 'agencies', 'free_consultation', 'x', 'y', false);
        RAISE EXCEPTION 'a campaign with an unknown offer was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
END $$;

-- 2b. WF-05 Claim Leads hands the night batch its campaign: the webshop and
--     the accounting office clear their segment's bar of 40 and are segment
--     emails (night); the software company is a day lead.
DO $$
DECLARE r record; n int := 0;
BEGIN
    FOR r IN EXECUTE $q$EXECUTE wf05_claim('{"min_score": 60, "followup_max": 2, "followup_delay_days": 4,
        "window": "night", "regional_countries": ["RS"], "batch_size": 20, "model": "test", "input": {"window": "night"}}')$q$
    LOOP
        n := n + 1;
        IF r.lead_id = '11110000-0000-0000-0000-000000000001' AND r.campaign IS DISTINCT FROM 'ecommerce-process-audit-v1' THEN
            RAISE EXCEPTION 'claimed webshop lead carries campaign %', r.campaign;
        END IF;
        IF r.lead_id = '22220000-0000-0000-0000-000000000002' AND r.campaign IS NOT NULL THEN
            RAISE EXCEPTION 'accounting lead got campaign %', r.campaign;
        END IF;
        IF r.lead_id = '33330000-0000-0000-0000-000000000003' THEN
            RAISE EXCEPTION 'a day lead was claimed at night';
        END IF;
    END LOOP;
    IF n <> 2 THEN RAISE EXCEPTION 'claimed % leads, expected 2', n; END IF;
END $$;

-- 3. WF-05 Queue For Approval records the campaign on the draft, and a
--    campaign name that does not exist is recorded as none.
EXECUTE wf05_queue('{"lead_id": "11110000-0000-0000-0000-000000000001", "sequence_step": 1,
    "draft": {"subject": "porudžbine i ERP", "body": "Vidim da koristite WooCommerce i BEX. Kako porudžbine stižu do knjigovodstva?"},
    "experiment": {"segment": "webshops", "campaign": "ecommerce-process-audit-v1", "cta": "A", "offer": "process_audit"}}');
EXECUTE wf05_queue('{"lead_id": "22220000-0000-0000-0000-000000000002", "sequence_step": 1,
    "draft": {"subject": "dokumenta klijenata", "body": "Body."},
    "experiment": {"segment": "accounting_offices", "campaign": "renamed-meanwhile", "cta": "B"}}');
DO $$ BEGIN
    IF (SELECT campaign FROM outreach WHERE lead_id = '11110000-0000-0000-0000-000000000001') IS DISTINCT FROM 'ecommerce-process-audit-v1' THEN
        RAISE EXCEPTION 'draft did not record its campaign';
    END IF;
    IF (SELECT campaign FROM outreach WHERE lead_id = '22220000-0000-0000-0000-000000000002') IS NOT NULL THEN
        RAISE EXCEPTION 'an unknown campaign name was written';
    END IF;
    IF (SELECT status FROM outreach WHERE lead_id = '11110000-0000-0000-0000-000000000001') <> 'pending_approval' THEN
        RAISE EXCEPTION 'draft skipped pending_approval';
    END IF;
END $$;

-- 4. Suppression still stops a draft, whatever campaign it is in.
INSERT INTO suppression_list (email, reason) VALUES ('cara@testsaas.example', 'unsubscribe_request');
DO $$ BEGIN
    BEGIN
        EXECUTE $q$EXECUTE wf05_queue('{"lead_id": "33330000-0000-0000-0000-000000000003", "sequence_step": 1,
            "draft": {"subject": "s", "body": "b"}, "experiment": {}}')$q$;
        RAISE EXCEPTION 'a draft to a suppressed address was queued';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE 'outreach blocked:%suppression list%' THEN RAISE; END IF;
    END;
END $$;

-- 5. Duplicate leads: one per company and person.
DO $$ BEGIN
    BEGIN
        INSERT INTO leads (company_id, person_id) VALUES
            ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000a001');
        RAISE EXCEPTION 'a duplicate lead was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
END $$;

-- The webshop email is approved and sent (WF-06's job, simulated), the
-- accounting office's is sent and bounces.
UPDATE outreach SET status = 'sent', sent_at = now() - interval '5 days', approved_by = 'test', approved_at = now() - interval '5 days';
UPDATE leads SET status = 'contacted' WHERE id IN ('11110000-0000-0000-0000-000000000001', '22220000-0000-0000-0000-000000000002');
UPDATE people SET email_status = 'bounced' WHERE id = '00000000-0000-0000-0000-00000000a002';

-- 6. A question arrives and is classified (WF-08).
INSERT INTO conversations (id, lead_id, external_thread_id, status) VALUES
    ('44440000-0000-0000-0000-000000000004', '11110000-0000-0000-0000-000000000001', 'thread-1', 'open');
EXECUTE wf08_apply('{"conversation_id": "44440000-0000-0000-0000-000000000004",
    "lead_id": "11110000-0000-0000-0000-000000000001", "external_message_id": "m1",
    "subject": "Re: porudžbine", "body": "Koliko košta ta analiza?", "from_email": "ana@testshop.example",
    "lead_email": "ana@testshop.example", "company_name": "Test Shop", "escalated": false,
    "classification": {"category": "PRICE", "confidence": 0.9, "requested_stop": false,
                       "human_required": false, "reason": "asks the price"}}');
DO $$ BEGIN
    IF (SELECT status FROM leads WHERE id = '11110000-0000-0000-0000-000000000001') <> 'replied' THEN
        RAISE EXCEPTION 'a price question did not move the lead to replied';
    END IF;
    IF NOT (SELECT conversation FROM v_lead_outcomes WHERE lead_id = '11110000-0000-0000-0000-000000000001') THEN
        RAISE EXCEPTION 'a price question is not counted as a sales conversation';
    END IF;
    IF NOT (SELECT bounced FROM v_lead_outcomes WHERE lead_id = '22220000-0000-0000-0000-000000000002') THEN
        RAISE EXCEPTION 'the bounce is not counted';
    END IF;
END $$;

-- 7. The operator moves the webshop through the stages on Telegram (WF-11). A replayed
--    update and a message from another chat change nothing.
EXECUTE wf11_apply('{"update_id": 1, "chat_id": "42", "command": "stage", "argument": "1111", "args": ["1111", "call", "first", "call", "booked"], "authorised": true, "paused": true}');
EXECUTE wf11_apply('{"update_id": 1, "chat_id": "42", "command": "stage", "argument": "1111", "args": ["1111", "won", "99999"], "authorised": true, "paused": true}');
EXECUTE wf11_apply('{"update_id": 2, "chat_id": "666", "command": "stage", "argument": "1111", "args": ["1111", "won", "99999"], "authorised": false, "paused": true}');
DO $$ BEGIN
    IF (SELECT status FROM leads WHERE id = '11110000-0000-0000-0000-000000000001') <> 'meeting' THEN
        RAISE EXCEPTION 'call did not move the lead to meeting, or a replay/unauthorised command did';
    END IF;
    IF (SELECT count(*) FROM lead_events) <> 1 THEN
        RAISE EXCEPTION 'expected one stage event, got %', (SELECT count(*) FROM lead_events);
    END IF;
    IF (SELECT note FROM lead_events) <> 'first call booked' THEN
        RAISE EXCEPTION 'the note was not kept: %', (SELECT note FROM lead_events);
    END IF;
END $$;

EXECUTE wf11_apply('{"update_id": 3, "chat_id": "42", "command": "stage", "argument": "1111", "args": ["1111", "audit", "1200"], "authorised": true, "paused": true}');

-- 8. A reply from a lead in a sales stage does not push it back to 'replied'.
EXECUTE wf08_apply('{"conversation_id": "44440000-0000-0000-0000-000000000004",
    "lead_id": "11110000-0000-0000-0000-000000000001", "external_message_id": "m2",
    "subject": "Re: analiza", "body": "Kada možete da počnete?", "from_email": "ana@testshop.example",
    "lead_email": "ana@testshop.example", "company_name": "Test Shop", "escalated": false,
    "classification": {"category": "QUESTION", "confidence": 0.9, "requested_stop": false,
                       "human_required": false, "reason": "asks when"}}');
DO $$ BEGIN
    IF (SELECT status FROM leads WHERE id = '11110000-0000-0000-0000-000000000001') <> 'audit' THEN
        RAISE EXCEPTION 'a question from a lead at audit moved it to %', (SELECT status FROM leads WHERE id = '11110000-0000-0000-0000-000000000001');
    END IF;
    IF (SELECT revenue_eur FROM v_sales_kpis) <> 1200 OR (SELECT audits FROM v_sales_kpis) <> 1 THEN
        RAISE EXCEPTION 'audit revenue %, audits %', (SELECT revenue_eur FROM v_sales_kpis), (SELECT audits FROM v_sales_kpis);
    END IF;
    IF (SELECT pipeline_eur FROM v_sales_kpis) <> 0 THEN
        RAISE EXCEPTION 'the paid audit is counted as open pipeline too';
    END IF;
END $$;

-- 9. Proposal, then the build is won: the build is entered net of the audit
--    credit, and revenue is the audit fee plus the build, not the proposal twice.
EXECUTE wf11_apply('{"update_id": 4, "chat_id": "42", "command": "stage", "argument": "1111", "args": ["1111", "proposal", "4800"], "authorised": true, "paused": true}');
DO $$ BEGIN
    IF (SELECT pipeline_eur FROM v_sales_kpis) <> 4800 THEN
        RAISE EXCEPTION 'open pipeline %, expected 4800', (SELECT pipeline_eur FROM v_sales_kpis);
    END IF;
END $$;
EXECUTE wf11_apply('{"update_id": 5, "chat_id": "42", "command": "stage", "argument": "1111", "args": ["1111", "won"], "authorised": true, "paused": true}');
DO $$ BEGIN
    -- Won with no amount after a paid audit: the deal value still holds the
    -- proposal, which is not revenue until an amount is given at 'won'.
    IF (SELECT revenue_eur FROM v_sales_kpis) <> 1200 THEN
        RAISE EXCEPTION 'won without an amount counted % revenue', (SELECT revenue_eur FROM v_sales_kpis);
    END IF;
END $$;
EXECUTE wf11_apply('{"update_id": 6, "chat_id": "42", "command": "stage", "argument": "1111", "args": ["1111", "won", "3600", "build", "net", "of", "credit"], "authorised": true, "paused": true}');

-- 10. The funnel, per campaign and overall.
DO $$
DECLARE k v_sales_kpis; c v_campaign_results;
BEGIN
    SELECT * INTO k FROM v_sales_kpis;
    IF k.leads_contacted <> 2 OR k.replied <> 1 OR k.sales_conversations <> 1 OR k.meetings <> 1
       OR k.audits <> 1 OR k.proposals <> 1 OR k.clients <> 1 OR k.bounced <> 1 OR k.revenue_eur <> 4800 THEN
        RAISE EXCEPTION 'kpis wrong: %', row_to_json(k);
    END IF;
    SELECT * INTO c FROM v_campaign_results WHERE campaign = 'ecommerce-process-audit-v1';
    IF c.contacted <> 1 OR c.replied <> 1 OR c.calls <> 1 OR c.audits <> 1 OR c.proposals <> 1
       OR c.won <> 1 OR c.revenue_eur <> 4800 OR c.reply_rate_pct <> 100.0 THEN
        RAISE EXCEPTION 'campaign results wrong: %', row_to_json(c);
    END IF;
    SELECT * INTO c FROM v_campaign_results WHERE campaign = '(none)';
    IF c.contacted <> 1 OR c.bounced <> 1 OR c.revenue_eur <> 0 THEN
        RAISE EXCEPTION 'uncampaigned results wrong: %', row_to_json(c);
    END IF;
    IF (SELECT count(*) FROM lead_events WHERE value_eur IS NOT NULL) <> 3 THEN
        RAISE EXCEPTION 'amounts not kept on the stage events';
    END IF;
END $$;

-- 11. /stats and /campaigns answer with real numbers; an unknown stage is refused.
DO $$
DECLARE r record;
BEGIN
    EXECUTE $q$EXECUTE wf11_apply('{"update_id": 7, "chat_id": "42", "command": "stats", "args": [], "authorised": true, "paused": true}')$q$ INTO r;
    IF r.reply NOT LIKE '%REVENUE €4800%' OR r.reply NOT LIKE '%audits 1%' THEN
        RAISE EXCEPTION '/stats reply: %', r.reply;
    END IF;
    EXECUTE $q$EXECUTE wf11_apply('{"update_id": 8, "chat_id": "42", "command": "campaigns", "args": [], "authorised": true, "paused": true}')$q$ INTO r;
    IF r.reply NOT LIKE '%ecommerce-process-audit-v1%' OR r.reply NOT LIKE '%€4800%' THEN
        RAISE EXCEPTION '/campaigns reply: %', r.reply;
    END IF;
    EXECUTE $q$EXECUTE wf11_apply('{"update_id": 9, "chat_id": "42", "command": "stage", "argument": "1111", "args": ["1111", "signed"], "authorised": true, "paused": true}')$q$ INTO r;
    IF r.outcome <> 'bad_stage' THEN
        RAISE EXCEPTION 'an unknown stage was %', r.outcome;
    END IF;
END $$;

-- 12. An opt-out still suppresses and cancels, in any stage.
EXECUTE wf08_apply('{"conversation_id": "44440000-0000-0000-0000-000000000004",
    "lead_id": "11110000-0000-0000-0000-000000000001", "external_message_id": "m3",
    "subject": "Re", "body": "Molim Vas, ne pišite mi više.", "from_email": "ana@testshop.example",
    "lead_email": "ana@testshop.example", "company_name": "Test Shop", "escalated": false,
    "classification": {"category": "UNSUBSCRIBE", "confidence": 1, "requested_stop": true,
                       "human_required": false, "reason": "asked to stop"}}');
DO $$ BEGIN
    IF NOT is_suppressed('ana@testshop.example') THEN
        RAISE EXCEPTION 'opt-out did not suppress';
    END IF;
    IF (SELECT status FROM leads WHERE id = '11110000-0000-0000-0000-000000000001') <> 'suppressed' THEN
        RAISE EXCEPTION 'opt-out from a won lead did not suppress it';
    END IF;
END $$;

-- 13. The four scores read off stored data, and with none they are honest.
INSERT INTO agent_runs (agent_name, company_id, status, started_at, finished_at, output) VALUES
    ('scoring', '00000000-0000-0000-0000-00000000c002', 'success', now(), now(),
     '{"components": {"company_fit": 15, "commercial_potential": 6, "technology_fit": 9, "hiring_signal": 3, "pain_evidence": 6, "decision_maker": 5},
       "notes": ["lines: infrastructure 20, automation 44; kept automation"]}');
INSERT INTO signals (company_id, signal_type, signal, source_url, confidence) VALUES
    ('00000000-0000-0000-0000-00000000c002', 'manual_process', 'dokumentaciju dostavite e-mailom', 'https://testbooks.example/usluge', 0.8),
    ('00000000-0000-0000-0000-00000000c002', 'tool_sprawl', 'probably several tools', NULL, 0.9);
DO $$
DECLARE s v_company_scores;
BEGIN
    SELECT * INTO s FROM v_company_scores WHERE company_id = '00000000-0000-0000-0000-00000000c002';
    IF s.icp_fit <> 70 OR s.opportunity <> 30 OR s.line <> 'automation' OR s.process_confidence <> 80
       OR s.process_signals_sourced <> 1 OR s.process_signals_unsourced <> 1 OR s.buyer_confidence <> 0 THEN
        -- buyer 0: the address bounced, so there is nobody to write to.
        RAISE EXCEPTION 'scores wrong: %', row_to_json(s);
    END IF;
    SELECT * INTO s FROM v_company_scores WHERE company_id = '00000000-0000-0000-0000-00000000c003';
    IF s.icp_fit IS NOT NULL OR s.process_confidence <> 0 THEN
        RAISE EXCEPTION 'an unscored company got scores: %', row_to_json(s);
    END IF;
END $$;
