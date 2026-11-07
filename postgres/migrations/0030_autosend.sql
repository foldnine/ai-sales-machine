-- 0030_autosend.sql
-- Guarded autosend: a first message that passes every check below is approved
-- without a human, for as long as the operator has it switched on.
--
-- It is off by default. Without it every draft waits at pending_approval for
-- /approve on Telegram. docs/roadmap.md phase 14 lists the
-- preconditions that were meant to come first; most were not met, and that
-- note is kept there rather than here.
--
-- An audit of human-approved messages found defects a human approval had let
-- through, and an unattended send must not:
--   - Cyrillic letters inside Latin Serbian text,
--   - wrong verb forms ("Ponudim", "Ponudite"),
--   - a role or title greeted instead of a person,
--   - national or multinational firms written to as if they were 5-50 people,
--   - the wrong language for the country,
--   - the same boilerplate sentences in different companies' emails.
-- And one hole no rule here can close: a reply read in a mail client while WF-08 was
-- down is never recorded, so the lead stays 'contacted'. A follow-up sent
-- automatically could land in the middle of a conversation. Follow-ups are
-- therefore never auto-approved.
--
-- Two switches, both the operator's:
--   OUTREACH_AUTOSEND_ENABLED in .env   the master. Anything but the exact
--                                        string "true" and nothing below
--                                        approves anything.
--   app_settings 'autosend'             on/off from Telegram: /autosend on,
--                                        /autosend off, /stop.
-- WF-06 still sends only inside OUTREACH_DAILY_LIMIT, the per-domain limit,
-- working hours, and never while OUTREACH_PAUSED is anything but "false".
--
-- Rollback (by hand, after a backup):
--   DROP FUNCTION autosend_command, autosend_decide, autosend_blockers,
--       autosend_sentences, autosend_text_language, autosend_model_text,
--       autosend_greeting, autosend_language_map, autosend_enabled;
--   DROP TABLE autosend_decisions;
--   DELETE FROM app_settings WHERE key IN ('autosend', 'autosend_deny_patterns');
--   restore command_log_outcome_check from 0014.

