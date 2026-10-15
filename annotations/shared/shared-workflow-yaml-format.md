---
id: shared-workflow-yaml-format
type: shared
title: Workflow YAML format and import errors
status: not-started
owner:

trigger:
  old_route: >-
    no route of its own; runs in the browser wherever the collaborative editor turns workflow YAML
    into a workflow: the YAML import dialog, the template browser and "Build from scratch" on
    /projects/:project_id/w/new, and AI assistant apply, undo and redo on /w/new and /w/:id
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the host surface is mounted (workflow-editor-new, workflow-editor-ai-assistant); the parser itself has no gate
    - writing the parsed workflow into the shared document needs edit rights (createWorkflowStore.ts:1896)

inherits:
  - shared-editor-session        # the parsed workflow lands in the shared Y.Doc; saving and save errors are owned there

url_params: []

config_variants:
  default: {}                    # read under this one; nothing in the parser depends on config or build

inventory:
  routes: []
  events: []                     # validate_workflow_name, list_templates and publish_template are owned by their views
  js_hooks:
    - assets/js/yaml/util.ts parseWorkflowYAML (format-aware entry point, util.ts:41-58)
    - assets/js/yaml/format.ts parseWorkflow, detectFormat, serializeWorkflow (format.ts:19-35)
    - assets/js/yaml/v1.ts parseWorkflow, convertWorkflowSpecToState, convertWorkflowStateToSpec (AI payload only)
    - assets/js/yaml/v2.ts parseWorkflow, serializeWorkflow, detectFormat
    - assets/js/yaml/workflow-errors.ts WorkflowError classes, createWorkflowError, formatWorkflowError
    - assets/js/yaml/schema/workflow-spec.json, workflow-spec-v2.json
    - assets/js/collaborative-editor/adapters/YAMLStateToYDoc.ts applyToYDoc
    - assets/js/collaborative-editor/components/yaml-import/ValidationErrorDisplay.tsx
    - Phoenix hooks YAMLToWorkflow, TemplateToWorkflow, WorkflowToYAML (hooks/index.ts:8-10, :32-34; see 6.3)
  policies: []
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - parseWorkflowTemplate lenient parser (util.ts:66-93); only the dead TemplateToWorkflow hook calls it (6.3)
    - v1.parseWorkflowYAML, v1.parseWorkflowTemplate (v1.ts:208-226, :269-279); no caller outside the module (6.3)
    - validateWorkflowIds (utils/validateWorkflowIds.ts:9-57); the v1 schema already refuses object ids (6.3)
    - Lightning.Workflows.YamlFormat.V2 and Lightning.ExportUtils; server emitters only, owned by flow-export-project-yaml and the provisioning API

related:
  - workflow-editor-new                 # inherits: import dialog, templates, build from scratch
  - workflow-editor-ai-assistant        # inherits: apply, undo and redo of AI-written YAML
  - workflow-editor-inspectors          # code view and template publishing use the v2 serializer (CodeViewPanel.tsx:24-42; TemplatePublishPanel.tsx:116-140)
  - flow-export-project-yaml            # server v2 emitter this parser mirrors
  - assets/js/yaml/
  - assets/js/collaborative-editor/adapters/YAMLStateToYDoc.ts
  - assets/js/collaborative-editor/components/YAMLImportModal.tsx
  - assets/js/collaborative-editor/components/yaml-import/ValidationErrorDisplay.tsx
  - assets/js/collaborative-editor/utils/templateWorkflowState.ts
  - assets/js/collaborative-editor/hooks/useAIWorkflowApplications.ts
  - assets/js/collaborative-editor/hooks/useAIWorkflowUndo.ts
  - assets/js/collaborative-editor/stores/createWorkflowStore.ts (importWorkflow, deduplicateJobNames)
  - lib/lightning/workflows/yaml_format/v2.ex
  - lib/lightning/export_utils.ex
  - test/fixtures/portability/v1/canonical_workflow.yaml
  - test/fixtures/portability/v2/canonical_workflow.yaml
  - assets/test/yaml/util.test.ts
  - assets/test/yaml/v2.test.ts
  - assets/test/collaborative-editor/adapters/YAMLStateToYDoc.test.ts
  - assets/test/collaborative-editor/components/yaml-import/YAMLImportModal.test.tsx
  - test/lightning/workflows/yaml_format_v2_test.exs
