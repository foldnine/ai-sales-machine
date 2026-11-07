-- Seed: a realistic-looking pipeline for the dashboard demo and screenshots.
-- Every company, person and address is invented and lives under the reserved
-- .example TLD. Never load this into a real database.
--   make seed-demo
--
-- Deterministic (setseed), and safe to load twice: companies are keyed on
-- domain and everything else hangs off the companies this run created.

DO $$
DECLARE
    pre text[] := ARRAY[
        'Northwind','Lumen','Quanta','Brightpath','Cobalt','Fernhill','Halcyon','Ironbark',
        'Juniper','Keystone','Larkspur','Meridian','Nimbus','Obsidian','Pinecrest','Quillon',
        'Redwood','Saltmarsh','Tidewater','Umber','Vantage','Willow','Xenia','Yarrow',
        'Zephyr','Alder','Birchwood','Cedarline','Driftwood','Emberly','Foxglove','Granite',
        'Hawthorn','Indigo','Jasper','Kestrel','Linden','Marigold','Nettle','Oakmont',
        'Peregrine','Quarry','Rowan','Sorrel','Thistle','Upland','Verdant','Wren',
        'Aster','Bramble','Copperleaf','Dunmore','Elmstead','Fallow','Glenrock','Heron',
        'Ivywood','Juno','Kinsale','Lowmoor','Millbrook','Northgate','Orchard','Pebble',
        'Quayside','Riverstone','Silverbirch','Tamarack','Ullswater','Valemont','Westbrook','Yewdale'];
    first_names text[] := ARRAY['Anna','Ben','Clara','David','Elena','Felix','Greta','Hugo','Ines','Jonas',
        'Katrin','Lukas','Maja','Niko','Olivia','Pavel','Rosa','Stefan','Tara','Viktor','Lea','Marko','Sara','Tim'];
    last_names text[] := ARRAY['Berger','Novak','Jansen','Kovač','Meyer','Horvat','de Vries','Fischer','Lindqvist',
        'Marić','Schulz','Petrov','Visser','Wagner','Bakker','Hoffmann','Kraus','Popović','Smit','Weber'];
    seg text; src text; country text; industry text; offer text; line text;
    i int; c_id uuid; p_id uuid; l_id uuid; o_id uuid; cv_id uuid;
    fit int; res int; dm int; total int; st text; created timestamptz;
    fname text; lname text; dom text; nm text; title text; hook text; sig_type text; sig_text text;
    sent timestamptz; cls text; stage text;
    techs jsonb;
