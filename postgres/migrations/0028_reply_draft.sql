-- 0028: a suggested reply on Telegram when someone answers with interest.
--
-- WF-08 classifies a reply and alerts on POSITIVE; a QUESTION or a PRICE
-- request is only escalated. Either way the operator then has to write the answer from
-- nothing, and the first answer's speed is most of what turns "zanima me" into
-- a conversation. WF-08 now drafts it (prompts/reply-draft.md) and sends the
-- draft as its own notification. Nothing is sent to the customer: the operator
-- copies it into their mail client and sends it in the thread themselves.
ALTER TABLE notifications DROP CONSTRAINT notifications_kind_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_kind_check CHECK (kind IN (
    'agent_failure',           -- WF-99
    'agent_health',            -- WF-101
    'company_hot',             -- WF-04
    'draft_ready',             -- WF-05
    'positive_reply',          -- WF-08
    'conversation_escalated',  -- WF-08
    'reply_draft',             -- WF-08, a suggested answer (0028)
    'daily_report',            -- WF-100
    'system'
));
