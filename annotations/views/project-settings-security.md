---
id: project-settings-security
type: view
title: Project settings › Security
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/settings#security
  new_route: /projects/:project_id/settings/security
  old_route_disposition: redirect
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope; settings.ex:51)
    - the client-side tab hash is "security" (settings.html.heex:51-54, :681; TabbedContainer, see shared-project-settings-tab-chrome)
    - the switch is interactive only when the project is not a sandbox and the usage limiter allows `:require_mfa` (settings.html.heex:731-732; hooks.ex:214-227)

inherits:
  - shared-authenticated-session
  - shared-project-scope                  # on_mount :project_scope (settings.ex:51); login, MFA gate (S05), membership remount (S08)
  - shared-usage-limits-banner            # on_mount :check_limits (settings.ex:52)
  - shared-project-header
  - shared-project-settings-tab-chrome    # tab navigation, role notice (S06 row "editor | Security"), sandbox inherited banner (S09)
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: "#security (URL fragment)"
    set_by: the tab strip only; no other page or email links here (grep of "#security" in lib/ finds none)
    effect: opens this tab client-side; the server never sees it (settings.ex:233)

config_variants:
  default: { Lightning.Extensions.usage_limiter: Lightning.Extensions.UsageLimiter }   # limit_action always :ok (usage_limiter.ex:11); read under this one
  mfa-limited: { Lightning.Extensions.usage_limiter: <adapter whose limit_action(%Action{type: :require_mfa}) returns {:error, _, %Message{function: f}}> }   # hosted plans; read from code and project_live_test.exs:2280-2316
  sandbox: { project.parent_id: <parent project id> }   # data state, named so the sandbox scenario can be tagged