flows:
  - flow-export-project-yaml            # referenced: the server v2 emitter is the other half of the format
---

## 1. Purpose

People move workflows into a project as YAML: a file exported from another project or instance, a
CLI project, a published template, or a workflow the AI assistant has written. This parser decides
what such a file means and refuses what it cannot represent, before anything reaches the shared
workflow. Without it, a file would either be rejected for no stated reason, or worse, land as a
workflow that quietly differs from the one that was exported: missing steps, rewired edges, or a
trigger that starts accepting data nobody asked for.

## 2. What it does

- **Read either format** (anyone importing a file, picking a template, or applying AI-written YAML)
  - Both workflow formats are accepted: v1 (separate jobs, triggers and edges) and v2 (one list of steps)
  - A workflow's steps, triggers and edge logic stay the same through export and re-import
- **Refuse what it can't represent**
  - Files that aren't valid YAML, don't match the format, or use a trigger type other than webhook or cron are refused
  - Edges to a step or trigger the file doesn't define are refused, and so (v1) are two steps whose names would export to the same key
  - Errors show with a code, a readable message and the path to the problem
- **Import safely** (editors, when the result is written into the workflow)
  - Triggers stay off unless the file turns them on
  - The id in a file never takes over another workflow
  - A re-applied file that doesn't mention a webhook path keeps the existing one

**Straightforwardness: 2 of 5.** Two formats, a browser-side check that is the only check, and duplicate-name rules that disagree between import and export, so a round trip can quietly lose or break things.

### Most surprising behaviours

- **(2)** In v2, a second step with the same id silently replaces the first. The code view can produce such a file when two step names differ only in case or a space versus a hyphen, so export then re-import loses a step with no error. (6.1)
- **(2)** Steps named "Fetch" and "fetch" import and save fine, but the project's YAML export then fails with a duplicate error. (6.1)
- **(2)** "Triggers stay off unless the file says so" doesn't help in practice: the blank workflow and both built-in templates turn their trigger on, so a new webhook is live and the sample schedule runs daily against example.com, even though the workflow is still a draft. (6.2)
- **(3)** Credentials in a file are accepted and quietly dropped, and templates published from the canvas lose their layout. (6.2)
- **(3)** Published templates are shared across the whole instance, so every editor can see the job code of templates from projects they're not on. (6.2)

## 3. Who can do what

Source: the parser has no authorization; it runs in the viewer's browser. Writing its result into
the shared workflow is guarded by `guardWrite` (`createWorkflowStore.ts:1896`), which follows the
edit permission resolved by shared-editor-session. Host gates: workflow-editor-new (`:create_workflow`,
`collaborate.ex:35-59`) and workflow-editor-ai-assistant.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See parse errors on a host surface | as the host allows | yes | yes | yes | no | yes, when support access is on |
| Have a parsed workflow written into the shared workflow | no | yes | yes | yes | no | yes, when support access is on |

**Preconditions beyond role**
- The server never parses workflow YAML: template code is stored unvalidated (`workflow_template.ex:28-60`), and the provisioning API takes JSON in and only emits YAML (`provisioning_controller.ex:62`, `:188-199`). This browser parser is the only gate.

## 4. What it touches

**Reads**: none on the server. Input comes from the host: a pasted or uploaded file, `workflow_templates.code` (via `list_templates`), or an AI message.

**Writes**: the shared Y.Doc only, in one transaction that replaces name, jobs, triggers, edges and positions (`YAMLStateToYDoc.ts:127-203`); persistence belongs to shared-editor-session.

**Immediate side effects** (in the same request)
- Channel request `validate_workflow_name` before the write (`createWorkflowStore.ts:1802-1831`, `:1900-1909`); the naming rule is owned by workflow-editor-new
- Dangling cron cursor references are cleared inside the same transaction (`YAMLStateToYDoc.ts:195-201`)

**Deferred side effects** (later, elsewhere)
- none; triggers the file turns on go live only when the host saves (shared-editor-session)

