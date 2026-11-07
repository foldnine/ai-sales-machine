-- 0029: a fourth discovery source, Minimax's public directory of accounting
-- services, and the discovery budget moved to the segment that answers.
--
-- On 2026-10-02 the first reply this system ever received came from an
-- accounting office (Kontrol sistem, Novi Sad) 18 minutes after the email
-- went out, and it was about Minimax, the bookkeeping program it runs on.
-- Seven first emails had gone out by then; the webshops had sent four and
-- received nothing, with 5% of the researched ones at the segment's bar.
--
-- OpenStreetMap cannot feed that segment. The six countries' full extracts
-- hold 232 objects tagged office=accountant or named like one, 60 of them
-- with a website, and 49 were already in companies. Minimax publishes the
-- offices that use it, by country, so entrepreneurs can find a bookkeeper:
-- minimax.si 572 (259 with a usable domain), minimax.rs 464 (98),
-- minimax.hr 541 (78). Kontrol sistem is on the Serbian list. Every office
-- there keeps its clients' books in Minimax, which is a sourced fact about
-- the company, not a guess - the thing a segment email needs for line one.
--
-- infra/scripts/minimax-directory.sh fills directory_snapshot (make
-- minimax-refresh); WF-01 reads it the way it reads osm_snapshot.

ALTER TABLE discovery_seen DROP CONSTRAINT IF EXISTS discovery_seen_source_check;
ALTER TABLE discovery_seen ADD CONSTRAINT discovery_seen_source_check
    CHECK (source IN ('radar_yc', 'radar_hn', 'radar_osm', 'radar_minimax'));

ALTER TABLE companies DROP CONSTRAINT IF EXISTS companies_source_check;
ALTER TABLE companies ADD CONSTRAINT companies_source_check
    CHECK (source IN (
        'manual', 'apollo', 'radar_github', 'radar_jobs', 'radar_blog',
        'radar_funding', 'referral', 'import', 'radar_yc', 'radar_hn',
        'radar_osm', 'radar_minimax'
    ));

-- One row per directory and country, the page as parsed: a list of
-- {name, domain, website, email, address, city, slug}. Refreshed weekly at
-- most; a refresh that fails leaves the last good row.
CREATE TABLE directory_snapshot (
    source     text        NOT NULL CHECK (source IN ('radar_minimax')),
    country    text        NOT NULL CHECK (country ~ '^[A-Z]{2}$'),
    url        text        NOT NULL,
    entries    jsonb       NOT NULL CHECK (jsonb_typeof(entries) = 'array'),
    elements   integer     NOT NULL CHECK (elements >= 0),
    fetched_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (source, country)
);

COMMENT ON TABLE directory_snapshot IS
    'Public directories WF-01 reads as a discovery source (0029_minimax_directory.sql), filled by make minimax-refresh.';

-- The directory's offices are accounting offices by construction; nothing
-- here can file them anywhere else.
UPDATE icp_segments
SET sources       = array_append(sources, 'radar_minimax'),
    industry_like = array_append(industry_like, 'Minimax %')
WHERE code = 'accounting_offices'
  AND NOT 'radar_minimax' = ANY (sources);

-- Budget follows the answer. Accounting offices go from 10% to 30% of the
-- daily limit, taken from webshops (45% to 25%). At 120 a day that is 36
-- offices a day, the whole directory in about two weeks. Unused slots still
-- go to the other segments the same day.
UPDATE icp_segments SET discovery_share = CASE code
    WHEN 'accounting_offices' THEN 30
    WHEN 'webshops'           THEN 25
    ELSE discovery_share END
WHERE code IN ('accounting_offices', 'webshops');

-- The offer, with what the first reply taught: the documents an office
-- collects end up typed into Minimax, and Minimax has an inbox that can be
-- filled from outside (its API's AddInboxItem). "Nije sve savršeno" was the
-- office's own description of that inbox.
UPDATE icp_segments
SET angle = 'An accounting office. The repetitive work such offices usually do by hand: '
         || 'collecting documents from clients over email, WhatsApp, Viber or on paper and '
         || 'chasing the missing ones every month, typing purchase invoices into the '
         || 'bookkeeping program, matching bank statements against invoices, pulling '
         || 'e-invoices out of the country''s e-invoicing system (see COUNTRY), reminding '
         || 'clients about deadlines. If a signal says the office is listed in Minimax''s '
         || 'directory of accounting services, it works in Minimax: that is a sourced fact '
         || 'and a good line one, and the question is how client documents get into Minimax '
         || 'today (Minimax has an inbox that documents can be sent to automatically, already '
         || 'sorted by client and type). Never say or imply that the sender is a Minimax partner. '
         || 'Offer: a short analysis of how documents come in from clients and get booked, '
         || 'with the steps worth automating ranked by the hours they take each month.'
WHERE code = 'accounting_offices';
