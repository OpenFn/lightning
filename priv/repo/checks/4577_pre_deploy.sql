-- Pre-deploy check for #4577 (unicode names).
--
-- Two conditions in existing data that this release turns from "works" into
-- "errors". Neither is fixed by code and neither has a backfill, so run this
-- against production before shipping and work through whatever it returns.
--
--   psql "$DATABASE_URL" -f priv/repo/checks/4577_pre_deploy.sql
--
-- An empty result from both halves means nothing to do.

\echo '== 1. Names that collide once hyphenated =========================='
-- A key in the project spec is the name with each space turned into a hyphen,
-- so `My Flow` and `My-Flow` become one key. The unique indexes are on the raw
-- name, so both rows exist today and the project exports fine, silently losing
-- one of the pair. This release refuses the whole export instead.
--
-- Consequence for a project in this state: GitHub sync stops, and the browser
-- download returns a JSON 400 through FallbackController rather than a flash.
-- Fix by renaming one of each pair before deploying.
WITH keyed AS (
  SELECT 'workflow' AS kind, w.project_id, p.name AS project, w.name,
         replace(w.name, ' ', '-') AS spec_key
    FROM workflows w JOIN projects p ON p.id = w.project_id
   WHERE w.deleted_at IS NULL
  UNION ALL
  SELECT 'collection', c.project_id, p.name, c.name, replace(c.name, ' ', '-')
    FROM collections c JOIN projects p ON p.id = c.project_id
  UNION ALL
  SELECT 'channel', ch.project_id, p.name, ch.name, replace(ch.name, ' ', '-')
    FROM channels ch JOIN projects p ON p.id = ch.project_id
  UNION ALL
  -- A credential key is "<owner email> <credential name>" hyphenated, scoped
  -- to the project through project_credentials.
  SELECT 'credential', pc.project_id, p.name, cr.name,
         replace(u.email || ' ' || cr.name, ' ', '-')
    FROM project_credentials pc
    JOIN credentials cr ON cr.id = pc.credential_id
    JOIN users u ON u.id = cr.user_id
    JOIN projects p ON p.id = pc.project_id
)
SELECT kind, project, spec_key, count(*) AS colliding, array_agg(name) AS names
  FROM keyed
 GROUP BY kind, project_id, project, spec_key
HAVING count(*) > 1
 ORDER BY kind, project;

\echo '== 2. Control characters in names and condition labels ============'
-- Workflow names never had a format rule, so a legacy row may hold a tab, a
-- newline or an escape. This release rejects them with no backfill, so such a
-- row is refused by any path that casts the name. Editing an unrelated field
-- still saves, because the rule fires on a change to the name and not on every
-- write, so this is narrower than it first looks. Condition labels are the
-- same: their rule used to sit inside the js_expression branch, so a label on
-- an :always edge was never checked.
--
-- The client deliberately stays lax here so a legacy row still loads; the
-- server does not. Fix by renaming, or accept that those rows are read-only
-- until someone does.
--
-- NUL is absent from the pattern because a text column cannot hold one.
-- U+FFFE and U+FFFF are present: Postgres stores both happily, so unlike NUL
-- their omission would not be justified by the column.
SELECT 'workflow.name' AS field, p.name AS project, w.id::text AS id,
       w.name AS value
  FROM workflows w JOIN projects p ON p.id = w.project_id
 WHERE w.deleted_at IS NULL
   AND w.name ~ E'[\\u0001-\\u001F\\u007F-\\u009F\\u2028\\u2029\\uFFFE\\uFFFF]'
UNION ALL
SELECT 'edge.condition_label', p.name, e.id::text, e.condition_label
  FROM workflow_edges e
  JOIN workflows w ON w.id = e.workflow_id
  JOIN projects p ON p.id = w.project_id
 WHERE e.condition_label IS NOT NULL
   AND e.condition_label ~ E'[\\u0001-\\u001F\\u007F-\\u009F\\u2028\\u2029\\uFFFE\\uFFFF]'
UNION ALL
-- workflow_templates.name had a length cap and no format rule at base, so a
-- legacy template name may hold a control character too. jobs.name and
-- credentials.name are deliberately absent: both were charset-restricted at
-- base, so no legacy row can hold one.
SELECT 'workflow_template.name', p.name, t.id::text, t.name
  FROM workflow_templates t
  JOIN workflows w ON w.id = t.workflow_id
  JOIN projects p ON p.id = w.project_id
 WHERE t.name ~ E'[\\u0001-\\u001F\\u007F-\\u009F\\u2028\\u2029\\uFFFE\\uFFFF]'
 ORDER BY field, project;
