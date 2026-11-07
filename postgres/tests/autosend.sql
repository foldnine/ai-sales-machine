-- Guarded autosend (0030_autosend.sql), through the workflows' own SQL:
-- wf05_queue, wf05_autosend, wf05_alert, wf11_apply and wf100_stats are
-- prepared by infra/scripts/sql-test.sh from n8n/workflows/. Every block
-- raises on a wrong answer.
--
-- Everything here is rolled back at the end, so the files after this one see
-- the database as the migrations left it.
SAVEPOINT autosend_test;

-- Drafts other test files left waiting would be swept by /autosend on below.
UPDATE outreach SET status = 'rejected', rejection_reason = 'set aside by autosend.sql'
WHERE status = 'pending_approval';

-- 0. The migration's defaults: off, with a deny list.
DO $$ BEGIN
    IF autosend_enabled() THEN RAISE EXCEPTION 'autosend must start off'; END IF;
    IF (SELECT value FROM app_settings WHERE key = 'autosend') <> '{"enabled": false}'::jsonb THEN
        RAISE EXCEPTION 'app_settings autosend is %', (SELECT value FROM app_settings WHERE key = 'autosend');
    END IF;
    IF NOT (SELECT value FROM app_settings WHERE key = 'autosend_deny_patterns') @> '["\\mponudim\\M", "\\mponudite\\M"]'::jsonb THEN
        RAISE EXCEPTION 'the deny list is not seeded with the verb forms';
    END IF;
END $$;

-- 1. The helpers.
DO $$ BEGIN
    IF autosend_language_map('RS:sr, HR:sr,DE:de,none') <> '{"RS": "sr", "HR": "sr", "SERBIA": "sr", "CROATIA": "sr"}'::jsonb THEN
        RAISE EXCEPTION 'autosend_language_map: %', autosend_language_map('RS:sr, HR:sr,DE:de,none');
    END IF;
    IF autosend_language_map('') <> '{}'::jsonb OR autosend_language_map(NULL) <> '{}'::jsonb THEN
        RAISE EXCEPTION 'an empty OUTREACH_LANGUAGES must map nothing';
    END IF;
    IF autosend_text_language('Da li Vam se to dešava svakog meseca, ili je to kod Vas već rešeno?') <> 'sr' THEN
        RAISE EXCEPTION 'Serbian read as %', autosend_text_language('Da li Vam se to dešava svakog meseca, ili je to kod Vas već rešeno?');
    END IF;
    IF autosend_text_language('Is that role meant to own the pipeline, or is it a stopgap for the volume?') <> 'en' THEN
        RAISE EXCEPTION 'English read as %', autosend_text_language('Is that role meant to own the pipeline, or is it a stopgap for the volume?');
    END IF;
    IF autosend_text_language('ERP CRM WooCommerce') <> 'unclear' THEN
        RAISE EXCEPTION 'three product names have no language';
    END IF;
    IF autosend_greeting(E'N/r: Ana Test, direktor\n\nPoštovani,\n\nTekst.') <> 'Poštovani,' THEN
        RAISE EXCEPTION 'the greeting under an N/r line was not found';
    END IF;
    IF autosend_model_text(E'Hi Lena,\n\nOne.\n\nTwo?\n\n--\nYour Name\n\nReply "stop".') <> E'One.\n\nTwo?' THEN
        RAISE EXCEPTION 'model text: %', autosend_model_text(E'Hi Lena,\n\nOne.\n\nTwo?\n\n--\nYour Name\n\nReply "stop".');
    END IF;
END $$;

-- 2. Fixtures. A: a Serbian accounting office, a named owner, a clean draft.
--    B: a German software company, English, clean. C: Serbian, with one word
--    in Cyrillic. Each written by WF-05's own Queue For Approval.
INSERT INTO companies (id, name, domain, source, industry, country, status, employee_count) VALUES
    ('00000000-0000-0000-0000-0000000a5001', 'Knjige Plus', 'knjigeplus.example', 'radar_osm', 'OSM office=accountant', 'RS', 'scored', 8),
    ('00000000-0000-0000-0000-0000000a5002', 'Lena Cloud', 'lenacloud.example', 'radar_yc', NULL, 'DE', 'scored', 20),
    ('00000000-0000-0000-0000-0000000a5003', 'Račun Centar', 'racuncentar.example', 'radar_osm', 'OSM office=accountant', 'RS', 'scored', 6);
