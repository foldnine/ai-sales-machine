-- 0027: what a regional draft may claim, and one company one email.
--
-- The first night of regional drafts (2026-10-02) gave 12, and five of them
-- had to be rejected for reasons a rule can catch:
--   - two accounting offices in Bosnia were told about SEF, and
--     one in Slovenia the day before. SEF is Serbia's e-invoicing system; the segment
--     angles named it for every country.
--   - shopbrand.example and ba.shopbrand.example are one company with two domains, and
--     both got a draft in the same batch.
--   - AKS and D Express are national courier networks (558 trucks, 35 shops),
--     not the 5-50 person firms the segments are written for. That one is a
--     judgement on the research file and lives in prompts/outreach.md.

-- 1. The angles describe the work; the country's own systems come from
--    country_facts, so a draft to Montenegro cannot inherit Serbia's.
UPDATE icp_segments
SET angle = replace(angle, 'e-invoices entered into SEF by hand',
                    'e-invoices entered by hand into the country''s e-invoicing system (see COUNTRY)')
WHERE code = 'webshops';
UPDATE icp_segments
SET angle = replace(angle, 'pulling invoices out of SEF',
                    'pulling e-invoices out of the country''s e-invoicing system (see COUNTRY)')
WHERE code = 'accounting_offices';

-- 2. What may be said about a country's invoicing. WF-05 passes the row to the
--    model as COUNTRY, and Validate And Check blocks a draft that names a
--    system this table does not list for the recipient's country.
CREATE TABLE country_facts (
    country     text PRIMARY KEY CHECK (country ~ '^[A-Z]{2}$'),
    e_invoicing text NOT NULL,
    -- Names a draft to this country may use. Any other country's system named
    -- in a draft is a block (prompts/outreach.md, COUNTRY).
    systems     text[] NOT NULL DEFAULT '{}'
);

COMMENT ON TABLE country_facts IS
    'What a first message may say about a country''s invoicing systems; see 0027_draft_quality.sql.';

INSERT INTO country_facts (country, e_invoicing, systems) VALUES
('RS', 'B2B and public-sector e-invoices go through SEF (Sistem elektronskih faktura), mandatory since 2023. Retail receipts are fiscalized.',
 ARRAY['SEF', 'eFaktura', 'e-Faktura']),
('HR', 'Fiskalizacija 2.0: B2B e-invoices (eRačun) are mandatory from 1 January 2026, sent through an information intermediary.',
 ARRAY['eRačun', 'e-Račun', 'Fiskalizacija']),
('SI', 'E-invoices to the public sector go through UJP (eRačun). There is no B2B e-invoicing mandate yet; do not claim one.',
 ARRAY['eRačun', 'e-račun', 'UJP']),
('BA', 'There is no national e-invoicing system. Retail sales are fiscalized through fiscal devices. Do not mention e-invoicing.',
 ARRAY[]::text[]),
('ME', 'Every invoice is fiscalized online with the tax administration (EFI, e-fiskalizacija) since 2021.',
 ARRAY['EFI', 'e-fiskalizacija', 'fiskalizacija']),
('MK', 'There is no mandatory B2B e-invoicing. Do not mention e-invoicing.',
 ARRAY[]::text[]);

-- 3. The brand a domain belongs to: the registrable label without its public
--    suffix and without subdomains. shopbrand.example and ba.shopbrand.example are both
--    'shopbrand'; a name under a two-part suffix such as .com.hr keeps its own label; ba.appliance.example is 'appliance'.
CREATE OR REPLACE FUNCTION domain_brand(p_domain text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN d ~ '\.(com|co|org|net|edu|gov|in|ac)\.[a-z]{2}$'
            THEN split_part(regexp_replace(d, '\.(com|co|org|net|edu|gov|in|ac)\.[a-z]{2}$', ''), '.',
                            array_length(string_to_array(regexp_replace(d, '\.(com|co|org|net|edu|gov|in|ac)\.[a-z]{2}$', ''), '.'), 1))
        WHEN d LIKE '%.%'
            THEN split_part(regexp_replace(d, '\.[^.]+$', ''), '.',
                            array_length(string_to_array(regexp_replace(d, '\.[^.]+$', ''), '.'), 1))
        ELSE d
    END
    FROM (SELECT lower(regexp_replace(btrim(COALESCE(p_domain, '')), '^www\.', '')) AS d) x;
$$;

COMMENT ON FUNCTION domain_brand(text) IS
    'The brand label of a domain (shopbrand.example and ba.shopbrand.example -> shopbrand). WF-01 treats a known brand as already known; WF-05 writes one first message per brand. See 0027_draft_quality.sql.';

CREATE INDEX companies_domain_brand_idx ON companies (domain_brand(domain::text));