**External, non-transactional effects**
- none

**Depends on config**
- none

**Product limits**
- One error is shown at a time, the most actionable one the schema check finds (6.2)

## 5. Scenarios

```gherkin
Feature: Workflow YAML format
  In order to move a workflow into a project without rebuilding it
  As someone importing, templating or applying workflow YAML
  I want a file to mean exactly what it says, or to be told what is wrong with it

  @S01 @pending
  Scenario Outline: Both workflow formats are accepted
    # Value: files from older Lightning exports, the provisioning API, the CLI and the current code view all import.
    # util.ts:41-58; format.ts:24-31; v2.ts:71-95; util.test.ts:253-294; YAMLImportModal.test.tsx:369-389
    Given the canonical workflow in <format> format
    When I import it
    Then the workflow has steps "ingest", "load", "maybe skip", "report failure" and "transform"
    And it has a cron trigger and a webhook trigger

    Examples:
      | format                                       |
      | v1 (top-level jobs, triggers and edges maps) |
      | v2 (top-level steps list, no jobs key)       |

  @S02 @pending
  Scenario: A workflow keeps its logic through export and re-import
    # Value: a workflow copied between projects or instances behaves the same, instead of silently rewiring.
    # v2.ts:254-414 (emit), :600-683 (parse); v2.test.ts:182-345; test/fixtures/portability/v2/canonical_workflow.yaml
    Given a workflow whose webhook replies "after_completion" and whose cron trigger runs "0 6 * * *" with cursor step "ingest"
    And "ingest" leads to "transform" on success, to "report failure" on failure, and to "maybe skip" on the JS condition "!state.errors && state.data" labelled "Skip when no errors" and disabled
    When I import the v2 YAML the code view produces for it
    Then the imported workflow has the same steps, adaptors and code
    And the same edges with the same conditions, label and disabled state
    And the same webhook reply, cron expression and cron cursor

  @S03 @pending
  Scenario Outline: v2 edge conditions keep their meaning
    # Value: conditions written by hand or by the CLI run the same way once imported.
    # v2.ts:600-625, :639-658; v2.test.ts:236-250
    Given a v2 file where step "a" has next "b" written as <next>
    When I import it
    Then the edge from "a" to "b" has condition <condition>

    Examples:
      | next                                  | condition                          |
      | b (a bare step id)                    | always                             |
      | { b: true }                           | always                             |
      | { b: { condition: on_job_failure } }  | on job failure                     |
      | { b: "state.data.ok" }                | JS expression "state.data.ok"      |
      | { b: false }                          | JS expression "false"              |

  @S04 @pending
  Scenario: Text that is not valid YAML is refused with the parser's reason
    # Value: the user is pointed at the formatting problem instead of a generic failure.
    # util.ts:51-54; workflow-errors.ts:60-69, :230-231; ValidationErrorDisplay.tsx:45-58; util.test.ts:296-298
    Given the YAML import dialog is open in paste mode
    When I paste "invalid: [syntax"
    Then I see "Validation Error" with the code "YAML_SYNTAX_ERROR"
    And the message starts "YAML syntax error:" and ends "Please check your YAML formatting."

  @S05 @pending
  Scenario Outline: A file that does not match the format names the field and its path
    # Value: users fix the exact field instead of guessing which part of a long file is wrong.
    # v1.ts:235-245, :281-298; v2.ts:142-148; workflow-errors.ts:108-157, :219-246; ValidationErrorDisplay.tsx:48-58
    Given the YAML import dialog is open in paste mode
    When I paste a v1 workflow where <problem>
    Then I see the code "<code>" and the path "<path>"

    Examples:
      | problem                                      | code                     | path                    |
      | job "fetch" has no "body"                    | SCHEMA_MISSING_PROPERTY  | /jobs/fetch             |
      | job "fetch" has an extra key "timeout"       | SCHEMA_INVALID_PROPERTY  | /jobs/fetch             |
      | job "fetch" has "body: 42"                   | SCHEMA_TYPE_ERROR        | /jobs/fetch/body        |

  @S06 @pending
  Scenario Outline: An edge to a missing step is refused
    # Value: no workflow is created with an edge that leads nowhere.
    # v1.ts:126-153; v2.ts:536-566; workflow-errors.ts:71-93, :221-225; v2.test.ts:464-512
    Given a <format> file whose edge from "ingest" targets "load-data", which the file does not define
    When I import it
    Then I see the code "JOB_NOT_FOUND" and a message naming "load-data"
    And nothing is written to the workflow

    Examples:
      | format |
      | v1     |
      | v2     |

  @S07 @pending
  Scenario: Two step names that would export to the same key are refused
    # Value: an imported workflow can always be exported again; otherwise it imports cleanly and fails on the way back out.
    # v1.ts:45-48, :247-264; workflow-errors.ts:95-106, :227-228; util.test.ts:517-525
    Given a v1 file with steps named "a b" and "a-b"
    When I import it
    Then I see the code "DUPLICATE_JOB_NAME"
    But a file with steps named "a b" and "a c" imports

  @S08 @pending
  Scenario: Only webhook and cron triggers are accepted
    # Value: an unrecognised trigger type never becomes a public webhook endpoint the file did not ask for.
    # workflow-spec.json:63-66; workflow-spec-v2.json:39-42; v1.ts:109-119 (backstop comment); workflow-errors.ts:132-136, :239-242
    Given a v1 file with a trigger of type "kafka"
    When I import it
    Then I see the code "SCHEMA_INVALID_VALUE" and "Must be one of: cron, webhook"

  @S09 @pending
  Scenario Outline: Triggers are only on when the file says so
    # Value: importing a workflow does not start accepting webhook requests or running on a schedule by accident.
    # workflow-spec.json:107 (v1 requires enabled); v2.ts:577-598; v2.test.ts:268-287; util.test.ts:44-152
    Given a <format> file whose webhook trigger <enabled>
    When I import it
    Then <outcome>

    Examples:
      | format | enabled                 | outcome                                                     |
      | v2     | has no "enabled" key    | the webhook trigger is imported disabled                    |
      | v2     | says "enabled: true"    | the webhook trigger is imported enabled                     |
      | v1     | has no "enabled" key    | I see "SCHEMA_MISSING_PROPERTY" naming "enabled"            |

  @S10 @pending
  Scenario: The workflow id in a file is ignored
    # Value: importing a file exported from another workflow never writes into that workflow.
    # YAMLStateToYDoc.ts:131-134 (only the name is copied to workflow metadata); v1.ts:166-167
    Given workflow "Lab results" exists with id "<lab id>"
    And a v1 file whose top-level "id" is "<lab id>"
    When I import it as a new workflow
    Then a separate workflow is created
    And "Lab results" is unchanged

  @S11 @pending
  Scenario: Re-applying a file that does not mention a webhook path keeps the live path
    # Value: an AI or YAML re-apply cannot silently break the URL a source system is posting to.
    # v1.ts:99-103; YAMLStateToYDoc.ts:80-86, :147-172; YAMLStateToYDoc.test.ts:619-700; util.test.ts:187-250
    Given workflow "Intake" has a webhook trigger with custom path "facility-001"
    When a v1 file for "Intake" that keeps the trigger's id but has no "custom_path" is applied
    Then the webhook trigger still has custom path "facility-001"
    But when the file says "custom_path: facility-002" the trigger has "facility-002"
```