INSERT INTO people (id, company_id, full_name, email, email_status, kind) VALUES
    ('00000000-0000-0000-0000-0000000b5001', '00000000-0000-0000-0000-0000000a5001', 'Marko Petrović', 'marko@knjigeplus.example', 'valid', 'person'),
    ('00000000-0000-0000-0000-0000000b5002', '00000000-0000-0000-0000-0000000a5002', 'Lena Weber', 'lena@lenacloud.example', 'valid', 'person'),
    ('00000000-0000-0000-0000-0000000b5003', '00000000-0000-0000-0000-0000000a5003', 'Jelena Ilić', 'jelena@racuncentar.example', 'guessed', 'person');
INSERT INTO leads (id, company_id, person_id, score, status) VALUES
    ('a5a50000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000a5001', '00000000-0000-0000-0000-0000000b5001', 70, 'new'),
    ('a5a50000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000a5002', '00000000-0000-0000-0000-0000000b5002', 80, 'new'),
    ('a5a50000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000a5003', '00000000-0000-0000-0000-0000000b5003', 65, 'new');

DO $$
DECLARE
    sig_sr text := E'--\nYour Name\nYour Company - automatizacija poslovnih procesa\nhttps://example.com/\n\n'
                || E'Niste prava osoba ili vas ovo ne zanima? Odgovorite „stop“ i više vam se\nnećemo javljati.';
    sig_en text := E'--\nYour Name\nYour Company - infrastructure audits, DevOps and SRE\nhttps://example.com/infrastructure/\n\n'
                || E'Not the right person, or not interested? Reply "stop" and you will not hear\nfrom us again.';
BEGIN
    EXECUTE format('EXECUTE wf05_queue(%L::jsonb)', jsonb_build_object(
        'lead_id', 'a5a50000-0000-0000-0000-000000000001', 'sequence_step', 1,
        'draft', jsonb_build_object('subject', 'Dokumenta od klijenata svakog meseca', 'body', concat_ws(E'\n\n',
            'Dobar dan, Marko,',
            'Na Vašem sajtu piše da vodite knjige za preko trideset firmi u Novom Sadu.',
            'Kancelarije te veličine obično svakog meseca ručno skupljaju izvode i fakture od klijenata preko mejla i Vibera.',
            'Radim kratku analizu procesa: kako dokumenta stižu i gde se gubi najviše sati.',
            'Da li je to kod Vas već rešeno?',
            sig_sr)),
        'experiment', jsonb_build_object('segment', 'accounting_offices', 'language', 'sr', 'cta', 'A')));
    EXECUTE format('EXECUTE wf05_queue(%L::jsonb)', jsonb_build_object(
        'lead_id', 'a5a50000-0000-0000-0000-000000000002', 'sequence_step', 1,
        'draft', jsonb_build_object('subject', 'Platform engineer role open since June', 'body', concat_ws(E'\n\n',
            'Hi Lena,',
            'Your careers page lists a platform engineer role that has been open since June.',
            'When the person who set up the deploys leaves, the pipeline usually becomes the thing nobody wants to touch.',
            'I run short infrastructure audits that end with a written list of what to fix first.',
            'Is that role meant to own the pipeline?',
            sig_en)),
        'experiment', jsonb_build_object('segment', 'infra_startups', 'language', 'en', 'cta', 'A')));
    EXECUTE format('EXECUTE wf05_queue(%L::jsonb)', jsonb_build_object(
        'lead_id', 'a5a50000-0000-0000-0000-000000000003', 'sequence_step', 1,
        'draft', jsonb_build_object('subject', 'Izvodi iz banke i fakture', 'body', concat_ws(E'\n\n',
            'Dobar dan, Jelena,',
            'Vaš sajt navodi da radite sa preduzetnicima iz Šapca i okoline.',
            'Takve kancelarije obično sat po sat sparuju бankovne izvode sa fakturama u programu.',
            'Radim kratku analizu: koji koraci mogu da se automatizuju i koliko vremena odnose.',
            'Da li je to kod Vas posao jedne osobe?',
            sig_sr)),
        'experiment', jsonb_build_object('segment', 'accounting_offices', 'language', 'sr', 'cta', 'B')));
END $$;

CREATE FUNCTION pg_temp.draft(p_lead text) RETURNS uuid LANGUAGE sql AS $$
    SELECT id FROM outreach WHERE lead_id = p_lead::uuid ORDER BY sequence_step LIMIT 1;