BEGIN
    IF EXISTS (SELECT 1 FROM companies WHERE domain = 'northwind.example') THEN
        RAISE NOTICE 'demo pipeline already loaded';
        RETURN;
    END IF;
    PERFORM setseed(0.42);

    FOR i IN 1 .. array_length(pre, 1) LOOP
        CASE
            WHEN i <= 26 THEN seg := 'infra_startups'; line := 'infrastructure';
                src := (ARRAY['radar_yc','radar_hn','radar_jobs'])[1 + i % 3];
                country := (ARRAY['NL','DE','GB','US','SE','FR','ES'])[1 + i % 7];
                industry := (ARRAY['B2B SaaS','Fintech','Developer tools','Healthtech','Logistics software','Data platform'])[1 + i % 6];
                offer := (ARRAY['infrastructure_audit','devops_improvement_sprint','fractional_devops_sre'])[1 + i % 3];
                nm := pre[i] || (ARRAY[' Labs',' Cloud',' Analytics',' Systems',' AI',' Health'])[1 + i % 6];
                techs := (ARRAY['["aws","kubernetes","terraform","postgresql"]','["gcp","docker","github-actions"]',
                                '["aws","ecs","datadog","redis"]','["azure","aks","helm","grafana"]'])[1 + i % 4]::jsonb;
            WHEN i <= 44 THEN seg := 'webshops'; line := 'automation'; src := 'radar_osm';
                country := (ARRAY['RS','HR','SI','DE','AT'])[1 + i % 5]; industry := 'OSM shop=' || (ARRAY['hardware','clothes','furniture','bicycle','cosmetics'])[1 + i % 5];
                offer := 'process_audit'; nm := pre[i] || (ARRAY[' Store',' Shop',' Outfitters',' Home'])[1 + i % 4];
                techs := '["woocommerce","excel","gmail"]'::jsonb;
            WHEN i <= 58 THEN seg := 'accounting_offices'; line := 'automation';
                src := (ARRAY['radar_osm','radar_minimax'])[1 + i % 2];
                country := (ARRAY['SI','RS','HR'])[1 + i % 3]; industry := 'OSM office=accountant';
                offer := 'process_audit'; nm := pre[i] || ' Accounting';
                techs := '["minimax","excel"]'::jsonb;
            WHEN i <= 65 THEN seg := 'logistics'; line := 'automation'; src := 'radar_osm';
                country := (ARRAY['RS','HR','DE'])[1 + i % 3]; industry := 'OSM office=logistics';
                offer := 'process_audit'; nm := pre[i] || ' Freight';
                techs := '["excel","email"]'::jsonb;
            ELSE seg := 'agencies'; line := 'automation'; src := 'radar_osm';
                country := (ARRAY['SI','RS','NL'])[1 + i % 3]; industry := 'OSM office=advertising_agency';
                offer := 'process_audit'; nm := pre[i] || ' Studio';
                techs := '["notion","hubspot","google-workspace"]'::jsonb;
        END CASE;

        dom := lower(pre[i]) || '.example';
        -- Skewed towards the last two weeks, as a pipeline that is running looks.
        created := now() - (power(random(), 1.6) * interval '42 days') - interval '2 hours';
        IF line = 'infrastructure' THEN
            fit := 18 + floor(random() * 32)::int; res := 10 + floor(random() * 30)::int; dm := floor(random() * 11)::int;
        ELSE
            fit := 12 + floor(random() * 34)::int; res := 6 + floor(random() * 30)::int; dm := floor(random() * 11)::int;
        END IF;
        total := fit + res + dm;
        -- The newest companies are still in research; the rest are scored.
        IF created > now() - interval '20 hours' THEN st := (ARRAY['new','researching','researched'])[1 + i % 3];
        ELSIF total < 40 THEN st := 'ignored';
        ELSIF total < 55 THEN st := 'scored';
        ELSE st := 'ready';
        END IF;

        INSERT INTO companies (name, domain, website, country, industry, employee_count, description,
                               tech_stack, source, status, segment, created_at, updated_at,
                               fit_score, research_score, decision_maker_score)
        VALUES (nm, dom, 'https://' || dom, country, industry,
                CASE WHEN line = 'infrastructure' THEN 15 + floor(random() * 100)::int ELSE 4 + floor(random() * 40)::int END,
                CASE line WHEN 'infrastructure'
                    THEN nm || ' builds ' || lower(industry) || ' products for mid-market customers and runs its own production platform.'
                    ELSE nm || ' is a ' || replace(split_part(industry, '=', 2), '_', ' ') || ' business that handles orders, invoices and supplier email by hand.' END,
                techs, src, st, seg, created, created + interval '3 hours',
                CASE WHEN st IN ('new','researching','researched') THEN NULL ELSE fit END,
                CASE WHEN st IN ('new','researching','researched') THEN NULL ELSE res END,
                CASE WHEN st IN ('new','researching','researched') THEN NULL ELSE dm END)
        RETURNING id INTO c_id;

        -- Signals: what research found, each with its source.
        IF line = 'infrastructure' THEN
            sig_type := (ARRAY['hiring_devops','kubernetes_adoption','cloud_migration','reliability_problem','cloud_cost_problem'])[1 + i % 5];
            sig_text := CASE sig_type
                WHEN 'hiring_devops' THEN 'Open role: Senior Platform Engineer, open ' || (20 + i) || ' days, Terraform and Kubernetes required.'
                WHEN 'kubernetes_adoption' THEN 'Engineering blog describes moving the API from VMs to Kubernetes, migration in progress.'
                WHEN 'cloud_migration' THEN 'CTO talk announces a move from a single data centre to AWS this year.'
                WHEN 'reliability_problem' THEN 'Public status page shows four incidents in the last 30 days, two over an hour.'
                ELSE 'Job ad mentions reducing cloud spend as a first-quarter objective.' END;
        ELSE
            sig_type := (ARRAY['manual_process','hiring_manual_ops','tool_sprawl','volume_growth'])[1 + i % 4];
            sig_text := CASE sig_type
                WHEN 'manual_process' THEN 'Order form on the site asks customers to email a spreadsheet; orders are re-keyed by hand.'
                WHEN 'hiring_manual_ops' THEN 'Hiring an administrative assistant for data entry and invoice matching.'
                WHEN 'tool_sprawl' THEN 'Site links to four separate tools for orders, invoices, delivery and support.'
                ELSE 'Announced a second location and doubled the product catalogue this year.' END;
        END IF;
        IF st NOT IN ('new','researching') THEN
            INSERT INTO signals (company_id, signal_type, signal, source_url, confidence, created_at)
            VALUES (c_id, sig_type, sig_text, 'https://' || dom || (ARRAY['/careers','/blog','/about','/contact'])[1 + i % 4],
                    round((0.6 + random() * 0.38)::numeric, 2), created + interval '1 hour');
            IF i % 2 = 0 THEN
                INSERT INTO signals (company_id, signal_type, signal, source_url, confidence, created_at)
                VALUES (c_id, CASE line WHEN 'infrastructure' THEN 'hiring_engineering_growth' ELSE 'volume_growth' END,
                        CASE line WHEN 'infrastructure' THEN 'Engineering team grew from ' || (8 + i % 9) || ' to ' || (14 + i % 13) || ' people in a year (team page).'
                             ELSE 'Catalogue and opening hours expanded; a second warehouse address appears in the footer.' END,
                        'https://' || dom || '/team', round((0.55 + random() * 0.3)::numeric, 2), created + interval '1 hour')
                ON CONFLICT DO NOTHING;
            END IF;

            -- The research run, with the structure agents/research/schema.json defines.
            INSERT INTO agent_runs (agent_name, company_id, status, model, started_at, finished_at,
                                    prompt_tokens, output_tokens, input, output)
            VALUES ('research', c_id, 'success', 'qwen9-64k:latest', created + interval '40 minutes',
                    created + interval '40 minutes' + make_interval(secs => 180 + floor(random() * 160)::int),
                    14000 + floor(random() * 9000)::int, 1400 + floor(random() * 900)::int,
                    jsonb_build_object('domain', dom),
                    jsonb_build_object(
                        'company_summary', nm || ' - ' || lower(industry) || ', about ' || (CASE WHEN line = 'infrastructure' THEN 30 + i ELSE 6 + i % 20 END) || ' people.',
                        'facts', jsonb_build_array(
                            jsonb_build_object('fact', sig_text, 'source', 'https://' || dom || '/careers', 'observed_at', to_char(created, 'YYYY-MM-DD')),
                            jsonb_build_object('fact', 'Headquartered in ' || country || '.', 'source', 'https://' || dom || '/about', 'observed_at', to_char(created, 'YYYY-MM-DD'))),
                        'technology', (SELECT jsonb_agg(jsonb_build_object('name', t, 'category', 'stack', 'evidence', 'Named on the careers or about page.',
                                                                           'source', 'https://' || dom || '/careers', 'confidence', 0.8))
                                       FROM jsonb_array_elements_text(techs) t),
                        'reasonable_inferences', jsonb_build_array(
                            jsonb_build_object('inference', CASE line WHEN 'infrastructure'
                                THEN 'No dedicated platform team yet; product engineers carry on-call.'
                                ELSE 'Order handling depends on one or two people re-typing data.' END,
                                'based_on', 'Team page and open roles', 'confidence', 0.6)),
                        'unknown', jsonb_build_array('Current monthly cloud or software spend', 'Who owns operations day to day'),
                        'why_now', CASE line WHEN 'infrastructure' THEN 'An open infrastructure role for weeks means the gap is felt now.'
                                        ELSE 'Growth is adding volume to a process that is still manual.' END,
                        'recommended_service', offer,
                        'confidence', round((0.55 + random() * 0.35)::numeric, 2),
                        'sources', jsonb_build_array('https://' || dom || '/careers', 'https://' || dom || '/about')));
        END IF;

        IF st IN ('scored','ready') THEN
            INSERT INTO agent_runs (agent_name, company_id, status, model, started_at, finished_at, output)
            VALUES ('scoring', c_id, 'success', 'qwen9-64k:latest', created + interval '70 minutes',
                    created + interval '70 minutes' + make_interval(secs => 95 + floor(random() * 60)::int),
                    jsonb_build_object('fit_score', fit, 'research_score', res, 'decision_maker_score', dm, 'total_score', total,
                                       'recommended_offer', offer,
                                       'reason', 'Sourced ' || replace(sig_type, '_', ' ') || ' signal and a team size inside the band.'));
        END IF;

        -- A contact, a lead and a first message for companies worth writing to.
        CONTINUE WHEN st <> 'ready';
        fname := first_names[1 + (i * 7) % array_length(first_names, 1)];
        lname := last_names[1 + (i * 3) % array_length(last_names, 1)];
        title := CASE line WHEN 'infrastructure' THEN (ARRAY['CTO','VP Engineering','Head of Engineering'])[1 + i % 3]
                           ELSE (ARRAY['Owner','Managing Director','Operations Manager'])[1 + i % 3] END;
        INSERT INTO people (company_id, first_name, last_name, full_name, title, seniority, email, email_status,
                            kind, discovery_method, source_url)
        VALUES (c_id, fname, lname, fname || ' ' || lname, title,
                CASE WHEN title IN ('CTO','Owner','Managing Director') THEN 'c_level' WHEN title LIKE 'VP%' THEN 'vp' ELSE 'head' END,
                lower(translate(fname, 'čćšžđ', 'ccszd')) || '@' || dom, (ARRAY['valid','valid','guessed'])[1 + i % 3],
                'person', 'published_page', 'https://' || dom || '/team')
        RETURNING id INTO p_id;

        hook := CASE sig_type
            WHEN 'hiring_devops' THEN 'I saw the Senior Platform Engineer role has been open for a few weeks.'
            WHEN 'kubernetes_adoption' THEN 'Your engineering blog post on moving the API to Kubernetes caught my eye.'
            WHEN 'cloud_migration' THEN 'I noticed the plan to move off the data centre and onto AWS this year.'
            WHEN 'reliability_problem' THEN 'Your status page has had a busy month.'
            WHEN 'cloud_cost_problem' THEN 'Your job ad mentions bringing cloud spend down this quarter.'
            WHEN 'manual_process' THEN 'I noticed orders on your site arrive as emailed spreadsheets.'
            WHEN 'hiring_manual_ops' THEN 'I saw you are hiring someone for data entry and invoice matching.'
            WHEN 'tool_sprawl' THEN 'Your site sends customers to four different tools for one order.'
            ELSE 'Congratulations on the second location.' END;

        -- Pipeline position, oldest first: the oldest have been sent and some
        -- answered; the newest wait for approval.
        st := CASE
            WHEN created > now() - interval '4 days' THEN 'pending_approval'
            WHEN i % 11 = 0 THEN 'rejected'
            WHEN i % 13 = 0 THEN 'bounced'
            WHEN created > now() - interval '5 days' THEN 'approved'
            ELSE 'sent' END;
        sent := CASE WHEN st IN ('sent','bounced') THEN created + interval '20 hours' + make_interval(hours => i % 7) END;

        INSERT INTO leads (company_id, person_id, score, reason, recommended_offer, status, created_at)
        VALUES (c_id, p_id, total,
                'Sourced ' || replace(sig_type, '_', ' ') || ' signal; ' || title || ' named on the team page.',
                offer,
                CASE st WHEN 'pending_approval' THEN 'pending_approval' WHEN 'approved' THEN 'approved'
                        WHEN 'rejected' THEN 'rejected' ELSE 'contacted' END,
                created + interval '2 hours')
        RETURNING id INTO l_id;

        INSERT INTO outreach (lead_id, subject, body, status, approved_by, approved_at, rejection_reason, sent_at,
                              segment, campaign, variant, created_at, provider_message_id)
        VALUES (l_id,
                CASE line WHEN 'infrastructure' THEN (ARRAY['Platform role','Quick question about on-call','The Kubernetes move','Cloud costs'])[1 + i % 4]
                          ELSE (ARRAY['Orders by email','A question about invoices','Order handling'])[1 + i % 3] END,
                'Hi ' || fname || E',\n\n' || hook || E'\n\n'
                || CASE line WHEN 'infrastructure'
                     THEN 'Teams your size usually feel it as product engineers losing a day a week to infrastructure. I run a fixed-price infrastructure audit: two weeks, a written report, and a prioritised plan your team can run with.'
                     ELSE 'Businesses your size usually lose several hours a week to re-typing the same data. I do a short process audit that shows which steps can run by themselves, with a sample report you can read first.' END
                || E'\n\nWould it be useful to compare notes for 20 minutes next week?\n\n--\nYour Name\nYour Company\nhttps://example.com/\n\n'
                || 'Not the right person, or not interested? Reply "stop" and you will not hear from us again.',
                st,
                CASE WHEN st IN ('approved','sent','bounced') THEN 'telegram:demo' END,
                CASE WHEN st IN ('approved','sent','bounced') THEN created + interval '1 day' END,
                CASE WHEN st = 'rejected' THEN 'Hook too generic for this company' END,
                sent, seg,
                CASE WHEN seg = 'webshops' THEN 'ecommerce-process-audit-v1' END,
                jsonb_build_object('cta', 'question', 'language', 'en'),
                created + interval '3 hours',
                CASE WHEN sent IS NOT NULL THEN 'demo-' || md5(dom) END)
        RETURNING id INTO o_id;

        IF st IN ('sent','bounced') THEN
            UPDATE companies SET status = 'contacted' WHERE id = c_id;
        END IF;
        IF st = 'bounced' THEN
            UPDATE people SET email_status = 'bounced' WHERE id = p_id;
        END IF;

        -- Replies on about a quarter of what was sent.
        IF st = 'sent' AND i % 4 = 0 THEN
            cls := (ARRAY['POSITIVE','QUESTION','NOT_NOW','POSITIVE','NEGATIVE','PRICE','UNSUBSCRIBE'])[1 + i % 7];
            -- WF-08 keeps the message 'sent' and records when the reply came.
            UPDATE outreach SET reply_at = sent + interval '9 hours' WHERE id = o_id;
            UPDATE companies SET status = CASE WHEN cls IN ('POSITIVE','QUESTION','PRICE') THEN 'opportunity' ELSE 'replied' END WHERE id = c_id;
            INSERT INTO conversations (lead_id, channel, external_thread_id, status, last_message_at, created_at)
            VALUES (l_id, 'email', 'demo-thread-' || md5(dom),
                    CASE cls WHEN 'POSITIVE' THEN 'awaiting_human' WHEN 'QUESTION' THEN 'awaiting_human' WHEN 'PRICE' THEN 'escalated'
                             WHEN 'NOT_NOW' THEN 'nurture' WHEN 'UNSUBSCRIBE' THEN 'unsubscribed' ELSE 'closed_lost' END,
                    sent + interval '9 hours', sent + interval '9 hours')
            RETURNING id INTO cv_id;
            INSERT INTO messages (conversation_id, direction, author, subject, body, classification, classification_confidence, sent_at, created_at)
            VALUES (cv_id, 'inbound', 'prospect', 'Re: ' || (SELECT subject FROM outreach WHERE id = o_id),
                    CASE cls
                        WHEN 'POSITIVE' THEN 'Hi, good timing actually - we have been talking about exactly this. Does Thursday afternoon work?'
                        WHEN 'QUESTION' THEN 'Thanks. Can you send an example of what the report looks like?'
                        WHEN 'PRICE' THEN 'Interesting. What does this cost, roughly?'
                        WHEN 'NOT_NOW' THEN 'Not right now, we are mid-launch. Try me again in a couple of months.'
                        WHEN 'NEGATIVE' THEN 'We handle this in-house, thanks.'
                        ELSE 'Please remove me from your list.' END,
                    cls, round((0.78 + random() * 0.2)::numeric, 2), sent + interval '9 hours', sent + interval '9 hours');
            UPDATE leads SET status = CASE cls WHEN 'POSITIVE' THEN 'meeting' WHEN 'QUESTION' THEN 'replied' WHEN 'PRICE' THEN 'opportunity'
                                               WHEN 'NOT_NOW' THEN 'nurture' WHEN 'UNSUBSCRIBE' THEN 'suppressed' ELSE 'closed_lost' END,
                             deal_value_eur = CASE WHEN cls IN ('POSITIVE','PRICE') THEN CASE line WHEN 'infrastructure' THEN 6500 ELSE 1200 END END
            WHERE id = l_id;
            IF cls = 'UNSUBSCRIBE' THEN
                INSERT INTO suppression_list (email, reason, note)
                SELECT email, 'unsubscribe_request', 'demo' FROM people WHERE id = p_id
                ON CONFLICT DO NOTHING;
            END IF;
            IF cls IN ('POSITIVE','PRICE') THEN
                stage := CASE WHEN i % 2 = 0 THEN 'meeting' ELSE 'opportunity' END;
                INSERT INTO lead_events (lead_id, stage, note, actor, value_eur, created_at)
                VALUES (l_id, stage, 'Moved after the reply', 'telegram:demo',
                        CASE line WHEN 'infrastructure' THEN 6500 ELSE 1200 END, sent + interval '1 day');
            END IF;
        END IF;
    END LOOP;

    -- One won deal and one proposal, so revenue is not a row of zeros.
    UPDATE leads SET status = 'closed_won', deal_value_eur = 6500
    WHERE id = (SELECT l.id FROM leads l JOIN companies c ON c.id = l.company_id
                WHERE c.domain LIKE '%.example' AND l.status = 'meeting' ORDER BY l.created_at LIMIT 1);
    INSERT INTO lead_events (lead_id, stage, note, actor, value_eur, created_at)
    SELECT id, 'closed_won', 'Audit signed', 'telegram:demo', 6500, now() - interval '3 days'
    FROM leads WHERE status = 'closed_won' AND company_id IN (SELECT id FROM companies WHERE domain LIKE '%.example');
    UPDATE leads SET status = 'proposal'
    WHERE id = (SELECT l.id FROM leads l JOIN companies c ON c.id = l.company_id
                WHERE c.domain LIKE '%.example' AND l.status = 'meeting' ORDER BY l.created_at LIMIT 1);

    -- Background agent activity over the last day, with a couple of failures,
    -- so the system page has something to show.
    INSERT INTO agent_runs (agent_name, status, model, started_at, finished_at, error)
    SELECT (ARRAY['enrichment','classifier','outreach','enrichment','research'])[1 + g % 5],
           CASE WHEN g % 17 = 0 THEN 'error' WHEN g % 23 = 0 THEN 'timeout' ELSE 'success' END,
           CASE WHEN g % 5 IN (0, 3) THEN 'llama3.1:8b' ELSE 'qwen9-64k:latest' END,
           now() - make_interval(mins => g * 25), now() - make_interval(mins => g * 25) + make_interval(secs => 20 + g % 90),
           CASE WHEN g % 17 = 0 THEN 'model returned invalid JSON (truncated at max tokens)'
                WHEN g % 23 = 0 THEN 'timed out after 600000 ms' END
    FROM generate_series(1, 58) g;
END $$;
