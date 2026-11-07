-- 0021: let a deploy drain the pipeline before it restarts n8n.
--
-- A restart kills every execution in flight (CLAUDE.md, rule 7), so deploy.sh
-- waits until nothing runs. On a busy day that never happens: research takes
-- longer than its 30-minute schedule and the runs overlap. On 2026-09-24 a
-- deploy waited hours for a gap.
--
-- So deploy.sh writes app_settings 'deploy_drain' = the time it started
-- draining, and the claim query of every long-running workflow (WF-02, WF-03,
-- WF-04, WF-05) adds AND NOT deploy_draining(). New runs then claim nothing
-- and finish at once; the runs already going finish their batch; the deploy
-- restarts into an idle pipeline and deletes the key.
--
-- The flag expires by itself after two hours, so a deploy that dies half-way
-- cannot leave the pipeline paused. Anything that is not a timestamp reads as
-- not draining.
CREATE OR REPLACE FUNCTION deploy_draining() RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1
        FROM app_settings
        WHERE key = 'deploy_drain'
          AND jsonb_typeof(value) = 'string'
          AND (value #>> '{}') ~ '^\d{4}-\d{2}-\d{2}'
          AND (value #>> '{}')::timestamptz > now() - interval '2 hours'
    );
$$;

COMMENT ON FUNCTION deploy_draining() IS
    'True while deploy.sh is draining the pipeline before a restart (expires after 2 hours).';