$$;

-- Holds unless a reason of this kind is found for draft A (or the one named).
CREATE FUNCTION pg_temp.expect_blocker(p_kind text, p_lead text DEFAULT 'a5a50000-0000-0000-0000-000000000001',
                                       p_languages text DEFAULT 'RS:sr,HR:sr,BA:sr,ME:sr')
RETURNS void LANGUAGE plpgsql AS $$
DECLARE b text[] := autosend_blockers(pg_temp.draft(p_lead), p_languages);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM unnest(b) x WHERE x LIKE p_kind || ':%') THEN
        RAISE EXCEPTION 'expected a "%" blocker, got %', p_kind, b;
    END IF;
END $$;

CREATE FUNCTION pg_temp.expect_clean(p_lead text DEFAULT 'a5a50000-0000-0000-0000-000000000001',
                                     p_languages text DEFAULT 'RS:sr,HR:sr,BA:sr,ME:sr')
RETURNS void LANGUAGE plpgsql AS $$
DECLARE b text[] := autosend_blockers(pg_temp.draft(p_lead), p_languages);
BEGIN
    IF cardinality(b) <> 0 THEN
        RAISE EXCEPTION 'expected no blockers for %, got %', p_lead, b;
    END IF;
END $$;

-- 3. The happy path: A and B are clean, C is held for its Cyrillic word.
SELECT pg_temp.expect_clean('a5a50000-0000-0000-0000-000000000001');
SELECT pg_temp.expect_clean('a5a50000-0000-0000-0000-000000000002');
SELECT pg_temp.expect_clean('a5a50000-0000-0000-0000-000000000001', NULL);
SELECT pg_temp.expect_blocker('cyrillic', 'a5a50000-0000-0000-0000-000000000003');

-- 4. Every blocker, one at a time, on draft A.
SAVEPOINT b; UPDATE outreach SET sequence_step = 2 WHERE lead_id = 'a5a50000-0000-0000-0000-000000000001';
SELECT pg_temp.expect_blocker('follow-up'); ROLLBACK TO SAVEPOINT b;

SAVEPOINT b; UPDATE outreach SET status = 'rejected' WHERE lead_id = 'a5a50000-0000-0000-0000-000000000001';
SELECT pg_temp.expect_blocker('status'); ROLLBACK TO SAVEPOINT b;

SAVEPOINT b; UPDATE outreach SET subject = 'Документа од клијената' WHERE lead_id = 'a5a50000-0000-0000-0000-000000000001';
SELECT pg_temp.expect_blocker('cyrillic'); ROLLBACK TO SAVEPOINT b;

SAVEPOINT b; UPDATE outreach SET body = replace(body, 'Radim kratku analizu', 'Ponudim kratku analizu')
WHERE lead_id = 'a5a50000-0000-0000-0000-000000000001';
SELECT pg_temp.expect_blocker('phrase'); ROLLBACK TO SAVEPOINT b;

SAVEPOINT b; UPDATE outreach SET body = replace(body, 'Radim kratku', 'Ponudite kratku')
WHERE lead_id = 'a5a50000-0000-0000-0000-000000000001';
SELECT pg_temp.expect_blocker('phrase'); ROLLBACK TO SAVEPOINT b;

-- The deny list is data: a new pattern takes effect on the next draft, and a
-- broken one holds drafts instead of failing the workflow.
SAVEPOINT b; UPDATE app_settings SET value = value || '["trideset firmi"]'::jsonb WHERE key = 'autosend_deny_patterns';
SELECT pg_temp.expect_blocker('phrase'); ROLLBACK TO SAVEPOINT b;
SAVEPOINT b; UPDATE app_settings SET value = '["(unclosed"]'::jsonb WHERE key = 'autosend_deny_patterns';
SELECT pg_temp.expect_blocker('deny list'); ROLLBACK TO SAVEPOINT b;

SAVEPOINT b; UPDATE outreach SET body = replace(body, 'Dobar dan, Marko,', 'Poštovani direktore,')
WHERE lead_id = 'a5a50000-0000-0000-0000-000000000001';
SELECT pg_temp.expect_blocker('greeting'); ROLLBACK TO SAVEPOINT b;

SAVEPOINT b; UPDATE outreach SET body = replace(body, 'Dobar dan, Marko,', 'Dobar dan, Direktor,')
WHERE lead_id = 'a5a50000-0000-0000-0000-000000000001';
SELECT pg_temp.expect_blocker('greeting'); ROLLBACK TO SAVEPOINT b;

