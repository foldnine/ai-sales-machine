-- 0022_role_contacts.sql
-- Let a company's published general address (info@, office@, kontakt@) be a
-- contact, when nobody named can be reached.
--
-- Until now WF-03 recorded role addresses in agent_runs.output.role_addresses
-- and never wrote them to people: full_name is NOT NULL, and a made-up name to
-- satisfy it would put "Careers team" in the greeting of an email. On the
-- companies this pipeline now targets - small regional businesses, 10 to 200
-- people, e-commerce, agencies, logistics - the general address is very often
-- the only one published, so those companies could never become a lead at all.
--
-- It was decided on 2026-09-24 that outreach may go to such an address when no
-- named person with a contactable address was found. It is a business address
-- the company published so that it would be written to, which is the same
-- footing docs/security.md gives a published personal address. Every draft is
-- still approved by hand over Telegram; nothing about dispatch changes.
--
-- So a people row now has a kind. 'person' is everything that existed before
-- and means exactly what it meant. 'role' is a published general address with
-- no person behind it, and it carries NO name - full_name is NULL rather than
-- invented, so nothing downstream can greet it by one.
--
-- Nothing existing changes meaning: every current row becomes kind 'person'
-- and still satisfies every constraint, and for persons the name rule is the
-- one 0003 wrote.

-- 1. The kind.
ALTER TABLE people
    ADD COLUMN kind text NOT NULL DEFAULT 'person'
        CONSTRAINT people_kind_check CHECK (kind IN ('person', 'role'));

COMMENT ON COLUMN people.kind IS
    'person: a named individual. role: a published general address (info@, office@) with no person behind it, and no name. See 0022_role_contacts.sql.';

-- 2. Which local-parts may be written to. Only addresses a company publishes
--    for business contact. Jobs, support, billing, press, legal, abuse, no-reply
--    and the rest are addressed to a function that is not buying anything, and
--    writing to them is the kind of mail that gets a domain blocklisted. The
--    list and its reasons are in docs/contact-enrichment.md; WF-03 "Validate
--    And Verify" carries the same list plus the order it prefers them in, and
--    this function is what refuses a row if the two ever drift.
CREATE OR REPLACE FUNCTION is_outreach_role_address(check_email citext)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $fn$
    SELECT lower(split_part(check_email::text, '@', 1)) IN (
        'uprava', 'direkcija', 'management', 'office', 'ured', 'kancelarija',
        'info', 'informacije',
        'kontakt', 'kontakti', 'contact',
        'hello',
        'business',
        'enquiries', 'inquiries', 'enquiry', 'inquiry', 'upit', 'upiti',
        'general',
        'mail', 'email', 'posta',
        'sales', 'prodaja'
    );
$fn$;

COMMENT ON FUNCTION is_outreach_role_address(citext) IS
    'True when the local-part is a general business address outreach may use. See 0022_role_contacts.sql.';

-- 3. The name. Required and non-blank for a person, as before; absent for a
--    role, so that a role row can never be greeted by a name somebody made up.
ALTER TABLE people ALTER COLUMN full_name DROP NOT NULL;
ALTER TABLE people DROP CONSTRAINT people_full_name_check;
ALTER TABLE people ADD CONSTRAINT people_full_name_check CHECK (
    CASE kind
        WHEN 'person' THEN full_name IS NOT NULL AND length(btrim(full_name)) > 0
        ELSE full_name IS NULL
    END
);

-- 4. What a role row must be. An address, published on a page (not derived,
--    not from a commit), with the page recorded, on the allowlist, and with
--    none of the fields that describe a person.
ALTER TABLE people ADD CONSTRAINT people_role_contact_check CHECK (
    kind = 'person' OR (
        email IS NOT NULL
        AND is_outreach_role_address(email)
        AND discovery_method = 'published_page'
        AND source_url IS NOT NULL
        AND first_name IS NULL
        AND last_name IS NULL
        AND title IS NULL
        AND seniority IS NULL
        AND linkedin_url IS NULL
    )
);

-- 5. At most one role contact per company. WF-03 picks the best; the index
--    makes "one" true rather than intended.
--
--    people_company_name_key (0013) is untouched: a role row's full_name is
--    NULL, so it never takes part in that index, and for persons it means what
--    it meant. people_email_key still holds one row per address for both kinds.
--    people_contactable_idx still means "usable for outreach", and a role row
--    is exactly that.
CREATE UNIQUE INDEX people_one_role_per_company_key
    ON people (company_id) WHERE kind = 'role';

-- 6. The read models. Both views feed Telegram messages and the daily report
--    with full_name, which a role row does not have; NULL concatenated into a
--    notification title makes the whole title NULL. They now show the address
--    instead, labelled as what it is, and expose kind at the end so a reader
--    can tell the two apart without parsing the label.
CREATE OR REPLACE VIEW v_approval_queue AS
SELECT
    o.id            AS outreach_id,
    o.sequence_step,
    o.channel,
    o.subject,
    o.body,
    o.created_at,
    l.id            AS lead_id,
    l.score,
    l.reason,
    l.recommended_offer,
    COALESCE(p.full_name, p.email::text || ' (general address)') AS full_name,
    p.title,
    p.email,
    c.id            AS company_id,
    c.name          AS company_name,
    c.domain,
    c.score_band,
    p.kind          AS person_kind
FROM outreach o
JOIN leads     l ON l.id = o.lead_id
JOIN people    p ON p.id = l.person_id
JOIN companies c ON c.id = l.company_id
WHERE o.status = 'pending_approval'
ORDER BY l.score DESC NULLS LAST, o.created_at;

CREATE OR REPLACE VIEW v_open_opportunities AS
SELECT
    conv.id AS conversation_id,
    conv.status,
    conv.escalation_reason,
    conv.last_message_at,
    l.id    AS lead_id,
    l.score,
    l.recommended_offer,
    COALESCE(p.full_name, p.email::text || ' (general address)') AS full_name,
    p.email,
    c.name  AS company_name,
    c.domain,
    p.kind  AS person_kind
FROM conversations conv
JOIN leads     l ON l.id = conv.lead_id
JOIN people    p ON p.id = l.person_id
JOIN companies c ON c.id = l.company_id
WHERE conv.status IN ('awaiting_human', 'escalated')
ORDER BY conv.last_message_at DESC NULLS LAST;
