-- 0033: the web dashboard's access to the database.
--
-- The dashboard is a second way to approve a draft, next to /approve on
-- Telegram. A second way in is a second way to get something wrong, so it gets
-- less than the workflows do, not more:
--
--   * its own role, aisales_dashboard, that can read the public schema and
--     nothing in the n8n schema (where the credentials live);
--   * no INSERT, UPDATE or DELETE on any table. The only writes it can make
--     are the three functions below, SECURITY DEFINER, each doing exactly what
--     the Telegram command does and nothing else;
--   * every one of those writes is recorded in operator_actions, in the same
--     statement as the effect, so nothing it does is unlogged.
--
-- Approving changes a row's status and nothing more. WF-06 is still the only
-- thing that sends, inside OUTREACH_PAUSED, the daily limit, the send window
-- and the suppression trigger (0008) - which fires on this UPDATE too.
--
-- The role is created NOLOGIN. `make dashboard-role` (or ./install.sh) gives it
-- LOGIN and the password in DASHBOARD_DB_PASSWORD; a migration cannot read
-- .env, and a password must not live in a migration.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aisales_dashboard') THEN
        CREATE ROLE aisales_dashboard NOLOGIN;
    END IF;
END $$;

-- 1. What the operator did from the dashboard, one row per effect.
CREATE TABLE operator_actions (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor       text        NOT NULL,
    action      text        NOT NULL CHECK (action IN ('approve', 'reject', 'edit')),
    outreach_id uuid        NOT NULL REFERENCES outreach (id) ON DELETE CASCADE,
    detail      jsonb       NOT NULL DEFAULT '{}'::jsonb,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX operator_actions_outreach_idx ON operator_actions (outreach_id, created_at DESC);
CREATE INDEX operator_actions_created_idx  ON operator_actions (created_at DESC);

COMMENT ON TABLE operator_actions IS
    'Every write made from the web dashboard (0033): approve, reject, edit. Written by the dashboard_* functions in the same statement as the effect.';

-- 2. Approve. The same UPDATE as /approve (WF-11): only rows still waiting,
-- approved_by names where it came from, and the lead follows its draft.
CREATE OR REPLACE FUNCTION dashboard_approve(p_ids uuid[], p_actor text)
RETURNS TABLE (outreach_id uuid, outcome text)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_actor text := 'dashboard:' || COALESCE(NULLIF(btrim(p_actor), ''), 'operator');
BEGIN
    IF cardinality(COALESCE(p_ids, '{}')) = 0 OR cardinality(p_ids) > 100 THEN
        RAISE EXCEPTION 'approve between 1 and 100 drafts at a time';
    END IF;

    RETURN QUERY
    WITH approved AS (
        UPDATE outreach o
        SET status           = 'approved',
            approved_by      = v_actor,
            approved_at      = now(),
            rejection_reason = NULL
        WHERE o.id = ANY (p_ids)
          AND o.status = 'pending_approval'
        RETURNING o.id, o.lead_id
    ),
    lead_moved AS (
        UPDATE leads l SET status = 'approved'
        WHERE l.id IN (SELECT lead_id FROM approved)
        RETURNING l.id
    ),
    logged AS (
        INSERT INTO operator_actions (actor, action, outreach_id)
        SELECT v_actor, 'approve', a.id FROM approved a
        RETURNING operator_actions.outreach_id
    )
    SELECT i.id,
           CASE WHEN EXISTS (SELECT 1 FROM logged g WHERE g.outreach_id = i.id)
                THEN 'approved' ELSE 'not_pending' END
    FROM unnest(p_ids) AS i(id);
END $$;

-- 3. Reject, with the reason kept on the row as Telegram keeps it.
CREATE OR REPLACE FUNCTION dashboard_reject(p_id uuid, p_reason text, p_actor text)
RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_actor  text := 'dashboard:' || COALESCE(NULLIF(btrim(p_actor), ''), 'operator');
    v_reason text := left(COALESCE(NULLIF(btrim(p_reason), ''), 'rejected from the dashboard'), 500);
    v_lead   uuid;
BEGIN
    UPDATE outreach o
    SET status = 'rejected', rejection_reason = v_reason
    WHERE o.id = p_id AND o.status = 'pending_approval'
    RETURNING o.lead_id INTO v_lead;

    IF v_lead IS NULL THEN
        RETURN 'not_pending';
    END IF;

    UPDATE leads SET status = 'rejected' WHERE id = v_lead;
    INSERT INTO operator_actions (actor, action, outreach_id, detail)
    VALUES (v_actor, 'reject', p_id, jsonb_build_object('reason', v_reason));
    RETURN 'rejected';
END $$;

-- 4. Edit a waiting draft before approving it. The text a human approves is
-- the text that is sent (prompts/signature.md), so an edit is allowed - but
-- not one that removes the signature block WF-05 appended: that block carries
-- the sender's identity and the opt-out line, which are legal obligations,
-- not style. The previous text is kept in the log.
CREATE OR REPLACE FUNCTION dashboard_edit(p_id uuid, p_subject text, p_body text, p_actor text)
RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
    v_actor   text := 'dashboard:' || COALESCE(NULLIF(btrim(p_actor), ''), 'operator');
    v_old     outreach%ROWTYPE;
    v_sig     text;
    v_subject text := btrim(COALESCE(p_subject, ''));
    v_body    text := replace(COALESCE(p_body, ''), E'\r\n', E'\n');
BEGIN
    SELECT * INTO v_old FROM outreach WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR v_old.status <> 'pending_approval' THEN
        RETURN 'not_pending';
    END IF;
    IF v_subject = '' OR length(v_subject) > 200 THEN
        RAISE EXCEPTION 'subject must be 1-200 characters';
    END IF;
    IF length(btrim(v_body)) = 0 OR length(v_body) > 5000 THEN
        RAISE EXCEPTION 'body must be 1-5000 characters';
    END IF;

    -- The signature block starts at the last "--" line WF-05 wrote.
    IF position(E'\n--\n' IN v_old.body) > 0 THEN
        v_sig := substring(v_old.body FROM length(v_old.body)
                           - position(reverse(E'\n--\n') IN reverse(v_old.body)) - 2);
        IF position(btrim(v_sig) IN v_body) = 0 THEN
            RAISE EXCEPTION 'the signature and opt-out block must stay unchanged';
        END IF;
    END IF;

    IF v_subject IS NOT DISTINCT FROM v_old.subject AND v_body = v_old.body THEN
        RETURN 'unchanged';
    END IF;

    UPDATE outreach SET subject = v_subject, body = v_body WHERE id = p_id;
    INSERT INTO operator_actions (actor, action, outreach_id, detail)
    VALUES (v_actor, 'edit', p_id,
            jsonb_build_object('old_subject', v_old.subject, 'old_body', v_old.body));
    RETURN 'edited';
END $$;

-- 5. Privileges. Functions are executable by PUBLIC by default; these are not.
REVOKE ALL ON FUNCTION dashboard_approve(uuid[], text)         FROM PUBLIC;
REVOKE ALL ON FUNCTION dashboard_reject(uuid, text, text)      FROM PUBLIC;
REVOKE ALL ON FUNCTION dashboard_edit(uuid, text, text, text)  FROM PUBLIC;

GRANT USAGE ON SCHEMA public TO aisales_dashboard;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO aisales_dashboard;
-- Tables and views added by later migrations are readable too; still no writes.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO aisales_dashboard;
GRANT EXECUTE ON FUNCTION dashboard_approve(uuid[], text)        TO aisales_dashboard;
GRANT EXECUTE ON FUNCTION dashboard_reject(uuid, text, text)     TO aisales_dashboard;
GRANT EXECUTE ON FUNCTION dashboard_edit(uuid, text, text, text) TO aisales_dashboard;
-- Read-only helpers the views and pages call.
GRANT EXECUTE ON FUNCTION domain_brand(text) TO aisales_dashboard;