SAVEPOINT b; UPDATE outreach SET body = replace(body, 'Hi Lena,', 'Dear CEO,')
WHERE lead_id = 'a5a50000-0000-0000-0000-000000000002';
SELECT pg_temp.expect_blocker('greeting', 'a5a50000-0000-0000-0000-000000000002'); ROLLBACK TO SAVEPOINT b;

SAVEPOINT b; UPDATE outreach SET body = replace(body, 'Hi Lena,', 'Hi Sales Team,')
WHERE lead_id = 'a5a50000-0000-0000-0000-000000000002';
SELECT pg_temp.expect_blocker('greeting', 'a5a50000-0000-0000-0000-000000000002'); ROLLBACK TO SAVEPOINT b;

SAVEPOINT b; INSERT INTO suppression_list (domain, reason) VALUES ('knjigeplus.example', 'manual');
SELECT pg_temp.expect_blocker('suppressed'); ROLLBACK TO SAVEPOINT b;

SAVEPOINT b; INSERT INTO people (company_id, full_name, email, email_status, kind) VALUES
    ('00000000-0000-0000-0000-0000000a5001', 'Ana Petrović', 'ana@knjigeplus.example', 'bounced', 'person');
SELECT pg_temp.expect_blocker('bounced'); ROLLBACK TO SAVEPOINT b;

SAVEPOINT b; INSERT INTO suppression_list (email, reason) VALUES ('old@knjigeplus.example', 'hard_bounce');
SELECT pg_temp.expect_blocker('bounced'); ROLLBACK TO SAVEPOINT b;

SAVEPOINT b; UPDATE leads SET status = 'replied' WHERE id = 'a5a50000-0000-0000-0000-000000000001';
SELECT pg_temp.expect_blocker('lead'); ROLLBACK TO SAVEPOINT b;

SAVEPOINT b; INSERT INTO conversations (lead_id, external_thread_id) VALUES ('a5a50000-0000-0000-0000-000000000001', 'autosend-test-1');
SELECT pg_temp.expect_blocker('conversation'); ROLLBACK TO SAVEPOINT b;

-- Somebody else at the company answered an earlier message (WF-08 recorded it).
SAVEPOINT b;
INSERT INTO people (id, company_id, full_name, email, email_status, kind) VALUES
    ('00000000-0000-0000-0000-0000000b5009', '00000000-0000-0000-0000-0000000a5001', 'Ivana Petrović', 'ivana@knjigeplus.example', 'valid', 'person');
INSERT INTO leads (id, company_id, person_id, score, status) VALUES
    ('a5a50000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-0000000a5001', '00000000-0000-0000-0000-0000000b5009', 60, 'contacted');
INSERT INTO conversations (id, lead_id, external_thread_id) VALUES
    ('a5a5c000-0000-0000-0000-000000000009', 'a5a50000-0000-0000-0000-000000000009', 'autosend-test-9');
INSERT INTO messages (conversation_id, direction, author, body) VALUES
    ('a5a5c000-0000-0000-0000-000000000009', 'inbound', 'prospect', 'Javite se sledeće nedelje.');
SELECT pg_temp.expect_blocker('conversation');
ROLLBACK TO SAVEPOINT b;

SAVEPOINT b; UPDATE companies SET employee_count = 600 WHERE id = '00000000-0000-0000-0000-0000000a5001';
SELECT pg_temp.expect_blocker('size'); ROLLBACK TO SAVEPOINT b;

SAVEPOINT b;
INSERT INTO agent_runs (agent_name, company_id, status, started_at, finished_at, output) VALUES
    ('research', '00000000-0000-0000-0000-0000000a5001', 'success', now() - interval '1 hour', now(),
     '{"analysis": {"company_summary": "A national courier network with 35 shops across Serbia.", "facts": []}}');
SELECT pg_temp.expect_blocker('size');
ROLLBACK TO SAVEPOINT b;

SAVEPOINT b; UPDATE icp_segments SET active = false WHERE code = 'accounting_offices';
SELECT pg_temp.expect_blocker('segment'); ROLLBACK TO SAVEPOINT b;

SAVEPOINT b; UPDATE companies SET segment = NULL WHERE id = '00000000-0000-0000-0000-0000000a5001';
SELECT pg_temp.expect_blocker('segment'); ROLLBACK TO SAVEPOINT b;