Where the errors show is the host's business, and each host owns its own scenario:
workflow-editor-new shows the import dialog's error box (S04 to S09 above use it) and the template
preview's "This template can't be previewed." (`TemplateBrowserModal.tsx:245-259`, its S13);
workflow-editor-ai-assistant shows a "Failed to apply workflow" alert on an existing workflow or an
error message in the chat on a new one (`useAIWorkflowApplications.ts:321-341`;
`AIAssistantPanelWrapper.tsx:588-599`), and "Failed to restore workflow" on undo or redo
(`useAIWorkflowUndo.ts:94-100`).

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| v2 does not check duplicate step ids: a later step with the same `id` silently replaces the earlier one. The code view can emit such a file, because two job names that differ only in case or a space versus a hyphen get the same step id | `v2.ts:520-534`, `:251-258`, `:337-348` | a workflow exported from the code view and re-imported is missing a step, with no error | fix |
| Duplicate-name checks disagree: v1 compares names hyphenated but case-sensitive, v2 does not check names at all (it renames repeats to "x 2" on the way in), while the server v2 export downcases and refuses any collision | `v1.ts:48`, `:257-264`; `createWorkflowStore.ts:1840-1870`, `:1911`; `yaml_format/v2.ex:207`, `:399-400`, `:690-706` | steps "Fetch" and "fetch" import and save, then the project YAML export fails with a duplicate key error | fix |
| The v1 schema allows `webhook_reply` of `before_start`, `after_completion` or null, but the server also allows `custom`, and the v1 export and AI payload emit it | `workflow-spec.json:76-79`; `trigger.ex:31`; `export_utils.ex:194-198`; `v1.ts:396-400` | a v1 file (provisioning API YAML, an AI reply) for a workflow with a custom webhook reply is refused | decide |
| The enum error joins a `null` allowed value into the list | `workflow-errors.ts:132-136`, `:239-242`; `workflow-spec.json:78` | "Must be one of: before_start, after_completion, " with a trailing comma | fix |
| Values the server rejects pass the parser: v1 `condition_type` is any string, v2 `webhook_reply` is any string | `workflow-spec.json:151-153`; `workflow-spec-v2.json:46`; `edge.ex:52`; `trigger.ex:51` | "Create" is enabled, then the save fails with a generic error instead of a validation message | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Format detection: `steps` without `jobs` is v2; `jobs`, `edges` and a `triggers` map whose entries have `type` is v1; anything else, including both `jobs` and `steps`, falls back to v1 with a console warning | `v2.ts:71-108`; `util.test.ts:312-334` | preserve |
| Only one error is ever reported; the parser picks enum, then unknown property, then missing property, then type, then the first error, although the display can list several | `v1.ts:281-298`; `v2.ts:694-710`; `ValidationErrorDisplay.tsx:46-60` | decide |
| Formatted copy repeats itself: "Missing required field: Missing required property 'body' at /jobs/fetch", "Invalid property: Unknown property ..." | `workflow-errors.ts:122-131`, `:233-237` | decide |
| The same error reads differently by host: the import dialog shows the code and formatted copy, the template preview and AI paths show the raw message | `ValidationErrorDisplay.tsx:50-53`; `templateWorkflowState.ts:36-41`; `useAIWorkflowApplications.ts:331-341` | decide |
| v1 `pos` restores the layout; v2 carries none, so templates published from the canvas (v2) lose their layout even though positions are stored next to the code and sent to the browser | `v1.ts:66`, `:78-80`; `v2.ts:528`, `:585`; `TemplatePublishPanel.tsx:126-140`; `workflow_channel.ex:1495-1505` | decide |
| Credentials in a file (`credential` in v1, `configuration` in v2) are accepted and discarded; the code view's v2 export omits `configuration` while the server's v2 export includes it | `v1.ts:58-65`; `v2.ts:530-532`, `:337-355`; `yaml_format/v2.ex:301-317` | decide |
| v2 accepts and ignores `start`, `schema_version`, the workflow `id`, and Kafka trigger fields (`hosts`, `topics`, `sasl`, `username`, `password` and others) | `workflow-spec-v2.json:55-63`, `:89-93`; `v2.ts:568-598` | decide |
| v2 has no `custom_path`: the schema refuses it as an unknown property and neither serializer emits it; v1 accepts it | `workflow-spec-v2.json:34-67`; `workflow-spec.json:103-105`; `util.test.ts:187-190` | decide |
| A cron cursor naming a step the file does not define becomes no cursor, silently | `v1.ts:83-93`; `YAMLStateToYDoc.ts:195-201` | preserve |
| `convertWorkflowSpecToState` defaults a missing trigger `enabled` to true, but v1 requires the key and v2 always fills it with false, so the true default is unreachable from any parse path | `v1.ts:72-73`; `workflow-spec.json:107`; `v2.ts:578` | decide |
| Every built-in starting point sets its trigger `enabled: true` (blank workflow, both shipped templates), so a created webhook is live and the "Scheduled workflow" cron fires daily against example.com, while the workflow row is `:draft` | `baseTemplates.ts:21-23`, `:51-53`, `:76-80`; `workflow.ex:64` | decide |
| The template catalogue is instance-wide: every editor sees every published template and its job code, whichever project published it | `workflow_templates.ex:146-150`; `workflow_channel.ex:761-766` | decide |
| v2 condition bodies keep a trailing newline from a `|` block in the stored expression, though the comparison against named literals strips it | `v2.ts:645-657` | preserve |
| Each parse compiles the JSON schema afresh | `v1.ts:236-237`; `v2.ts:142-143` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| Phoenix hooks `YAMLToWorkflow`, `TemplateToWorkflow`, `WorkflowToYAML` | `yaml/YAMLToWorkflow.ts`; `yaml/TemplateToWorkflow.ts`; `yaml/WorkflowToYAML.ts`; registered `hooks/index.ts:8-10`, `:32-34` | no `phx-hook` names them in `lib/` (legacy editor removed) |
| `parseWorkflowTemplate` lenient v1 path | `util.ts:66-93` | only `TemplateToWorkflow` calls it; the template browser uses the strict parser (`templateWorkflowState.ts:16-18`) |
| `v1.parseWorkflowYAML`, `v1.parseWorkflowTemplate` | `v1.ts:208-226`, `:269-279` | no caller; `format.ts:30` calls `v1.parseWorkflow` |
| "Unsupported trigger type" throw | `v1.ts:109-120` | both schemas restrict `type` to webhook or cron first |
| `validateWorkflowIds` on AI apply and redo | `validateWorkflowIds.ts:9-57`; `useAIWorkflowApplications.ts:294`; `useAIWorkflowUndo.ts:83` | v1 schema already refuses a non-string id (`workflow-spec.json:21-23`, `:60-62`, `:139-141`); v2 output carries no ids |
| `createWorkflowError` regexes for `SourceJob:`, `TargetJob:`, `SourceTrigger:` messages | `workflow-errors.ts:170-184` | current throwers construct the typed errors directly with different wording |
| `INVALID_EDGE_KEY` error code | `workflow-errors.ts:19` | nothing throws it |

