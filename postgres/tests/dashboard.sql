-- The dashboard role (0033): it reads, it cannot write a table, and its three
-- functions do what /approve and /reject do and log it.
INSERT INTO companies (id, name, domain, source, industry, country, status) VALUES
    ('00000000-0000-0000-0000-0000000da001', 'Dash Shop', 'dashshop.example', 'manual', 'Retail', 'DE', 'ready');
INSERT INTO people (id, company_id, full_name, email, email_status, kind) VALUES
    ('00000000-0000-0000-0000-0000000da101', '00000000-0000-0000-0000-0000000da001', 'Dana Example', 'dana@dashshop.example', 'valid', 'person'),
    ('00000000-0000-0000-0000-0000000da102', '00000000-0000-0000-0000-0000000da001', 'Dino Example', 'dino@dashshop.example', 'valid', 'person');
INSERT INTO leads (id, company_id, person_id, score, recommended_offer, status) VALUES
    ('66660000-0000-0000-0000-0000000da201', '00000000-0000-0000-0000-0000000da001', '00000000-0000-0000-0000-0000000da101', 70, 'process_audit', 'pending_approval'),
    ('66660000-0000-0000-0000-0000000da202', '00000000-0000-0000-0000-0000000da001', '00000000-0000-0000-0000-0000000da102', 70, 'process_audit', 'pending_approval');
INSERT INTO outreach (id, lead_id, subject, body, status) VALUES
    ('77770000-0000-0000-0000-0000000da301', '66660000-0000-0000-0000-0000000da201', 'One question',
     E'Hi Dana,\n\nBody one.\n\n--\nYour Name\nYour Company\n\nReply "stop".', 'pending_approval'),
    ('77770000-0000-0000-0000-0000000da302', '66660000-0000-0000-0000-0000000da202', 'Another question',
     E'Hi Dana,\n\nBody two.\n\n--\nYour Name\nYour Company\n\nReply "stop".', 'pending_approval');

SET ROLE aisales_dashboard;

-- 1. Reads work; a direct write does not.
DO $$ BEGIN
    IF (SELECT count(*) FROM v_approval_queue WHERE outreach_id::text LIKE '77770000-%') <> 2 THEN
        RAISE EXCEPTION 'the dashboard role cannot read the approval queue';
    END IF;
    BEGIN
        UPDATE outreach SET status = 'approved' WHERE id = '77770000-0000-0000-0000-0000000da301';
        RAISE EXCEPTION 'the dashboard role updated outreach directly';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        PERFORM 1 FROM n8n.credentials_entity LIMIT 1;
        RAISE EXCEPTION 'the dashboard role can read n8n credentials';
    EXCEPTION WHEN insufficient_privilege OR undefined_table OR invalid_schema_name THEN NULL;
    END;
END $$;

-- 2. An edit that drops the signature is refused; one that keeps it is applied.
DO $$
DECLARE r text;
BEGIN
    BEGIN
        PERFORM dashboard_edit('77770000-0000-0000-0000-0000000da301', 'One question', E'Hi Dana,\n\nShorter.', 'test');
        RAISE EXCEPTION 'an edit without the signature block was accepted';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM NOT LIKE '%signature%' THEN RAISE; END IF;
    END;
    r := dashboard_edit('77770000-0000-0000-0000-0000000da301', 'Better question',
                        E'Hi Dana,\n\nBody one, tightened.\n\n--\nYour Name\nYour Company\n\nReply "stop".', 'test');
    IF r <> 'edited' THEN RAISE EXCEPTION 'edit returned %', r; END IF;
END $$;

-- 3. Approve: only waiting rows, the lead follows, a second approve is a no-op.
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM dashboard_approve(ARRAY['77770000-0000-0000-0000-0000000da301'::uuid], 'test')
    WHERE outcome = 'approved';
    IF n <> 1 THEN RAISE EXCEPTION 'approve did not approve'; END IF;
    SELECT count(*) INTO n FROM dashboard_approve(ARRAY['77770000-0000-0000-0000-0000000da301'::uuid], 'test')
    WHERE outcome = 'not_pending';
    IF n <> 1 THEN RAISE EXCEPTION 'a second approve was not a no-op'; END IF;
    IF dashboard_edit('77770000-0000-0000-0000-0000000da301', 'x', 'y', 'test') <> 'not_pending' THEN
        RAISE EXCEPTION 'an approved draft could still be edited';
    END IF;
END $$;

-- 4. Reject keeps the reason.
DO $$ BEGIN
    IF dashboard_reject('77770000-0000-0000-0000-0000000da302', 'wrong angle', 'test') <> 'rejected' THEN
        RAISE EXCEPTION 'reject did not reject';
    END IF;
END $$;

RESET ROLE;

DO $$ BEGIN
    IF (SELECT approved_by FROM outreach WHERE id = '77770000-0000-0000-0000-0000000da301') <> 'dashboard:test'
       OR (SELECT status FROM leads WHERE id = '66660000-0000-0000-0000-0000000da201') <> 'approved' THEN
        RAISE EXCEPTION 'approval did not record its actor or move the lead';
    END IF;
    IF (SELECT rejection_reason FROM outreach WHERE id = '77770000-0000-0000-0000-0000000da302') <> 'wrong angle'
       OR (SELECT status FROM leads WHERE id = '66660000-0000-0000-0000-0000000da202') <> 'rejected' THEN
        RAISE EXCEPTION 'rejection did not keep its reason or move the lead';
    END IF;
    IF (SELECT array_agg(action ORDER BY id) FROM operator_actions WHERE actor = 'dashboard:test')
       <> ARRAY['edit', 'approve', 'reject'] THEN
        RAISE EXCEPTION 'operator_actions: %', (SELECT array_agg(action ORDER BY id) FROM operator_actions);
    END IF;
END $$;

DELETE FROM outreach WHERE id::text LIKE '77770000-%';
DELETE FROM leads WHERE id::text LIKE '66660000-0000-0000-0000-0000000da%';
DELETE FROM people WHERE id::text LIKE '00000000-0000-0000-0000-0000000da1%';
DELETE FROM companies WHERE id = '00000000-0000-0000-0000-0000000da001';