-- A country OUTREACH_LANGUAGES no longer maps to Serbian, and an English
-- answer to a Serbian brief.
SAVEPOINT b;
SELECT pg_temp.expect_blocker('language', 'a5a50000-0000-0000-0000-000000000001', 'HR:sr');
ROLLBACK TO SAVEPOINT b;
SAVEPOINT b; UPDATE outreach SET body = replace(replace(body,
        'Kancelarije te veličine obično svakog meseca ručno skupljaju izvode i fakture od klijenata preko mejla i Vibera.',
        'Offices of that size usually collect statements and invoices from their clients by email every month.'),
        'Da li je to kod Vas već rešeno?', 'Is that something you have already solved?')
WHERE lead_id = 'a5a50000-0000-0000-0000-000000000001';
UPDATE outreach SET subject = 'Documents from clients every month', body = replace(body,
        'Na Vašem sajtu piše da vodite knjige za preko trideset firmi u Novom Sadu.',
        'Your site says you keep the books for more than thirty firms in Novi Sad.')
WHERE lead_id = 'a5a50000-0000-0000-0000-000000000001';
SELECT pg_temp.expect_blocker('language');
ROLLBACK TO SAVEPOINT b;

-- The same sentence already went to another company.
SAVEPOINT b;
INSERT INTO companies (id, name, domain, source, industry, country, status) VALUES
    ('00000000-0000-0000-0000-0000000a5008', 'Drugi Biro', 'drugibiro.example', 'radar_osm', 'OSM office=accountant', 'RS', 'scored');
INSERT INTO people (id, company_id, full_name, email, email_status, kind) VALUES
    ('00000000-0000-0000-0000-0000000b5008', '00000000-0000-0000-0000-0000000a5008', 'Petar Jovanović', 'petar@drugibiro.example', 'valid', 'person');
INSERT INTO leads (id, company_id, person_id, score, status) VALUES
    ('a5a50000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-0000000a5008', '00000000-0000-0000-0000-0000000b5008', 60, 'rejected');
INSERT INTO outreach (lead_id, subject, body, status) VALUES
    ('a5a50000-0000-0000-0000-000000000008', 'Nešto drugo', E'Dobar dan, Petre,\n\n'
     || 'Kancelarije te veličine obično svakog meseca ručno skupljaju izvode i fakture od klijenata preko mejla i Vibera.'
     || E'\n\n--\nYour Name', 'rejected');
SELECT pg_temp.expect_blocker('boilerplate');
ROLLBACK TO SAVEPOINT b;

-- 5. WF-05 Autosend Check. Off (either switch): every draft passes through
--    to the approval message and nothing is touched or recorded.
DO $$
DECLARE r record; n int := 0;
BEGIN
    FOR r IN EXECUTE format('EXECUTE wf05_autosend(%L::jsonb)', jsonb_build_object(
        'outreach_id', pg_temp.draft('a5a50000-0000-0000-0000-000000000001'), 'env_enabled', true,
        'languages', 'RS:sr', 'hook_fact', 'thirty firms', 'hook_source', 'https://knjigeplus.example/'))
    LOOP
        n := n + 1;
        IF r.autosend_active OR r.auto_approved OR r.hook_fact <> 'thirty firms' THEN
            RAISE EXCEPTION 'with app_settings off the draft was judged: %', row_to_json(r);
        END IF;
    END LOOP;
    IF n <> 1 THEN RAISE EXCEPTION 'with autosend off the draft must go on to the alert, got % rows', n; END IF;

    UPDATE app_settings SET value = '{"enabled": true}' WHERE key = 'autosend';
    n := 0;
    FOR r IN EXECUTE format('EXECUTE wf05_autosend(%L::jsonb)', jsonb_build_object(
        'outreach_id', pg_temp.draft('a5a50000-0000-0000-0000-000000000001'), 'env_enabled', false, 'languages', 'RS:sr'))
    LOOP
        n := n + 1;
        IF r.autosend_active THEN RAISE EXCEPTION 'the master switch off still judged the draft'; END IF;
    END LOOP;
    IF n <> 1 OR (SELECT status FROM outreach WHERE id = pg_temp.draft('a5a50000-0000-0000-0000-000000000001')) <> 'pending_approval'
       OR EXISTS (SELECT 1 FROM autosend_decisions) THEN
        RAISE EXCEPTION 'OUTREACH_AUTOSEND_ENABLED=false approved or recorded something';
    END IF;
    UPDATE app_settings SET value = '{"enabled": false}' WHERE key = 'autosend';