### 6.4 Performance and operational limits

none here; the 8MB upload cap and the 300ms validation debounce belong to the import dialog (workflow-editor-new).

### 6.5 Things seen but not understood

- v1 job, trigger and edge `id`s in a file are kept (`v1.ts:59`, `:71`, `:133`). AI replies carry them by design. What happens on save when a hand-written file reuses ids that belong to another workflow (`job.ex:93` `jobs_pkey`) was not traced.
- The AI payload serializer keys v1 triggers by type (`v1.ts:387`, `:422`), so two triggers of the same type would reach the assistant as one. Whether the editor can produce two of one type was not checked.
- Pasting a project-level YAML (the "Export project" download or `GET /api/provision/:id.yaml`) into workflow import should fail on the top-level `workflows` key; the exact error was not traced.
- The server's v2 moduledoc says a JS edge can carry an `expression:` key, but the emitter writes only `condition`, `label` and `disabled` (`yaml_format/v2.ex:87-88` vs `:565-591`), and the browser schema would refuse `expression` (`workflow-spec-v2.json:6-14`).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the parsers agree on duplicate handling (refuse, as v1 and the server export do, or rename, as v2 import does), and compare names the way the server export does (downcased)? (6.1 rows 1 and 2)
- Should the created workflow's triggers start enabled, given the row is `:draft`? Shared with workflow-editor-new 6.1 row 2.
- Should templates keep their published layout and stay instance-wide? (6.2)
- Should import bind credentials by the key the server export writes (`email|name`), or keep dropping them? (6.2)
- workflow-editor-new S17 and S18 restate S06 and S01 here; should they shrink to references?

## Proposed flows

- **flow-workflow-yaml-copy**: download a workflow's YAML from the code view (workflow-editor-inspectors), then import it on /w/new in another project or instance (workflow-editor-new). This file asserts only that the produced file parses back to the same workflow (S02). Surfaces: workflow-editor-inspectors, file download, workflow-editor-new.

## Proposed shared

none