-- ---------------------------------------------------------------------------
-- 1. The runtime switch and the deny list
-- ---------------------------------------------------------------------------
INSERT INTO app_settings (key, value)
VALUES ('autosend', '{"enabled": false}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- Phrases that keep a draft from going out by itself. Postgres regular
-- expressions, matched case-insensitively against the subject and the whole
-- body. Over-blocking costs nothing but a Telegram approval, so a pattern may
-- be wider than the mistake it was written for: "ponudim" is grammatical in
-- "mogu da Vam ponudim", and is still held back.
--
-- Edit with SQL; the next draft uses the new list:
--   UPDATE app_settings SET value = value || '["\\mnovi izraz\\M"]'::jsonb
--   WHERE key = 'autosend_deny_patterns';
INSERT INTO app_settings (key, value)
VALUES ('autosend_deny_patterns', $json$[
    "\\mponudim\\M",
    "\\mponudite\\M",
    "\\mruche\\M",
    "sinkronizacij",
    "trenutna prioriteta",
    "\\myou type\\M",
    "\\myour team spends\\M",
    "\\mvi kucate\\M",
    "\\mvaš tim troši\\M",
    "\\mnadam se da ste dobro\\M",
    "javljam (vam|Vam) se jer",
    "rešenje po meri",
    "\\mreaching out\\M",
    "\\mcompanies like yours\\M",
    "\\{[a-z_]*\\}",
    "\\mundefined\\M",
    "\\[object Object\\]",
    "\\mnull\\M"
]$json$::jsonb)
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. command_log learns 'refused': /autosend on while the master switch is off
-- ---------------------------------------------------------------------------
ALTER TABLE command_log DROP CONSTRAINT command_log_outcome_check;
ALTER TABLE command_log ADD CONSTRAINT command_log_outcome_check CHECK (outcome IN (
    'applied', 'not_found', 'ambiguous', 'unknown', 'unauthorised', 'refused'
));

-- ---------------------------------------------------------------------------
-- 3. Every decision, kept: what /autosend and the daily report count
-- ---------------------------------------------------------------------------
CREATE TABLE autosend_decisions (
    id          bigserial PRIMARY KEY,
    outreach_id uuid NOT NULL REFERENCES outreach (id) ON DELETE CASCADE,
    approved    boolean NOT NULL,
    -- Why it was not approved, each "kind: detail". Empty when approved.
    reasons     text[] NOT NULL DEFAULT '{}',
    -- wf05: as the draft was queued. sweep: /autosend on, over the queue.
    source      text NOT NULL CHECK (source IN ('wf05', 'sweep')),
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX autosend_decisions_created_idx ON autosend_decisions (created_at DESC);
CREATE INDEX autosend_decisions_outreach_idx ON autosend_decisions (outreach_id);

COMMENT ON TABLE autosend_decisions IS
    'One row per autosend decision on a draft: approved, or held with its reasons. See 0030_autosend.sql.';

-- ---------------------------------------------------------------------------
-- 4. Helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION autosend_enabled() RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT COALESCE((SELECT value ->> 'enabled' = 'true'
                     FROM app_settings
                     WHERE key = 'autosend' AND jsonb_typeof(value) = 'object'), false);
$$;

-- OUTREACH_LANGUAGES ("RS:sr,HR:sr") as {"RS": "sr", "SERBIA": "sr", ...}.
-- Only a language prompts/outreach.md has a block for counts, as in WF-05's
-- Outreach Window: today that is "sr". Every other country is English.
CREATE OR REPLACE FUNCTION autosend_language_map(p_languages text) RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $$
    WITH pairs AS (
        SELECT upper(btrim(split_part(pair, ':', 1))) AS country,
               lower(btrim(split_part(pair, ':', 2))) AS lang
        FROM unnest(string_to_array(COALESCE(p_languages, ''), ',')) pair
        WHERE btrim(split_part(pair, ':', 1)) <> ''
          AND lower(btrim(split_part(pair, ':', 2))) IN ('sr')
    ),
    names (name, code) AS (VALUES
        ('SERBIA', 'RS'), ('BOSNIA AND HERZEGOVINA', 'BA'), ('MONTENEGRO', 'ME'),
        ('CROATIA', 'HR'), ('SLOVENIA', 'SI'), ('NORTH MACEDONIA', 'MK')
    )
    SELECT COALESCE(jsonb_object_agg(country, lang), '{}'::jsonb)
    FROM (SELECT country, lang FROM pairs
          UNION
          SELECT n.name, p.lang FROM names n JOIN pairs p ON p.country = n.code) x;
$$;

-- WF-05 assembles every draft as
--   [N/r: name, title]      a role contact marked for somebody (optional)
--   greeting                from prompts/signature.md
--   the model's text        one or more paragraphs
--   --\nsignature           from prompts/signature.md
--   [quoted earlier message, follow-ups only]
-- separated by blank lines. These two take it apart again.
CREATE OR REPLACE FUNCTION autosend_greeting(p_body text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT btrim(t)
    FROM unnest(regexp_split_to_array(COALESCE(p_body, ''), '\n\s*\n')) WITH ORDINALITY u(t, i)
    WHERE i <= 2 AND t !~* '^\s*(n/r|attn):'
    ORDER BY i
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION autosend_model_text(p_body text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    WITH p AS (
        SELECT t, i
        FROM unnest(regexp_split_to_array(COALESCE(p_body, ''), '\n\s*\n')) WITH ORDINALITY u(t, i)
    ),
    g AS (SELECT min(i) AS gi FROM p WHERE i <= 2 AND t !~* '^\s*(n/r|attn):'),
    s AS (SELECT COALESCE(min(i), 2147483647) AS si FROM p WHERE t ~ '^\s*--\s*(\n|$)')
    SELECT NULLIF(btrim(string_agg(btrim(p.t), E'\n\n' ORDER BY p.i)), '')
    FROM p, g, s
    WHERE p.i > g.gi AND p.i < s.si;
$$;

-- Which language a text is written in, by its function words: 'sr', 'en', or
-- 'unclear'. Deliberately simple and locale-independent (lower() folds only
-- ASCII under the C collation, so the five Serbian capitals are folded by
-- hand). A draft that reads as neither is held, which is the point.
CREATE OR REPLACE FUNCTION autosend_text_language(p_text text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    WITH w AS (
        SELECT translate(lower(x), 'ČĆŽŠĐ', 'čćžšđ') AS w
        FROM regexp_split_to_table(COALESCE(p_text, ''), '[^A-Za-zČĆŽŠĐčćžšđ]+') x
        WHERE x <> ''
    ),
    c AS (
        SELECT count(*) FILTER (WHERE w IN (
                   'je', 'da', 'se', 'su', 'za', 'na', 'u', 'sa', 'od', 'ste', 'li', 'vi',
                   'vaš', 'vaša', 'vaše', 'vašu', 'vašem', 'vašeg', 'vašoj', 'vam', 'vas',
                   'koji', 'koja', 'koje', 'koju', 'kako', 'što', 'šta', 'ali', 'ili',
                   'smo', 'sam', 'nije', 'može', 'mogu', 'ako', 'kao', 'iz', 'već', 'ovo',
                   'ovaj', 'obično', 'ručno', 'svaki', 'svakog', 'mesečno', 'kada', 'gde',
                   'posle', 'pre', 'bez', 'kod', 'preko', 'jer', 'samo', 'još', 'bi',
                   'biste', 'imate', 'radite', 'koristite', 'vreme', 'sati', 'ih', 'njih'))
                   AS sr,
               count(*) FILTER (WHERE w IN (
                   'the', 'and', 'of', 'is', 'you', 'your', 'for', 'with', 'that', 'this',
                   'are', 'we', 'can', 'how', 'what', 'it', 'be', 'or', 'in', 'at', 'by',
                   'an', 'have', 'does', 'if', 'from', 'which', 'when', 'who', 'would',
                   'usually', 'each', 'every', 'into', 'our', 'my', 'whether', 'there',
                   'they', 'their', 'than', 'then'))
                   AS en
        FROM w
    )
    SELECT CASE WHEN sr >= 3 AND sr > 2 * en THEN 'sr'
                WHEN en >= 3 AND en > 2 * sr THEN 'en'
                ELSE 'unclear' END
    FROM c;
$$;

-- The sentences of a text worth comparing for boilerplate: eight words or
-- more, lower-cased, punctuation removed.
CREATE OR REPLACE FUNCTION autosend_sentences(p_text text) RETURNS SETOF text
LANGUAGE sql IMMUTABLE AS $$
    SELECT n
    FROM (
        SELECT btrim(regexp_replace(translate(lower(s), 'ČĆŽŠĐ', 'čćžšđ'), '[^a-z0-9čćžšđ]+', ' ', 'g')) AS n
        FROM regexp_split_to_table(COALESCE(p_text, ''), '[.!?]+(\s+|$)|\n+') s
    ) x
    WHERE array_length(string_to_array(n, ' '), 1) >= 8;
$$;

-- ---------------------------------------------------------------------------
-- 5. autosend_blockers: why a draft may NOT go out by itself
-- ---------------------------------------------------------------------------
-- Empty array: nothing found, the draft may be auto-approved. Every reason is
-- "kind: detail", so /autosend can count them by kind. Pure SQL so make test
-- covers every rule.
--
-- p_languages is OUTREACH_LANGUAGES as n8n has it. NULL skips comparing the
-- mapping with what WF-05 recorded on the draft (variant.language, which it
-- took from the same mapping); the text itself is still checked against the
-- language the draft was meant to be in.
CREATE OR REPLACE FUNCTION autosend_blockers(p_outreach_id uuid, p_languages text DEFAULT NULL)
RETURNS text[]
LANGUAGE plpgsql STABLE AS $$
DECLARE
    o  outreach%ROWTYPE;
    l  leads%ROWTYPE;
    p  people%ROWTYPE;
    c  companies%ROWTYPE;
    b  text[] := '{}';
    v_text      text;
    v_model     text;
    v_greet     text;
    v_name      text;
    v_domain    text;
    v_brand     text;
    v_country   text;
    v_intended  text;
    v_expected  text;
    v_detected  text;
    v_hit       text;
    v_research  text;
    v_patterns  jsonb;
    pat         text;
    -- A role or a title where a first name belongs: "Poštovani direktore",
    -- "Dear CEO", "Dobar dan, Prodaja,". The words WF-05's claim already knows
    -- for a decision maker, and the usual names of a department or an inbox.
    -- "Tim" is left out: it is a first name.
    title_re constant text :=
        '\m(direktor\w*|director|ceo|cto|cfo|coo|owner|founder|co-?founder|vlasni\w*|osniva\w*|'
        || 'menad[zž]\w*|manager|rukovodi\w*|[sš]ef|[sš]efe|[sš]efic\w*|gospodin\w*|gospo[dđ]\w*|g-?din|g-?đa|'
        || 'kolega|kolege|team|sir|madam|admin\w*|office|info|kontakt|contact|prodaj\w*|sales|support|'
        || 'podr[sš]k\w*|ra[cč]unovod\w*|knjigovod\w*|accounting|marketing|uprav\w*|management|partner\w*|'
        || 'head|hr|sekretar\w*|referent\w*|komercijal\w*|slu[zž]b\w*|odeljenj\w*|department|customer|'
        || 'kupac|kupci|webshop|shop|prodavnic\w*|firm\w*|company|doo|ltd|gmbh|prokurist\w*|zastupnik\w*|'
        || 'lastnik\w*|poslovo[dđ]\w*)\M';
    -- What a national or multinational firm looks like in a research file.
    -- companies has no size flag; the research the draft was written from is
    -- the evidence there is, and the segments are written for 5-50 people.
    large_re constant text :=
        '(multinational|multinacional\w*|nationwide|national (network|chain|retailer|courier|leader|brand)|'
        || 'nacionaln\w* (mre[zž]\w*|lan\w*|lider\w*)|\mchain of\M|\mlanac\M|lanc\w* (prodavnic|radnj|apotek)|'
        || 'franšiz\w*|franchis\w*|[sš]irom (srbije|hrvatske|bih|bosne|crne gore|slovenije|regiona|zemlje)|'
        || 'u celoj (srbiji|hrvatskoj|zemlji|regiji|regionu)|international group|part of the [a-z ]+ group|'
        || 'subsidiary|[cć]erk\w* (firm|kompanij)|\m([1-9][0-9]|[0-9]{3,}) (stores|shops|branches|locations|'
        || 'outlets|vehicles|trucks|prodavnic\w*|poslovnic\w*|filijal\w*|objek\w*|vozil\w*|kamion\w*|radnj\w*)|'
        || '\m[0-9]{3,} (employees|people|staff|zaposlen\w*|radnik\w*))';
BEGIN
    SELECT * INTO o FROM outreach WHERE id = p_outreach_id;
    IF NOT FOUND THEN
        RETURN ARRAY['draft: does not exist'];
    END IF;
    SELECT * INTO l FROM leads     WHERE id = o.lead_id;
    SELECT * INTO p FROM people    WHERE id = l.person_id;
    SELECT * INTO c FROM companies WHERE id = l.company_id;

    v_text  := COALESCE(o.subject, '') || E'\n' || COALESCE(o.body, '');
    v_model := autosend_model_text(o.body);
    v_brand := domain_brand(c.domain::text);

    -- The draft itself ---------------------------------------------------------
    IF o.status <> 'pending_approval' THEN
        b := b || format('status: %s, not pending_approval', o.status);
    END IF;
    -- Follow-ups always go to the operator: a reply read in a mail client while WF-08 was down
    -- is never recorded, and the lead still looks unanswered.
    IF o.sequence_step <> 1 THEN
        b := b || format('follow-up: step %s, follow-ups always need the operator', o.sequence_step);
    END IF;
    IF o.channel <> 'email' THEN
        b := b || format('channel: %s', o.channel);
    END IF;
    IF v_model IS NULL THEN
        b := b || 'text: no message between the greeting and the signature'::text;
    END IF;

    -- Script: every outreach language is written in Latin letters.
    v_hit := substring(v_text FROM '\S*[Ѐ-ӿ]+\S*');
    IF v_hit IS NOT NULL THEN
        b := b || format('cyrillic: "%s" in Latin text', left(v_hit, 40));
    END IF;

    -- Known bad phrases --------------------------------------------------------
    SELECT value INTO v_patterns FROM app_settings WHERE key = 'autosend_deny_patterns';
    IF v_patterns IS NULL OR jsonb_typeof(v_patterns) <> 'array' THEN
        b := b || 'deny list: app_settings autosend_deny_patterns is missing'::text;
    ELSE
        FOR pat IN SELECT jsonb_array_elements_text(v_patterns) LOOP
            BEGIN
                v_hit := (regexp_match(v_text, '(' || pat || ')', 'i'))[1];
                IF v_hit IS NOT NULL THEN
                    b := b || format('phrase: "%s"', left(v_hit, 40));
                END IF;
            EXCEPTION WHEN invalid_regular_expression THEN
                b := b || format('deny list: pattern %s is not a valid regular expression', pat);
            END;
        END LOOP;
    END IF;

    -- The greeting -------------------------------------------------------------
    -- WF-05 writes "Hi {first_name}," / "Dobar dan, {first_name}," to a person
    -- and "Hello," / "Poštovani," to a general address (prompts/signature.md).
    -- A greeting that is none of those was not written by WF-05's envelope.
    v_greet := COALESCE(autosend_greeting(o.body), '');
    IF v_greet !~* '^(hi|hello|dobar dan|po[sš]tovan[ia])\M' THEN
        b := b || format('greeting: "%s" is not one WF-05 writes', left(v_greet, 40));
    ELSE
        v_name := btrim(regexp_replace(
                      regexp_replace(v_greet, '^(hi|hello|dobar dan|po[sš]tovan[ia])\M[\s,]*', '', 'i'),
                      '[\s,.!:;]+$', ''));
        IF v_name <> '' AND (v_name ~* title_re OR v_name ~ '[0-9@]') THEN
            b := b || format('greeting: "%s" addresses a role or title, not a person', left(v_greet, 40));
        ELSIF v_name = '' AND p.kind IS DISTINCT FROM 'role' THEN
            b := b || 'greeting: a named contact greeted without a name'::text;
        ELSIF v_name <> '' AND p.kind = 'role' THEN
            b := b || format('greeting: "%s" names somebody at a general address', left(v_greet, 40));
        END IF;
    END IF;

    -- The recipient ------------------------------------------------------------
    IF p.email IS NULL THEN
        b := b || 'recipient: no address'::text;
    ELSE
        v_domain := lower(split_part(p.email::text, '@', 2));
        IF p.email_status NOT IN ('valid', 'catch_all', 'guessed') THEN
            b := b || format('recipient: address is %s', p.email_status);
        END IF;
        IF is_suppressed(p.email) THEN
            b := b || format('suppressed: %s or its domain is on the suppression list', p.email);
        END IF;
        IF EXISTS (SELECT 1 FROM suppression_list s
                   WHERE s.reason = 'hard_bounce' AND s.email IS NOT NULL
                     AND lower(split_part(s.email::text, '@', 2)) = v_domain)
           OR EXISTS (SELECT 1 FROM people p2
                      WHERE p2.email_status = 'bounced'
                        AND lower(split_part(p2.email::text, '@', 2)) = v_domain)
           OR EXISTS (SELECT 1 FROM outreach o2
                      JOIN leads l2  ON l2.id = o2.lead_id
                      JOIN people p2 ON p2.id = l2.person_id
                      WHERE o2.status = 'bounced'
                        AND (lower(split_part(p2.email::text, '@', 2)) = v_domain
                             OR l2.company_id = c.id)) THEN
            b := b || format('bounced: an earlier message to %s bounced', v_domain);
        END IF;
    END IF;

    -- Somebody is already talking to us ---------------------------------------
    IF l.status NOT IN ('new', 'pending_approval', 'approved', 'contacted') THEN
        b := b || format('lead: status is %s', l.status);
    END IF;
    IF EXISTS (SELECT 1 FROM conversations cv WHERE cv.lead_id = l.id) THEN
        b := b || 'conversation: this lead already has a thread'::text;
    END IF;
    IF EXISTS (SELECT 1 FROM outreach o2
               WHERE o2.lead_id = l.id AND o2.id <> o.id
                 AND o2.status IN ('approved', 'queued', 'sent', 'bounced', 'replied')) THEN
        b := b || 'conversation: this lead was already written to'::text;
    END IF;
    -- The whole brand (0027): shopbrand.example and ba.shopbrand.example are one company.
    IF EXISTS (SELECT 1 FROM companies c2
               JOIN leads l2 ON l2.company_id = c2.id
               JOIN conversations cv ON cv.lead_id = l2.id
               JOIN messages m ON m.conversation_id = cv.id
               WHERE domain_brand(c2.domain::text) = v_brand AND m.direction = 'inbound') THEN
        b := b || format('conversation: somebody at %s has written to us', c.domain);
    END IF;
    IF EXISTS (SELECT 1 FROM companies c2
               JOIN leads l2 ON l2.company_id = c2.id
               JOIN outreach o2 ON o2.lead_id = l2.id
               WHERE domain_brand(c2.domain::text) = v_brand AND l2.id <> l.id
                 AND o2.status IN ('approved', 'queued', 'sent', 'bounced', 'replied')) THEN
        b := b || format('conversation: %s was already written to', c.domain);
    END IF;
    v_hit := (SELECT l2.status FROM companies c2 JOIN leads l2 ON l2.company_id = c2.id
              WHERE domain_brand(c2.domain::text) = v_brand AND l2.id <> l.id
                AND l2.status IN ('replied', 'opportunity', 'meeting', 'audit', 'proposal',
                                  'closed_won', 'closed_lost', 'suppressed', 'rejected')
              LIMIT 1);
    IF v_hit IS NOT NULL THEN
        b := b || format('conversation: another contact at %s is at %s', c.domain, v_hit);
    END IF;

    -- The company --------------------------------------------------------------
    IF c.status IN ('ignored', 'suppressed', 'won', 'lost', 'replied', 'opportunity') THEN
        b := b || format('company: status is %s', c.status);
    END IF;
    IF c.employee_count > 50 THEN
        b := b || format('size: %s employees, the segments are written for 5-50', c.employee_count);
    END IF;
    SELECT concat_ws(E'\n',
               r.output #>> '{analysis,company_summary}',
               (SELECT string_agg(f ->> 'fact', E'\n')
                FROM jsonb_array_elements(CASE WHEN jsonb_typeof(r.output #> '{analysis,facts}') = 'array'
                                               THEN r.output #> '{analysis,facts}' ELSE '[]'::jsonb END) f))
      INTO v_research
    FROM agent_runs r
    WHERE r.company_id = c.id AND r.agent_name = 'research' AND r.status = 'success'
    ORDER BY r.finished_at DESC NULLS LAST
    LIMIT 1;
    v_hit := (regexp_match(concat_ws(E'\n', v_research, c.description), large_re, 'i'))[1];
    IF v_hit IS NOT NULL THEN
        b := b || format('size: the research describes a large or national firm ("%s")', left(v_hit, 40));
    END IF;

    -- The segment --------------------------------------------------------------
    IF c.segment IS NULL THEN
        b := b || 'segment: the company is in no ICP segment'::text;
    ELSIF NOT EXISTS (SELECT 1 FROM icp_segments s WHERE s.code = c.segment AND s.active) THEN
        b := b || format('segment: %s is not active', c.segment);
    END IF;

    -- The language -------------------------------------------------------------
    v_country  := upper(btrim(COALESCE(c.country, '')));
    v_intended := NULLIF(o.variant ->> 'language', '');
    v_expected := CASE WHEN p_languages IS NULL THEN COALESCE(v_intended, 'en')
                       ELSE COALESCE(autosend_language_map(p_languages) ->> v_country, 'en') END;
    IF v_intended IS NOT NULL AND v_intended <> v_expected THEN
        b := b || format('language: written as %s, %s expects %s', v_intended,
                         COALESCE(NULLIF(v_country, ''), 'an unknown country'), v_expected);
    END IF;
    IF v_model IS NOT NULL THEN
        v_detected := autosend_text_language(COALESCE(o.subject, '') || E'\n' || v_model);
        IF v_detected <> v_expected THEN
            b := b || format('language: the text reads as %s, %s expects %s', v_detected,
                             COALESCE(NULLIF(v_country, ''), 'an unknown country'), v_expected);
        END IF;
    END IF;

    -- Boilerplate: a sentence another company's email already has --------------
    IF v_model IS NOT NULL THEN
        SELECT x INTO v_hit
        FROM (SELECT autosend_sentences(v_model) AS x
              INTERSECT
              SELECT autosend_sentences(autosend_model_text(o2.body))
              FROM outreach o2
              JOIN leads l2 ON l2.id = o2.lead_id
              WHERE o2.id <> o.id AND l2.company_id <> c.id
                AND o2.created_at > now() - interval '60 days') d
        LIMIT 1;
        IF v_hit IS NOT NULL THEN
            b := b || format('boilerplate: "%s" is in another company''s email', left(v_hit, 60));
        END IF;
    END IF;

    RETURN b;
END;
$$;

COMMENT ON FUNCTION autosend_blockers(uuid, text) IS
    'Reasons a draft may not be auto-approved ("kind: detail"); empty means it may. See 0030_autosend.sql.';

-- ---------------------------------------------------------------------------
-- 6. autosend_decide: approve one draft if autosend is on and nothing blocks
-- ---------------------------------------------------------------------------
-- Called by WF-05 right after a draft reaches pending_approval, and by the
-- sweep in /autosend on. Returns one row; zero for a NULL id.
--
-- autosend_active is false, and nothing is touched or recorded, unless the
-- master switch (p_env_enabled, OUTREACH_AUTOSEND_ENABLED) and the runtime
-- switch are both on. A failure inside the checks holds the draft rather than
-- failing the workflow: a draft that errors here must still reach the operator.
CREATE OR REPLACE FUNCTION autosend_decide(p_outreach_id uuid, p_env_enabled boolean,
                                           p_languages text, p_source text DEFAULT 'wf05')
RETURNS TABLE (draft_id uuid, autosend_active boolean, auto_approved boolean, blockers text[])
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_active   boolean := COALESCE(p_env_enabled, false) AND autosend_enabled();
    v_reasons  text[]  := '{}';
    v_lead     uuid;
    v_approved boolean := false;
BEGIN
    IF p_outreach_id IS NULL THEN
        RETURN;
    END IF;
    IF NOT v_active THEN
        RETURN QUERY SELECT p_outreach_id, false, false, '{}'::text[];
        RETURN;
    END IF;

    -- Hold the row while it is judged, so a /reject arriving now is not lost.
    PERFORM 1 FROM outreach o WHERE o.id = p_outreach_id FOR UPDATE;

    BEGIN
        v_reasons := autosend_blockers(p_outreach_id, p_languages);
    EXCEPTION WHEN OTHERS THEN
        v_reasons := ARRAY['error: ' || left(SQLERRM, 200)];
    END;

    IF cardinality(v_reasons) = 0 THEN
        UPDATE outreach o
        SET status           = 'approved',
            approved_by      = 'autosend',
            approved_at      = now(),
            rejection_reason = NULL
        WHERE o.id = p_outreach_id AND o.status = 'pending_approval'
        RETURNING o.lead_id INTO v_lead;
        IF v_lead IS NOT NULL THEN
            v_approved := true;
            -- As /approve does (WF-11).
            UPDATE leads SET status = 'approved' WHERE id = v_lead AND status = 'pending_approval';
        ELSE
            v_reasons := ARRAY['status: no longer pending_approval'];
        END IF;
    END IF;

    INSERT INTO autosend_decisions (outreach_id, approved, reasons, source)
    VALUES (p_outreach_id, v_approved, v_reasons, COALESCE(p_source, 'wf05'));

    RETURN QUERY SELECT p_outreach_id, true, v_approved, v_reasons;
END;
$$;

COMMENT ON FUNCTION autosend_decide(uuid, boolean, text, text) IS
    'Auto-approve one pending draft when OUTREACH_AUTOSEND_ENABLED and app_settings autosend are on and autosend_blockers() is empty. See 0030_autosend.sql.';

-- ---------------------------------------------------------------------------
-- 7. autosend_command: /autosend on|off|status and /stop, from WF-11
-- ---------------------------------------------------------------------------
-- WF-11 calls this only for the operator's chat and only once per Telegram update
-- (command_log). Returns the reply, in Serbian.
--
--   on      refused unless the master switch is on. Turns autosend on and
--           sweeps the queue: every pending draft is judged now, the clean
--           ones are approved.
--   off     (/stop) turns it off, and puts back to pending_approval every draft
--           autosend approved that has not been claimed for sending yet. Stop
--           means stop: nothing approved by the machine goes out after it.
--   status  on or off, what it approved and held today, and why.
CREATE OR REPLACE FUNCTION autosend_command(p_command text, p_actor text, p_env_enabled boolean,
                                            p_languages text, p_timezone text, p_paused boolean)
RETURNS text
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_cmd      text := lower(btrim(COALESCE(p_command, 'status')));
    v_tz       text := COALESCE(NULLIF(btrim(p_timezone), ''), 'UTC');
    v_env      boolean := COALESCE(p_env_enabled, false);
    v_today    timestamptz;
    v_ids      uuid[];
    v_approved int := 0;
    v_held     int := 0;
    v_back     int := 0;
    v_inflight int := 0;
    v_sent     int := 0;
    v_top      text;
    d          record;
    r          record;
BEGIN
    v_today := date_trunc('day', now() AT TIME ZONE v_tz) AT TIME ZONE v_tz;

    IF v_cmd IN ('stop', 'off') THEN
        INSERT INTO app_settings (key, value)
        VALUES ('autosend', jsonb_build_object('enabled', false, 'changed_by', p_actor, 'changed_at', now()))
        ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

        -- The switch is off from here on, whatever happens below: the revert
        -- runs in its own subtransaction, so a failure in it cannot undo /stop.
        BEGIN
            -- A recipient suppressed since the approval cannot go back to
            -- pending_approval (the trigger on outreach refuses it); it is
            -- cancelled instead, which is what suppression means anyway.
            WITH back AS (
                UPDATE outreach o
                SET status           = CASE WHEN is_suppressed(pe.email) THEN 'cancelled' ELSE 'pending_approval' END,
                    approved_by      = NULL,
                    approved_at      = NULL,
                    rejection_reason = CASE WHEN is_suppressed(pe.email)
                                            THEN 'cancelled by /stop: recipient suppressed' END
                FROM leads l0
                JOIN people pe ON pe.id = l0.person_id
                WHERE l0.id = o.lead_id
                  AND o.status = 'approved' AND o.approved_by = 'autosend'
                RETURNING o.lead_id, o.status
            ),
            leads_back AS (
                UPDATE leads l SET status = 'pending_approval'
                WHERE l.id IN (SELECT lead_id FROM back WHERE status = 'pending_approval')
                  AND l.status = 'approved'
                RETURNING l.id
            )
            SELECT count(*)::int INTO v_back FROM back;
        EXCEPTION WHEN OTHERS THEN
            RETURN concat_ws(E'\n',
                'Autosend isključen. Novi draftovi idu na odobrenje.',
                'Ali vraćanje već odobrenih nije uspelo (' || left(SQLERRM, 150) || ').',
                'Ako ne smeju da odu: OUTREACH_PAUSED=true u .env i make deploy.');
        END;
        SELECT count(*)::int INTO v_inflight FROM outreach WHERE status = 'queued' AND approved_by = 'autosend';

        RETURN concat_ws(E'\n',
            'Autosend isključen. Novi draftovi idu na odobrenje.',
            CASE WHEN v_back > 0 THEN
                format('%s automatski odobrenih, a još neposlatih, vraćeno je na odobrenje (/leads).', v_back) END,
            CASE WHEN v_inflight > 0 THEN
                format('%s je već u slanju i ne može se zaustaviti.', v_inflight) END,
            'Ponovo uključuje samo /autosend on.');
    END IF;

    IF v_cmd = 'on' THEN
        IF NOT v_env THEN
            RETURN concat_ws(E'\n',
                'Autosend nije uključen: glavni prekidač OUTREACH_AUTOSEND_ENABLED u .env nije true.',
                'Postavi OUTREACH_AUTOSEND_ENABLED=true, pokreni make deploy, pa pošalji /autosend on.');
        END IF;

        INSERT INTO app_settings (key, value)
        VALUES ('autosend', jsonb_build_object('enabled', true, 'changed_by', p_actor, 'changed_at', now()))
        ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

        SELECT array_agg(o.id ORDER BY o.created_at) INTO v_ids
        FROM outreach o WHERE o.status = 'pending_approval';
        FOR r IN SELECT unnest(COALESCE(v_ids, '{}'::uuid[])) AS id LOOP
            SELECT * INTO d FROM autosend_decide(r.id, true, p_languages, 'sweep');
            IF d.auto_approved THEN v_approved := v_approved + 1; ELSE v_held := v_held + 1; END IF;
        END LOOP;

        SELECT string_agg(format('%s %s', kind, n), ', ' ORDER BY n DESC, kind) INTO v_top
        FROM (SELECT split_part(x, ':', 1) AS kind, count(*)::int AS n
              FROM autosend_decisions a, unnest(a.reasons) x
              WHERE a.source = 'sweep' AND a.outreach_id = ANY (COALESCE(v_ids, '{}'::uuid[]))
                AND a.created_at >= now() - interval '1 minute' AND NOT a.approved
              GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 4) t;

        RETURN concat_ws(E'\n',
            'Autosend uključen. Prvi mejl koji prođe sve provere ide u slanje bez tvog odobrenja; follow-upovi i dalje čekaju tebe.',
            format('Red za odobrenje: %s odobreno automatski, %s ostaje tebi.', v_approved, v_held),
            CASE WHEN v_top IS NOT NULL THEN 'Najčešći razlozi: ' || v_top END,
            CASE WHEN COALESCE(p_paused, true) THEN
                'Pažnja: OUTREACH_PAUSED nije false, pa WF-06 trenutno ne šalje ništa.' END,
            '/stop isključuje autosend; /autosend pokazuje stanje.');
    END IF;

    -- status
    SELECT count(DISTINCT a.outreach_id) FILTER (WHERE a.approved)::int,
           count(DISTINCT a.outreach_id) FILTER (WHERE NOT a.approved)::int
      INTO v_approved, v_held
    FROM autosend_decisions a
    WHERE a.created_at >= v_today;
    SELECT count(*)::int INTO v_sent
    FROM outreach o WHERE o.approved_by = 'autosend' AND o.sent_at >= v_today;
    SELECT string_agg(format('%s %s', kind, n), ', ' ORDER BY n DESC, kind) INTO v_top
    FROM (SELECT split_part(x, ':', 1) AS kind, count(*)::int AS n
          FROM autosend_decisions a, unnest(a.reasons) x
          WHERE a.created_at >= v_today AND NOT a.approved
          GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 4) t;

    RETURN concat_ws(E'\n',
        'Autosend: ' || CASE WHEN v_env AND autosend_enabled() THEN 'UKLJUČEN'
                             WHEN autosend_enabled() THEN 'isključen (glavni prekidač OUTREACH_AUTOSEND_ENABLED nije true)'
                             ELSE 'isključen' END,
        format('Danas automatski odobreno: %s (poslato %s)', v_approved, v_sent),
        format('Danas zadržano za tebe: %s', v_held)
            || CASE WHEN v_top IS NOT NULL THEN ' — ' || v_top ELSE '' END,
        CASE WHEN COALESCE(p_paused, true) THEN 'OUTREACH_PAUSED nije false: WF-06 ne šalje ništa.' END,
        CASE WHEN v_env AND autosend_enabled() THEN '/stop isključuje autosend.'
             WHEN v_env THEN '/autosend on ga uključuje.' END);
END;
$$;

COMMENT ON FUNCTION autosend_command(text, text, boolean, text, text, boolean) IS
    'WF-11 /autosend on|off|status and /stop. Returns the Telegram reply. See 0030_autosend.sql.';