END $$;

-- On, and the draft is held: it comes out with its reasons, and the approval
-- message carries them in one line.
SAVEPOINT b;
UPDATE app_settings SET value = '{"enabled": true}' WHERE key = 'autosend';
DO $$
DECLARE r record; a record; n int := 0;
BEGIN
    FOR r IN EXECUTE format('EXECUTE wf05_autosend(%L::jsonb)', jsonb_build_object(
        'outreach_id', pg_temp.draft('a5a50000-0000-0000-0000-000000000003'), 'env_enabled', true,
        'languages', 'RS:sr', 'hook_fact', 'Šabac', 'hook_source', 'https://racuncentar.example/'))
    LOOP
        n := n + 1;
        IF NOT r.autosend_active OR r.auto_approved OR NOT EXISTS (SELECT 1 FROM unnest(r.blockers) x WHERE x LIKE 'cyrillic:%') THEN
            RAISE EXCEPTION 'the Cyrillic draft was not held with its reason: %', row_to_json(r);
        END IF;
        FOR a IN EXECUTE format('EXECUTE wf05_alert(%L::jsonb)', jsonb_build_object(
            'outreach_id', r.outreach_id, 'hook_fact', r.hook_fact, 'hook_source', r.hook_source,
            'autosend_blockers', to_jsonb(r.blockers)))
        LOOP END LOOP;
    END LOOP;
    IF n <> 1 THEN RAISE EXCEPTION 'a held draft must reach the alert, got % rows', n; END IF;
    IF NOT EXISTS (SELECT 1 FROM notifications
                   WHERE dedup_key = 'draft_ready:' || pg_temp.draft('a5a50000-0000-0000-0000-000000000003')
                     AND body LIKE '%/approve%' AND body LIKE E'%\nAutosend held it: cyrillic: %') THEN
        RAISE EXCEPTION 'the approval message does not say why autosend held it: %',
            (SELECT body FROM notifications WHERE dedup_key = 'draft_ready:' || pg_temp.draft('a5a50000-0000-0000-0000-000000000003'));
    END IF;
    IF (SELECT status FROM outreach WHERE id = pg_temp.draft('a5a50000-0000-0000-0000-000000000003')) <> 'pending_approval' THEN
        RAISE EXCEPTION 'a held draft left pending_approval';
    END IF;

    -- And a clean one goes: approved by autosend, no row out, so no alert.
    n := 0;
    FOR r IN EXECUTE format('EXECUTE wf05_autosend(%L::jsonb)', jsonb_build_object(
        'outreach_id', pg_temp.draft('a5a50000-0000-0000-0000-000000000001'), 'env_enabled', true, 'languages', 'RS:sr'))
    LOOP n := n + 1; END LOOP;
    IF n <> 0 THEN RAISE EXCEPTION 'an auto-approved draft went on to the approval message'; END IF;
    IF (SELECT status || '/' || approved_by FROM outreach WHERE id = pg_temp.draft('a5a50000-0000-0000-0000-000000000001'))
       <> 'approved/autosend'
       OR (SELECT approved_at FROM outreach WHERE id = pg_temp.draft('a5a50000-0000-0000-0000-000000000001')) IS NULL
       OR (SELECT status FROM leads WHERE id = 'a5a50000-0000-0000-0000-000000000001') <> 'approved' THEN
        RAISE EXCEPTION 'the clean draft was not approved by autosend';
    END IF;
    IF (SELECT count(*) FROM autosend_decisions WHERE approved) <> 1
       OR (SELECT count(*) FROM autosend_decisions WHERE NOT approved) <> 1 THEN
        RAISE EXCEPTION 'decisions were not recorded';
    END IF;
    -- A NULL id (Queue For Approval wrote nothing) is no row at all.
    n := 0;
    FOR r IN EXECUTE $q$EXECUTE wf05_autosend('{"outreach_id": null, "env_enabled": true, "languages": ""}')$q$ LOOP n := n + 1; END LOOP;
    IF n <> 0 THEN RAISE EXCEPTION 'a NULL draft produced a row'; END IF;
END $$;
ROLLBACK TO SAVEPOINT b;