inventory:
  routes:
    - live /projects/:project_id/settings  ProjectLive.Settings :index   # config-injected (config/config.exs:52-57); catalogued by project-settings-setup
  events:
    - ProjectLive.Settings#toggle-mfa                                   # settings.ex:411-431
  js_hooks:
    - Tooltip (on the switch when the viewer can't edit the project; settings.html.heex:736)
  policies:
    - Lightning.Policies.ProjectUsers (:edit_project; project_users.ex:29-37, :134, :160-161; flag computed settings.ex:122-123; re-checked settings.ex:414, :744-749)
  workers: []
  api_endpoints: []
  emails: []
  config:
    - :lightning, Lightning.Extensions, :usage_limiter (config/config.exs:43), read through on_mount {LightningWeb.Hooks, :limit_mfa} (settings.ex:54; hooks.ex:214-227)
  not_reachable_here: []

related:
  - project-settings-setup                # owns the host route and mount; owns the crafted-save scenario that keeps requires_mfa out of the generic save
  - mfa-required                          # where unenrolled members land once the requirement is on (INVENTORY.md:31)
  - profile-mfa                           # where a member enrols (INVENTORY.md:86)
  - flow-digest-email                     # recipients must satisfy the project's MFA requirement (S04 there)
  - flow-failure-alert-email              # same rule for failure alerts
  - lib/lightning/projects/scope.ex       # the one place requires_mfa is read for authorisation (scope.ex:225-229)
  - lib/lightning/projects/sandboxes.ex   # requires_mfa copied at sandbox creation (sandboxes.ex:104-107)
flows:
  - flow-require-project-mfa
---

## 1. Purpose

Project owners and admins use this tab to decide whether a project can only be reached from
accounts protected by multi-factor authentication. Projects hold health and survey data, so an
admin needs a way to say "nobody gets in with just a password" without asking a superuser, and
every member needs to be able to see which rule applies. Without it a single stolen password is
enough to read or change the project, and on hosted plans that don't include the feature, admins
would get no explanation of why they can't turn it on.

## 2. What it does

- Every member sees whether the project currently requires MFA
- Admins and owners turn the MFA requirement on
- Admins and owners turn the MFA requirement off
- Editors, viewers and support users cannot change the requirement, and are told so
- A member whose admin role was removed while the page was open cannot change the requirement
- On a plan without the MFA feature, admins see the limiter's message and the switch is disabled
- In a sandbox, the switch is disabled
- Turning the requirement on keeps unenrolled members out of the project from then on

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:29-37` (`:edit_project` is an admin action),
`:134` (MFA unsatisfied denies everything), `:160-161` (admin actions need an owner or admin row;
support standing never fills them). Flag computed once at mount, `settings.ex:122-123`; the
handler re-checks the policy against a freshly loaded scope, `settings.ex:414`, `:744-749`,
`scope.ex:111-117`, `:165`. The usage limit is a separate gate, `settings.ex:414`, `hooks.ex:214-227`.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|--------|--------|--------|-------|-------|--------------------|-----------------------------|
| See the tab and the current requirement | yes | yes | yes | yes | no (cannot open the project) | yes |
| Turn the MFA requirement on or off | no | no | yes | yes | no | no |
| Turn it on or off in a sandbox | no | no | no | no | no | no |
| Turn it on or off when the plan limits MFA (`mfa-limited`) | no | no | no | no | no | no |

**Preconditions beyond role**
- The usage limiter must allow `%Action{type: :require_mfa}` for the project; this is decided once at mount (`hooks.ex:214-227`; `settings.ex:54`, `:414`).
- In a sandbox the switch is disabled and sends no event (`settings.html.heex:731-732`); the server handler itself does not check for a sandbox (see 6.1).
- A member who hasn't met the project's MFA requirement never reaches this page (shared-project-scope S05), and every policy check fails for them (`project_users.ex:134`).
- `requires_mfa` can't be set through the generic settings save (`settings.ex:341-345`, `:355-358`); that scenario lives in project-settings-setup.
- No check that the admin is enrolled in MFA before they turn the requirement on (`settings.ex:411-427`; see 6.1).

## 4. What it touches

**Reads**: `projects` (the project, preloaded with its parent, `settings.ex:108-110`; reloaded for every policy check, `scope.ex:165`, `:173-180`); `project_users` for the viewer's role (`scope.ex:183-188`); `users.mfa_enabled` and `support_user` via the scope (`scope.ex:189-197`, `:225-229`)

**Writes**: `projects.requires_mfa` (`settings.ex:417-422`; `projects.ex:589-598`; cast in `project.ex:72-86`)

**Immediate side effects** (in the same request)
- Audit `project` event `requires_mfa_updated` with before and after values and the acting user (`projects.ex:597`, `:620-625`; `audit.ex:15`, `:20-38`; `projects_test.exs:3560-3579`)
- Flash "Project MFA requirement updated successfully" (`settings.ex:427`)

**Deferred side effects** (later, elsewhere)
- From the next request on, every project-scoped policy check for an unenrolled member fails: LiveView pages redirect to `/mfa_required` (`hooks.ex:98-101`), plain routes and the API refuse (`project_mfa_enforcement_test.exs:1-35`), websocket channels refuse (`workflow_channel_test.exs:1776-1822`, `run_channel_test.exs:3105-3125`), and digest and failure-alert emails stop going to them (`mail_recipients_test.exs:58-77`). See proposed flow `flow-require-project-mfa`.
- No PubSub broadcast: members already on an open project page are not moved off it (`projects.ex:600-607`, `:776-780` broadcast only on `allow_support_access`).

**External, non-transactional effects**
- none

**Depends on config**
- `Lightning.Extensions.usage_limiter` decides whether the switch is enabled and whether the banner shows (`config/config.exs:43`; `hooks.ex:214-227`; variant `mfa-limited`)

**Product limits**
- On hosted plans without the feature, the requirement can't be turned on or off (variant `mfa-limited`, S06)

## 5. Scenarios

```gherkin
Feature: Project MFA requirement
  In order to keep project data reachable only from MFA-protected accounts
  As a project admin
  I want to require multi-factor authentication for everyone on the project

  @S01 @pending
  Scenario: Admin turns on the MFA requirement
    # Value: an admin can lock a sensitive project to MFA-protected accounts the same day, without a superuser.
    Given project "Malawi HIV" does not require MFA
    And I am an admin on project "Malawi HIV" who has enrolled in MFA
    When I open the "Security" tab
    Then I see "(currently optional for this project)"
    When I click the "Require MFA?" switch
    Then I see "Project MFA requirement updated successfully"
    And I see "(currently required for this project)"
    And project "Malawi HIV" requires MFA
    And an audit event "requires_mfa_updated" is recorded with me as the actor, before false and after true
    # settings.html.heex:726-753; settings.ex:411-427; projects.ex:589-598; audit.ex:20-38
    # project_live_test.exs:2109-2127 (flash only), :2259-2278; projects_test.exs:3560-3579

  @S02 @pending
  Scenario: Admin turns off the MFA requirement
    # Value: the people who set the requirement can lift it, and who loosened it is on record.
    Given project "Malawi HIV" requires MFA
    And I am an owner on project "Malawi HIV" who has enrolled in MFA
    When I click the "Require MFA?" switch on the "Security" tab
    Then I see "Project MFA requirement updated successfully"
    And I see "(currently optional for this project)"
    And project "Malawi HIV" does not require MFA
    And an audit event "requires_mfa_updated" is recorded with me as the actor, before true and after false
    # settings.ex:411-427; settings.html.heex:747-751; audit.ex:20-38 (audit both directions; only the on direction is tested)

  @S03 @pending
  Scenario Outline: Every member can see whether MFA is required
    # Value: members can tell which rule governs the project, and why a colleague without MFA is turned away.
    Given project "Malawi HIV" does not require MFA
    And I am a <role> on project "Malawi HIV"
    When I open the "Security" tab
    Then I see "Multi-Factor Authentication"
    And I see "(currently optional for this project)"
    # settings.html.heex:705-753; project_live_test.exs:2089-2107 (asserts the heading for all four roles)

    Examples:
      | role   |
      | viewer |
      | editor |
      | admin  |
      | owner  |

  @S04 @pending
  Scenario Outline: Members who aren't admins can't change the requirement
    # Value: only people trusted with access decisions can tighten or loosen how the project is protected.
    Given project "Malawi HIV" does not require MFA
    And I am a <role> on project "Malawi HIV"
    When I open the "Security" tab
    Then the "Require MFA?" switch shows the tooltip "You do not have permission to perform this action"
    When I click the "Require MFA?" switch
    Then I see "You are not authorized to perform this action."
    And project "Malawi HIV" still does not require MFA
    # settings.html.heex:729, :736; settings.ex:414, :428-430, :751-765; project_users.ex:160-161
    # project_live_test.exs:2129-2155 (editor, viewer; flash asserted, DB not); support row from project_users.ex:160-161, untested

    Examples:
      | role                                  |
      | editor                                |
      | viewer                                |
      | support user with no row, access on   |

  @S05 @pending
  Scenario: An admin demoted while the page is open can't change the requirement
    # Value: a revoked admin can't change the project's protection from a page they opened before losing the role.
    Given I am an admin on project "Malawi HIV" with the "Security" tab open
    And my role is changed to viewer without the page being told
    When I click the "Require MFA?" switch
    Then I see "You are not authorized to perform this action"
    And project "Malawi HIV" still does not require MFA
    # settings.ex:414, :744-749; scope.ex:111-117, :183-188; membership_revocation_test.exs:261-273, :294-298

  @S06 @pending @variant:mfa-limited
  Scenario: The plan doesn't include requiring MFA
    # Value: hosted plan limits hold, and the admin is told why they can't turn the requirement on.
    Given the usage limiter refuses ":require_mfa" for project "Malawi HIV" with the message "MFA Feature is disabled"
    And I am an admin on project "Malawi HIV"
    When I open the "Security" tab
    Then I see "MFA Feature is disabled"
    And the "Require MFA?" switch is disabled
    When "toggle-mfa" is sent directly
    Then I see "You are not authorized to perform this action"
    And project "Malawi HIV" still does not require MFA
    # hooks.ex:214-227; settings.ex:54, :414, :429; settings.html.heex:696-704, :731
    # project_live_test.exs:2280-2316; not-limited counterpart :2259-2278

  @S07 @pending @variant:sandbox
  Scenario: The requirement can't be changed from a sandbox
    # Value: a sandbox can't be used to change how strongly its data is protected; the inherited banner (shared-project-settings-tab-chrome S09) points to the parent.
    Given sandbox "dev" of project "Malawi HIV"
    And I am an owner of sandbox "dev"
    When I open the settings of sandbox "dev" on the "Security" tab
    Then the "Require MFA?" switch is disabled
    And clicking it sends nothing
    # settings.html.heex:729-732; sandbox_settings_test.exs:265-272 (asserts id, "disabled" and "cursor-not-allowed" in the page HTML)

  @S08 @pending
  Scenario: Turning on the requirement hands off to MFA enforcement
    # Value: the switch here is the rule every project page, API call and email recipient check then obeys.
    Given I am an admin on project "Malawi HIV"
    And "bob@example.org" is an editor on the project who has not enrolled in MFA
    When I turn on the MFA requirement
    Then the flow "flow-require-project-mfa" has started for "bob@example.org"
    # handoff only; scope.ex:225-229; project_users.ex:134; hooks.ex:98-101
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| An admin who hasn't enrolled in MFA can turn the requirement on, which immediately fails every policy check for them, including turning it back off | `settings.ex:411-427`; `scope.ex:225-229`; `project_users.ex:134`; tests do this with an unenrolled admin, `project_live_test.exs:2109-2127` | success flash, then "You are not authorized to perform this action" on any further change, and `/mfa_required` on the next page load, with no warning beforehand | decide |
| The switch's `disabled` ignores role: editors, viewers and support users get a greyed-out switch that is still clickable and sends `toggle-mfa` | `settings.html.heex:729`, `:731` (disabled only on `can_require_mfa` or sandbox) vs `:736` | a control styled as disabled that produces a red "not authorized" flash when clicked | fix |
| The opposite mismatch on `mfa-limited`: an admin's switch is disabled but styled as enabled (no `opacity-50`, `cursor-pointer`), because the style follows `can_edit_project` not `can_require_mfa` | `settings.html.heex:729`, `:731` | a normal-looking switch that does nothing | fix |
| `toggle-mfa` doesn't refuse sandboxes on the server; only the template withholds `phx-click`. A sandbox admin sending the event directly changes the sandbox's own `requires_mfa`, which the sandbox's scope then enforces | `settings.ex:411-427`; `settings.html.heex:732`; `scope.ex:225-229` | nothing in the UI; a crafted event bypasses the "cannot be changed here" banner | fix |
| `{:ok, project} = Projects.update_project(...)` crashes the LiveView on any changeset error, for example a project whose stored fields fail `Project.validate` or a `ProjectHook.handle_project_validation` adapter that rejects | `settings.ex:417-422`; `projects.ex:589-593`, `:609-610` | the page crashes and reconnects with no message | fix |
| The `:limit_mfa` hook matches only `:ok` and an error whose message has a `function`; an adapter returning `{:error, reason, %Message{text: ...}}` without one raises a case clause error at mount | `hooks.ex:214-227`; `message.ex:6-13` | every project settings tab fails to load, not just Security | fix |
| The inherited banner says sandbox security settings come from the parent, but `requires_mfa` is copied once at creation and not propagated | shared-project-settings-tab-chrome 6.1 row "The inherited banner on Security..."; `sandboxes.ex:104-107`; `sandboxes_test.exs:1422-1429` | see the shared row | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The toggle flips the value held in the socket, not the stored one; if another tab changed it, the click writes the value already stored, records no audit (no change), but still flashes "updated successfully" | `settings.ex:416-427`; `audit.ex:28-31` | decide |
| Changing the requirement doesn't broadcast; another admin's open Security tab keeps showing the old state until reload | `projects.ex:600-607`, `:776-780` | decide |
| The success flash is the same in both directions and doesn't say whether MFA is now required | `settings.ex:427` | decide |
| `aria-describedby="require-mfa-description"` points to an id that doesn't exist (the description is `id="mfa-description"`); `id="mfa-label"` is referenced by nothing | `settings.html.heex:710`, `:714`, `:735` | fix |
| Description copy is ungrammatical: "before they are allowed access this project" | `settings.html.heex:715-718` | fix |
| UI labels are title case ("Multi-Factor Authentication") next to a sentence-case section heading ("Project security") and a question-style switch label ("Require MFA?") | `settings.html.heex:683`, `:712`, `:745` | decide |
| The tooltip appears only for members who can't edit the project; an admin on a limited plan or in a sandbox gets no tooltip, only the limiter banner or the sandbox banner | `settings.html.heex:736` | preserve |
| The limiter banner is rendered by calling `Phoenix.LiveView.TagEngine.component/3` directly with the adapter's function and attrs, inside an always-present empty `<div>` | `settings.html.heex:696-704` | decide |
| `can_require_mfa` and `mfa_banner` are computed by an on_mount hook for every settings tab, not just this one, and never refreshed | `settings.ex:54`; `hooks.ex:214-227` | preserve |
| The role notice in a sandbox is suppressed (nil message) | shared-project-settings-tab-chrome 6.2 row "In a sandbox, Security passes a nil message..."; `settings.html.heex:685-687` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| Empty `<h6>` and `<p>` above the switch | `settings.html.heex:723-724` | no content; render nothing visible |
| `mfa_banner` branch under the default limiter | `settings.html.heex:697-703`; `usage_limiter.ex:11` | the default adapter always returns `:ok`, so `mfa_banner` is never assigned outside `mfa-limited` |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Each policy check reloads the project and membership row (two queries per `authorize`) | `scope.ex:165`, `:173-188`; `settings.ex:414` | no | preserve |

### 6.5 Things seen but not understood

- `sandbox_settings_test.exs:265-272` asserts `html =~ "disabled"` and `"cursor-not-allowed"` on the whole page, not on the switch, so it would pass if any other element on any tab carried those strings; it is weak coverage for S07.
- `project_live_test.exs:2129-2155` calls `render_click` on a switch that is not disabled for those roles; whether a real browser click behaves the same depends on 6.1 row 2, which a fix would change (the click would then send nothing).
- The limiter test returns reason `:disabled` (`project_live_test.exs:2301-2303`), which is not in `UsageLimiting.error_reason` (`usage_limiting.ex:5-9`); unclear what reason a real hosted adapter returns for `:require_mfa`.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should an admin who hasn't enrolled be blocked from turning on the requirement, or warned that they will lose access (6.1)? (owner: product)
- Should turning on the requirement move unenrolled members off pages they already have open, as removing a member does (shared-project-scope S07), rather than waiting for their next request?
- Should a sandbox follow its parent's MFA requirement live, or keep its own copy and say so (6.1, shared chrome row)?
- Which reason and message does the hosted usage limiter actually return for `:require_mfa` (6.5)? The commercial adapter is not in this repository.

## Proposed flows

- `flow-require-project-mfa`: an admin turns on the requirement here; an unenrolled member's next project page load redirects to `/mfa_required`, plain routes and the bearer-token API refuse them, websocket joins refuse, and digest and failure-alert emails stop reaching them until they enrol on their profile. Surfaces: project-settings-security, shared-project-scope (`hooks.ex:98-101`), mfa-required (`live/project_live/mfa_required.ex`), profile-mfa, controller and API routes (`project_mfa_enforcement_test.exs`), channel:workflow and channel:run, flow-digest-email and flow-failure-alert-email recipient checks (`mail_recipients.ex:28-32`).

## Proposed shared

none

## Lead resolution (batch 2)

- `flow-require-project-mfa` created as proposed.
