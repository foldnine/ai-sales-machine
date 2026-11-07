-- 0023: give the night outreach batch the GPU to itself.
--
-- Regional first messages (OUTREACH_LANGUAGES) are written in Serbian by
-- qwen3.6:27b, because the 9B model's Serbian had errors in every draft
-- (2026-09-24). The two models do not fit in 24 GB together, so Ollama swaps
-- them: measured the same day, the first 27B draft waited 20 minutes behind
-- research on the 9B and the second took 57 seconds. Research and scoring run
-- all night on their schedules, so "the pipeline is idle at night" is not true
-- unless something makes it so.
--
-- WF-05 drafts regional leads only between OUTREACH_NIGHT_HOUR_START and
-- OUTREACH_NIGHT_HOUR_END, opening each run with input.window = 'night'. While
-- such a run is open, the claim queries of WF-02, WF-03 and WF-04 add
-- AND NOT night_drafting() and take nothing, as they do for deploy_draining();
-- the runs already going finish their batch. WF-05 itself does not start a
-- second night batch over the first.
--
-- A run that dies without being closed stops counting after an hour, so it
-- cannot hold the pipeline for the rest of the night.
CREATE OR REPLACE FUNCTION night_drafting() RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1
        FROM agent_runs
        WHERE agent_name = 'outreach'
          AND status     = 'running'
          AND input ->> 'window' = 'night'
          AND started_at > now() - interval '1 hour'
    );
$$;

COMMENT ON FUNCTION night_drafting() IS
    'True while a WF-05 night batch (the large outreach model) is running; other model workflows claim nothing (expires after 1 hour).';
