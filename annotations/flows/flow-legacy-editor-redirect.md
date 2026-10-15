---
id: flow-legacy-editor-redirect
type: flow
title: Legacy editor URLs redirect to the collaborative editor
status: not-started
owner:

trigger:
  entry: controller:legacy-redirect                # an old bookmark or a link in an email sent before the legacy editor was retired; nothing in lib/ or assets/js builds a /legacy URL any more
  exit: workflow-editor-canvas                     # /w/:id/legacy; workflow-editor-new for /w/new/legacy; workflow-editor-run-viewer when a= was on the link
  surfaces:
    - controller:legacy-redirect                   # legacy_redirect_controller.ex:17-44; router.ex:306-311
    - workflow-editor-new                          # /w/new/legacy lands here (legacy_redirect_controller.ex:17-19)
    - workflow-editor-canvas                       # /w/:id/legacy lands here (legacy_redirect_controller.ex:21-23)
    - workflow-editor-run-viewer                   # only when the link carried a= (legacy_redirect_controller.ex:39-43); owned by flow-open-run-in-editor S07
  reachable_when:
    - the visitor is signed in, or signs in first and is returned to the legacy URL (router.ex:189-190; user_auth.ex:288-300, :490-492, :64-69)

inherits:
  - shared-authenticated-session      # :browser and :require_authenticated_user on the controller hop (router.ex:189-190)
  - shared-project-scope              # applied on landing, not by the controller (collaborate.ex:25)

url_params:
  - name: project_id
    set_by: the old link
    effect: copied into the target path unchecked (legacy_redirect_controller.ex:18, :22)
  - name: id
    set_by: the old link (/w/:id/legacy only)
    effect: copied into the target path unchecked (legacy_redirect_controller.ex:22)
  - name: a
    set_by: old run bookmarks of the retired editor
    effect: renamed to run (legacy_redirect_controller.ex:39-43)
  - name: (any other query param, e.g. s, m, v)
    set_by: the old link
    effect: forwarded unchanged under the same name (legacy_redirect_controller.ex:9-13, :28-31)

config_variants:
  default: {}                         # read under this one; the controller reads no config

inventory:
  routes:
    - get /projects/:project_id/w/new/legacy  LegacyRedirectController :new   # router.ex:310
    - get /projects/:project_id/w/:id/legacy  LegacyRedirectController :edit  # router.ex:311
  events: []
  js_hooks: []
  policies: []                        # the controller checks nothing; the landing LiveView's on_mount hooks do
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here: []

related:
  - lib/lightning_web/controllers/legacy_redirect_controller.ex
  - lib/lightning_web/router.ex
  - lib/lightning_web/controllers/user_auth.ex
  - lib/lightning_web/live/workflow_live/collaborate.ex
  - lib/lightning_web/hooks.ex
  - test/lightning_web/controllers/legacy_redirect_controller_test.exs
  - annotations/views/workflow-editor-new.md
  - annotations/views/workflow-editor-canvas.md
flows:
  - flow-open-run-in-editor           # owns the a -> run scenario (its S07)
  - flow-login-return-to              # owns the generic return-to behaviour used by S03
---

## 1. Purpose

People who bookmarked a workflow in the retired legacy editor, or who still have emails and
messages linking to it, need those links to keep opening the same workflow. Without the redirect
every such link would 404 and they would have to find the workflow again by name.

## 2. What it does

1. Someone opens an old link to the retired legacy editor, either to a workflow or to "new workflow".
   - If they're signed out, they log in first and then carry on with the same link.
2. They're sent straight to the same workflow, or the new workflow screen, in the current editor.
   - The rest of the link comes along with it, and an old link to a run opens that run.
3. Whether they can actually see the page is decided there as usual: non-members are turned away, and only people who can create workflows get the new workflow screen.

**Straightforwardness: 4 of 5.** It's a redirect that does what you'd expect; the surprises are odd links breaking it, not the normal case.

### Most surprising behaviours

- **(3)** An old link with certain bracketed bits in its address shows an error page instead of opening the workflow. (6.1)
- **(3)** A specially crafted link that looks like a workflow link may send someone to another page on the site instead, such as logging them out. (6.1)
- **(4)** Old links that pointed at a selected step or a particular mode open the workflow but lose that selection, since the new editor ignores the old settings. (6.2)

## 3. Who can do what

The controller applies no policy (`legacy_redirect_controller.ex:17-44`). Signed-in status comes
from the scope's pipeline (`router.ex:189-190`). Access to the target is decided on landing by
`shared-project-scope` and the editor's own mount checks.

| Action | Signed out | Viewer | Editor | Admin | Owner | Non-member |
|--------|------------|--------|--------|-------|-------|------------|
| Follow a legacy link and be redirected | after login | yes | yes | yes | yes | yes |
| Land on an existing workflow in the editor | after login | yes | yes | yes | yes | no (shared-project-scope) |
| Land on the new workflow screen | after login | no, bounced to the workflow list | yes | yes | yes | no (shared-project-scope) |

