-- WF-08 reply draft (0028): the context query finds the thread, and the draft
-- is queued as a reply_draft notification; an empty draft queues nothing.
INSERT INTO companies (id, name, domain, source, industry, country, status) VALUES
    ('00000000-0000-0000-0000-00000000b801', 'Reply Shop', 'replyshop.example', 'radar_osm', 'OSM shop=hardware', 'RS', 'scored');
INSERT INTO people (id, company_id, full_name, email, email_status, kind, discovery_method, source_url) VALUES
    ('00000000-0000-0000-0000-00000000b802', '00000000-0000-0000-0000-00000000b801', NULL, 'info@replyshop.example', 'valid', 'role', 'published_page', 'https://replyshop.example/kontakt');
INSERT INTO leads (id, company_id, person_id, score, recommended_offer, status) VALUES
    ('66660000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000b801', '00000000-0000-0000-0000-00000000b802', 50, 'process_audit', 'contacted');
INSERT INTO conversations (id, lead_id, external_thread_id) VALUES
    ('77770000-0000-0000-0000-000000000001', '66660000-0000-0000-0000-000000000001', 'thread-test-1');
INSERT INTO messages (conversation_id, direction, author, body) VALUES
    ('77770000-0000-0000-0000-000000000001', 'inbound', 'prospect', 'Zanima me, možete li poslati primer?');

DO $$
DECLARE r record; n int;
BEGIN
    EXECUTE $q$EXECUTE wf08_reply_context('{"lead_id": "66660000-0000-0000-0000-000000000001", "conversation_id": "77770000-0000-0000-0000-000000000001"}')$q$ INTO r;
    IF r.company_name IS DISTINCT FROM 'Reply Shop' OR json_array_length(r.thread) <> 1 THEN
        RAISE EXCEPTION 'reply context wrong: % %', r.company_name, r.thread;
    END IF;

    EXECUTE $q$EXECUTE wf08_queue_reply('{"conversation_id": "77770000-0000-0000-0000-000000000001", "external_message_id": "m1",
        "from_email": "info@replyshop.example", "category": "POSITIVE", "lead_id": "66660000-0000-0000-0000-000000000001",
        "company_name": "Reply Shop", "draft": ""}')$q$;
    IF EXISTS (SELECT 1 FROM notifications WHERE kind = 'reply_draft') THEN
        RAISE EXCEPTION 'an empty draft was queued';
    END IF;

    EXECUTE $q$EXECUTE wf08_queue_reply('{"conversation_id": "77770000-0000-0000-0000-000000000001", "external_message_id": "m1",
        "from_email": "info@replyshop.example", "category": "POSITIVE", "lead_id": "66660000-0000-0000-0000-000000000001",
        "company_name": "Reply Shop", "draft": "Hvala na odgovoru. Primer je ovde: https://example.com/process-audit/primer/"}')$q$;
    SELECT count(*) INTO n FROM notifications WHERE kind = 'reply_draft' AND body LIKE '%primer%' AND priority = 'immediate';
    IF n <> 1 THEN RAISE EXCEPTION 'expected one reply_draft notification, got %', n; END IF;
END $$;