-- 6. WF-11. /autosend on is refused while the master switch is off, and from
--    any other chat it is recorded and not answered.
DO $$
DECLARE r record;
BEGIN
    EXECUTE $q$EXECUTE wf11_apply('{"update_id": 990001, "chat_id": "42", "command": "autosend", "argument": "on",
        "args": ["on"], "authorised": true, "paused": true, "autosend_env": false, "languages": "RS:sr", "timezone": "Europe/Belgrade"}')$q$ INTO r;
    IF r.outcome <> 'refused' OR r.reply NOT LIKE '%OUTREACH_AUTOSEND_ENABLED%' OR autosend_enabled() THEN
        RAISE EXCEPTION '/autosend on with the master switch off: % / %', r.outcome, r.reply;
    END IF;
    IF (SELECT outcome FROM command_log WHERE update_id = 990001) <> 'refused' THEN
        RAISE EXCEPTION 'the refusal was not logged';
    END IF;
    EXECUTE $q$EXECUTE wf11_apply('{"update_id": 990002, "chat_id": "666", "command": "autosend", "argument": "on",
        "args": ["on"], "authorised": false, "paused": true, "autosend_env": true, "languages": "RS:sr", "timezone": "UTC"}')$q$ INTO r;
    IF r.outcome <> 'unauthorised' OR r.reply IS NOT NULL OR autosend_enabled() THEN
        RAISE EXCEPTION 'another chat turned autosend on, or was answered: % / %', r.outcome, r.reply;
    END IF;
    EXECUTE $q$EXECUTE wf11_apply('{"update_id": 990003, "chat_id": "42", "command": "autosend", "argument": "maybe",
        "args": ["maybe"], "authorised": true, "paused": true, "autosend_env": true}')$q$ INTO r;
    IF r.reply NOT LIKE '/autosend on%' OR autosend_enabled() THEN
        RAISE EXCEPTION 'a bad argument: % / %', r.outcome, r.reply;
    END IF;
    EXECUTE $q$EXECUTE wf11_apply('{"update_id": 990004, "chat_id": "42", "command": "help", "args": [],
        "authorised": true, "paused": true}')$q$ INTO r;
    IF r.reply NOT LIKE '%/autosend on|off%' OR r.reply NOT LIKE '%/stop%' THEN
        RAISE EXCEPTION '/help does not list /autosend and /stop';
    END IF;
END $$;

-- /autosend on sweeps the queue: A and B go, C stays with its reason.
DO $$
DECLARE r record;
BEGIN
    EXECUTE $q$EXECUTE wf11_apply('{"update_id": 990010, "chat_id": "42", "command": "autosend", "argument": "on",
        "args": ["on"], "authorised": true, "paused": false, "autosend_env": true, "languages": "RS:sr,HR:sr,BA:sr,ME:sr", "timezone": "Europe/Belgrade"}')$q$ INTO r;
    IF r.outcome <> 'applied' OR NOT autosend_enabled() THEN
        RAISE EXCEPTION '/autosend on did not turn it on: % / %', r.outcome, r.reply;
    END IF;
    IF r.reply NOT LIKE 'Autosend uključen.%' OR r.reply NOT LIKE '%2 odobreno automatski, 1 ostaje tebi%'
       OR r.reply NOT LIKE '%cyrillic 1%' THEN
        RAISE EXCEPTION 'the sweep reply: %', r.reply;
    END IF;
    IF (SELECT array_agg(approved_by ORDER BY lead_id) FROM outreach WHERE lead_id::text LIKE 'a5a50000%')
       IS DISTINCT FROM ARRAY['autosend', 'autosend', NULL] THEN
        RAISE EXCEPTION 'the sweep approved the wrong drafts: %',
            (SELECT array_agg(status || '/' || COALESCE(approved_by, '-') ORDER BY lead_id) FROM outreach WHERE lead_id::text LIKE 'a5a50000%');
    END IF;

    -- A replay of the same update does not sweep again.
    EXECUTE $q$EXECUTE wf11_apply('{"update_id": 990010, "chat_id": "42", "command": "autosend", "argument": "on",
        "args": ["on"], "authorised": true, "paused": false, "autosend_env": true, "languages": "RS:sr", "timezone": "UTC"}')$q$ INTO r;
    IF r.reply <> 'Već obrađeno.' OR (SELECT count(*) FROM autosend_decisions) <> 3 THEN
        RAISE EXCEPTION 'a replayed /autosend on did something: % (% decisions)', r.reply, (SELECT count(*) FROM autosend_decisions);
    END IF;
END $$;