**Preconditions beyond role**
- The redirect itself is issued to anyone signed in, for any `project_id` and `id`; it reveals nothing because it only rewrites the path (`legacy_redirect_controller.ex:17-23`).
- `/w/new` refuses users without `:create_workflow` with "You are not authorized to perform this action." (`collaborate.ex:35-59`); owned by workflow-editor-new.
- `/w/:id` refuses a workflow that is deleted or not in the project with "Workflow not found" (`collaborate.ex:26`; `hooks.ex:138-158`); owned by workflow-editor-canvas.

## 4. What it touches

**Reads**
- Hop 1, login gate (signed out only): session `user_return_to` written with the full legacy path and query (`user_auth.ex:296-298`, `:490-492`)
- Hop 2, redirect: the request path and query string only, no database (`legacy_redirect_controller.ex:25-37`)
- Hop 3, landing: whatever the target LiveView mounts (`collaborate.ex:25-59`); owned by workflow-editor-new and workflow-editor-canvas

**Writes**: none

**Immediate side effects**
- Hop 2: a 302 to the collaborative path (`legacy_redirect_controller.ex:34-36`)

**Deferred side effects**
- none

**External, non-transactional effects**
- none

**Depends on config**
- none

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Legacy editor URLs redirect to the collaborative editor
  In order to keep old workflow links working after the legacy editor was retired
  As anyone with an old link
  I want it to open the same workflow in the collaborative editor

  @S01 @pending
  Scenario: An old workflow link opens that workflow in the collaborative editor
    # Value: bookmarks and emailed links to a workflow keep working after the editor was replaced.
    Given I am an editor on project "Malawi HIV" with workflow "Intake"
    When I open "/projects/<project_id>/w/<Intake id>/legacy"
    Then I am redirected to "/projects/<project_id>/w/<Intake id>"
    And the workflow editor shows "Intake"
    # legacy_redirect_controller.ex:21-23, :25-37; router.ex:303, :311
    # legacy_redirect_controller_test.exs:35-45 (redirect target only)

  @S02 @pending
  Scenario: An old new-workflow link opens the new workflow screen
    # Value: a saved "create workflow" link still starts a new workflow.
    Given I am an editor on project "Malawi HIV"
    When I open "/projects/<project_id>/w/new/legacy"
    Then I am redirected to "/projects/<project_id>/w/new"
    And the flow ends on workflow-editor-new
    # legacy_redirect_controller.ex:17-19; router.ex:302, :310
    # legacy_redirect_controller_test.exs:10-17

  @S03 @pending
  Scenario: A signed-out visitor lands on the workflow after logging in, query intact
    # Value: an old link opened from an email reaches the workflow even when the reader was not logged in.
    Given I am signed out and an editor on project "Malawi HIV"
    When I open "/projects/<project_id>/w/<Intake id>/legacy?a=<R id>"
    And I log in
    Then I am on "/projects/<project_id>/w/<Intake id>" with "run=<R id>"
    # router.ex:189-190; user_auth.ex:288-300, :490-492, :64-69; legacy_redirect_controller.ex:39-43
    # no test covers the login hop for this route
```

The `a` to `run` rename with other params forwarded is flow-open-run-in-editor S07
(`legacy_redirect_controller_test.exs:47-83`); not repeated here.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Nested query params (`x[y]=1`) decode to a map, and `URI.encode_query/1` cannot stringify a map | `legacy_redirect_controller.ex:26`, `:31` | a 500 instead of a redirect for any old link with a bracketed param; list params (`x[]=1&x[]=2`) are stringified together instead | fix |
| `project_id` and `id` are interpolated into the target path without re-encoding; a `%2F` in a segment decodes to `/`, so a crafted link can redirect to another local path (for example `/users/log_out`) | `legacy_redirect_controller.ex:18`, `:22` | a link that looks like a workflow link logs the user out or opens another page; it stays on the same host (Phoenix's local-redirect check was not read, deps not present) | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| If both `a` and `run` are present, `a` overwrites `run`; repeated params collapse to the last value | `legacy_redirect_controller.ex:39-43` | decide |
| Query param order is not preserved (re-encoded from a map) | `legacy_redirect_controller.ex:31` | preserve |
| Legacy `s` and `m` are forwarded under their old names although the collaborative editor names selection and mode differently; they are ignored on landing | `legacy_redirect_controller.ex:9-13`; `router.ex:306-309` | decide |
| On `/w/new` every forwarded param is ignored | workflow-editor-new url_params (`collaborate.ex:100-104`) | preserve |
| The redirect is a plain controller GET inside the `:default` live_session block, so it is a full page load, not a live navigation | `router.ex:288`, `:310-311` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| none | | |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| none | | | |

### 6.5 Things seen but not understood

- Which legacy params other than `a` the retired editor used (and whether `v` meant the same version pin it does now) could not be checked: the legacy module is gone and git history here is shallow.
- How long the redirect should be kept: nothing in the code or comments sets a sunset date.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the rebuild keep the `/legacy` redirects at all, and for how long (6.5)?
- Should `s` and `m` be translated to the collaborative editor's params, or dropped (6.2)?
- Should the controller validate `project_id` and `id` as UUIDs before redirecting (6.1)?

## Proposed flows

none

## Proposed shared

none
