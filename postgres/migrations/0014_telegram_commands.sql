-- 0014_telegram_commands.sql
-- What WF-11 needs to read commands from Telegram and act on them.
--
-- Telegram will not call this machine. n8n is bound to loopback, Caddy aborts
-- anything that is not localhost, and N8N_HOST is still a placeholder, so a
-- Telegram Trigger - which is a webhook - has nothing to receive on. WF-11
-- polls getUpdates instead, and polling needs two things a workflow cannot
-- hold by itself: somewhere to keep its place in the update stream, and a
-- record of who asked for what.

-- ---------------------------------------------------------------------------
-- app_settings: small, mutable operational state
-- ---------------------------------------------------------------------------
-- Not configuration. Configuration is .env, it is read at container start, and
-- it is deliberately not writable from a phone. This is for the handful of
-- values that have to change while the system is running, and the Telegram
-- update offset is the first of them.
CREATE TABLE app_settings (
    key        text PRIMARY KEY,
    value      jsonb NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE app_settings IS
    'Mutable operational state. Configuration belongs in .env, not here.';

CREATE TRIGGER app_settings_set_updated_at
    BEFORE UPDATE ON app_settings
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- getUpdates returns every update newer than `offset`. Telegram drops an update
-- only once it has been acknowledged by asking for a higher offset, so losing
-- this row means replaying up to 24 hours of commands - which command_log below
-- is what makes survivable.
INSERT INTO app_settings (key, value)
VALUES ('telegram_update_offset', '0'::jsonb);

-- ---------------------------------------------------------------------------
-- command_log: who asked for what, and what happened
-- ---------------------------------------------------------------------------
-- docs/telegram.md: "Commands that change state are recorded with the chat id
-- and timestamp, because 'who approved this' is a question that gets asked
-- after something goes wrong."
--
-- It is recorded here rather than left to n8n's execution history on purpose.
-- WF-11 has to put the bot token in a URL, because the Telegram API carries it
-- in the path and offers no header to put it in instead, so that workflow saves
-- no execution data at all. This table is the audit trail, and it is a better
-- one: it survives execution pruning and it can be queried.
CREATE TABLE command_log (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Telegram's own id for the update. UNIQUE is not bookkeeping: it is what
    -- makes a replayed update a no-op. If WF-11 acts on a command and then
    -- fails before saving the new offset, the next run sees that update again,
    -- and this constraint is what stops the same draft being approved twice.
    update_id  bigint UNIQUE NOT NULL,

    chat_id    text NOT NULL,
    command    text NOT NULL,
    argument   text,

    outcome    text NOT NULL CHECK (outcome IN (
        'applied',        -- the command did what it said
        'not_found',      -- the id matched no row in a state the command accepts
        'ambiguous',      -- a short id matched more than one row
        'unknown',        -- not a command this system has
        'unauthorised'    -- a chat id that is not TELEGRAM_CHAT_ID
    )),
    detail     text,

    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX command_log_created_idx ON command_log (created_at DESC);
CREATE INDEX command_log_chat_idx    ON command_log (chat_id, created_at DESC);

COMMENT ON COLUMN command_log.update_id IS
    'Telegram update id. UNIQUE makes a replayed update idempotent.';

-- ---------------------------------------------------------------------------
-- Approving and rejecting by a short id
-- ---------------------------------------------------------------------------
-- docs/telegram.md: "The id is short. It gets typed on a phone." The approval
-- message prints the first four characters of the uuid, so the lookup has to
-- accept a prefix - and has to refuse rather than guess when a prefix matches
-- more than one row, which is the whole reason this is a function and not a
-- LIKE in the workflow.
--
-- Only a row at pending_approval is eligible. Approving something already sent,
-- rejected or failed is not a thing that should quietly succeed.
CREATE OR REPLACE FUNCTION resolve_outreach_prefix(p_prefix text)
RETURNS TABLE (outreach_id uuid, matches int)
LANGUAGE sql STABLE AS $$
    WITH hits AS (
        SELECT o.id
        FROM outreach o
        -- At least four characters. An empty prefix matches every row, and
        -- when exactly one draft is queued that would make a bare "/approve"
        -- with no argument approve it - a fat-fingered send, from a typo.
        WHERE length(btrim(p_prefix)) >= 4
          AND o.status = 'pending_approval'
          AND o.id::text LIKE lower(btrim(p_prefix)) || '%'
        LIMIT 2
    )
    -- array_agg rather than min: there is no min(uuid) in Postgres, and the
    -- CASE means the aggregate is only read when exactly one row matched.
    SELECT CASE WHEN count(*) = 1 THEN (array_agg(hits.id))[1] ELSE NULL END,
           count(*)::int
    FROM hits;
$$;

COMMENT ON FUNCTION resolve_outreach_prefix(text) IS
    'Resolve a short outreach id typed on a phone. Returns NULL unless exactly one pending_approval row matches.';