-- A goes out (WF-06's Record Send is not under test here). The daily report
-- names it; /autosend counts it.
UPDATE outreach SET status = 'queued' WHERE lead_id = 'a5a50000-0000-0000-0000-000000000001';
UPDATE outreach SET status = 'sent', sent_at = now() WHERE lead_id = 'a5a50000-0000-0000-0000-000000000001';
DO $$
DECLARE r record;
BEGIN
    EXECUTE $q$EXECUTE wf100_stats('{"timezone": "Europe/Belgrade"}')$q$ INTO r;
    IF r.autosent_count <> 1 OR r.autosent::jsonb -> 0 ->> 'company' <> 'Knjige Plus'
       OR r.autosent::jsonb -> 0 ->> 'subject' <> 'Dokumenta od klijenata svakog meseca'
       OR r.autosent::jsonb -> 0 ->> 'lead' <> 'a5a5' OR NOT r.autosend_enabled OR r.autosend_waiting <> 1 THEN
        RAISE EXCEPTION 'the daily report: % % % %', r.autosent_count, r.autosent, r.autosend_enabled, r.autosend_waiting;
    END IF;

    EXECUTE $q$EXECUTE wf11_apply('{"update_id": 990011, "chat_id": "42", "command": "autosend", "args": [],
        "authorised": true, "paused": true, "autosend_env": true, "languages": "RS:sr", "timezone": "Europe/Belgrade"}')$q$ INTO r;
    IF r.reply NOT LIKE 'Autosend: UKLJUČEN%' OR r.reply NOT LIKE '%Danas automatski odobreno: 2 (poslato 1)%'
       OR r.reply NOT LIKE '%Danas zadržano za tebe: 1 — cyrillic 1%' OR r.reply NOT LIKE '%OUTREACH_PAUSED%' THEN
        RAISE EXCEPTION '/autosend status: %', r.reply;
    END IF;
END $$;

-- /stop: off, and B - approved by autosend, not yet claimed - comes back to the operator.
DO $$
DECLARE r record;
BEGIN
    EXECUTE $q$EXECUTE wf11_apply('{"update_id": 990012, "chat_id": "42", "command": "stop", "args": [],
        "authorised": true, "paused": false, "autosend_env": true, "languages": "RS:sr", "timezone": "UTC"}')$q$ INTO r;
    IF r.outcome <> 'applied' OR autosend_enabled() THEN
        RAISE EXCEPTION '/stop did not turn autosend off: % / %', r.outcome, r.reply;
    END IF;
    IF r.reply NOT LIKE 'Autosend isključen. Novi draftovi idu na odobrenje.%'
       OR r.reply NOT LIKE '%1 automatski odobrenih, a još neposlatih, vraćeno je na odobrenje%' THEN
        RAISE EXCEPTION '/stop reply: %', r.reply;
    END IF;
    IF (SELECT status FROM outreach WHERE lead_id = 'a5a50000-0000-0000-0000-000000000002') <> 'pending_approval'
       OR (SELECT approved_by FROM outreach WHERE lead_id = 'a5a50000-0000-0000-0000-000000000002') IS NOT NULL
       OR (SELECT status FROM leads WHERE id = 'a5a50000-0000-0000-0000-000000000002') <> 'pending_approval' THEN
        RAISE EXCEPTION '/stop left an auto-approved draft approved';
    END IF;
    IF (SELECT status FROM outreach WHERE lead_id = 'a5a50000-0000-0000-0000-000000000001') <> 'sent' THEN
        RAISE EXCEPTION '/stop touched a sent message';
    END IF;

    -- Off, a new draft is not judged at all.
    IF EXISTS (SELECT 1 FROM autosend_decide(pg_temp.draft('a5a50000-0000-0000-0000-000000000002'), true, 'RS:sr')
               WHERE autosend_active) THEN
        RAISE EXCEPTION 'autosend_decide acted after /stop';
    END IF;

    -- /autosend off is the same as /stop.
    EXECUTE $q$EXECUTE wf11_apply('{"update_id": 990013, "chat_id": "42", "command": "autosend", "argument": "off",
        "args": ["off"], "authorised": true, "paused": true, "autosend_env": true}')$q$ INTO r;
    IF r.reply NOT LIKE 'Autosend isključen.%' OR autosend_enabled() THEN
        RAISE EXCEPTION '/autosend off: %', r.reply;
    END IF;
END $$;

ROLLBACK TO SAVEPOINT autosend_test;
