# Behaviour annotation template (v2)

One file per **view**, **capability** or **flow**.

- A **view** is something a user navigates to: a route, or a panel inside a settings page.
- A **capability** is behaviour with no screen: a cron job, an inbound webhook, an email, an API endpoint, a domain event.
- A **flow** is behaviour that crosses more than one surface: a second browser tab, an email link, a controller redirect, a PubSub broadcast back into a page. A flow owns the end-to-end scenario. The views it passes through only assert that the flow starts or ends there.

Suggested location: `annotations/views/<id>.md`, `annotations/capabilities/<id>.md`, `annotations/flows/<id>.md`,
and `annotations/shared/<id>.md` for behaviour every view inherits (auth scoping, MFA gating, limits banner).

**The organising principle: value first.** Sections 2 to 5 should read as a description of what the
product does for someone and why. Every scenario names the value it protects. Anything observed in the
code that can't be explained that way goes in section 6, "Unclear value", and gets a disposition there.
That section is where the laundry list lives, so the top of the file stays readable.

---

```yaml
---
id: project-settings-collaborators
type: view                                  # view | capability | flow | shared
title: Project settings › Collaborators
status: not-started                         # not-started | in-progress | migrated | cut
owner:

trigger:
  # view
  old_route: /projects/:project_id/settings#collaborators
  new_route: /projects/:project_id/settings/collaborators
  old_route_disposition: redirect           # redirect | gone (deliberate 404) | unchanged
  reachable_when:                           # conditions the host page applies before this renders
    - project has not been deleted
  # capability
  # kind: cron | webhook | event | api | email
  # source: lib/lightning/digest_email_worker.ex
  # flow
  # entry: project-settings-collaborators
  # exit: user-invite-accept
  # surfaces: [project-settings-collaborators, email:project-addition, user-invite-accept]

inherits:                                   # shared annotations whose behaviour applies here
  - shared-project-scope                    # login redirect, MFA gate, non-member redirect, membership remount
  - shared-usage-limits-banner

url_params:                                 # inbound URL contract, including params only other pages set
  - name: filters[workorder_id]
    set_by: workflow-health
    effect: expands that work order on load

config_variants:                            # named environments scenarios can be tagged with
  default: {}
  mfa-required: { project.requires_mfa: true }

inventory:                                  # items from the generated old-app inventory this annotation covers
  routes:
    - live /projects/:id/settings  ProjectLive.Settings
  events:
    - ProjectLive.Settings#add_collaborators
    - ProjectLive.Settings#remove_collaborator
    - ProjectLive.Settings#update_role
  js_hooks: []                              # browser-side hooks, inline handlers
  policies:
    - Lightning.Policies.ProjectUsers
  workers: []
  api_endpoints: []
  emails:
    - email:project-addition               # reference the email's own capability annotation
  config: []
  not_reachable_here: []                    # items in a shared module this view cannot reach (see section 6)

related: []
flows:
  - flow-invite-collaborator
---
```

## 1. Purpose

Two or three sentences. Who uses this, what job they are doing, and what would go wrong for them
if it didn't exist. This is the frame every scenario below hangs off.

> Project admins manage who can see and change a project. Getting this wrong either locks out a
> collaborator who needs to ship a fix, or exposes health data to someone who shouldn't see it.

## 2. What it does

A taut list of capabilities: who can do what. One line each, no justification. The value
lives in section 1 and on each scenario, not here. This is the index into section 5. If a line
has no scenario, it is either folded into another or it isn't verified.

- Admins add collaborators by email
- Admins change a collaborator's role
- Admins remove a collaborator
- Anyone on the project sees who else is on it

## 3. Who can do what

A role-by-action matrix pulled from the policy module named in the frontmatter, not from memory.
Include a visibility row. Then a **preconditions** list for gates that aren't roles: self-only,
sudo or re-auth windows, MFA state, support access, ownership of the resource, external identity.

| Action              | Viewer | Editor | Admin | Owner | Superuser | Support |
|---------------------|--------|--------|-------|-------|-----------|---------|
| See the panel       | yes    | yes    | yes   | yes   | yes       | yes     |
| Add collaborator    | no     | no     | yes   | yes   | yes       | no      |
| Change role         | no     | no     | yes   | yes   | yes       | no      |
| Remove collaborator | no     | no     | yes   | yes   | yes       | no      |
| Remove self         | yes    | yes    | yes   | no    | n/a       | n/a     |

**Preconditions beyond role**
- The last owner cannot be removed or demoted (protects against orphaned projects).
- All actions denied when the project requires MFA and the user hasn't enrolled.
- Support access is read-only here.

## 4. What it touches

**Reads**: `projects`, `project_users`, `users`

**Writes**: `project_users` (insert, update role, delete)

**Immediate side effects** (in the same request)
- Audit: `project_user.added`, `project_user.role_changed`, `project_user.removed`
- Email `email:project-addition` to each new collaborator

**Deferred side effects** (later, elsewhere)
- none

**External, non-transactional effects** (calls out that can't be rolled back if the request fails)
- none

**Depends on config**
- none

**Product limits** (limits a user would notice and that we intend to keep)
- none

## 5. Scenarios

Gherkin. Happy paths first. Every scenario carries:

- an id tag `@Sxx`
- a status tag: `@pending`, `@passing-old`, `@passing-new`, `@cut`
- a config variant tag when it only applies to one: `@variant:mfa-required`
- a **Value** line stating what the scenario protects, in plain language.
  If you can't write that line, the scenario belongs in section 6.

Async behaviour is fine to express with "eventually" or "while … is loading"; the test will wait.
If a scenario needs another browser tab, an email link or a different page to complete, it belongs
to a **flow** annotation, and this file only asserts the handoff.

```gherkin
Feature: Project collaborators
  In order to control who can see and change a project
  As a project admin
  I want to add, change and remove collaborators

  @S01 @passing-old
  Scenario: Admin adds a collaborator
    # Value: new team members get access the same day, without a superuser.
    Given I am an admin on project "Malawi HIV"
    And "amara@example.org" is a registered user not on the project
    When I add "amara@example.org" as an editor
    Then "amara@example.org" appears in the list with role "Editor"
    And the flow "flow-invite-collaborator" has started for "amara@example.org"
    And an audit event "project_user.added" is recorded

  @S02 @passing-old
  Scenario: Editor cannot see the add collaborator control
    # Value: only people trusted with access decisions can make them.
    Given I am an editor on project "Malawi HIV"
    When I open the collaborators panel
    Then I do not see the "Add collaborator" button

  @S03 @passing-old
  Scenario: The last owner cannot be removed
    # Value: a project never ends up with nobody able to administer it.
    Given I am the only owner on project "Malawi HIV"
    When I try to remove myself
    Then I see "A project must have at least one owner"
    And I remain an owner

  @S04 @pending @variant:mfa-required
  Scenario: Admin without MFA cannot change roles on an MFA-required project
    # Value: sensitive projects are only administered from MFA-protected accounts.
    Given project "Malawi HIV" requires MFA
    And I am an admin who has not enrolled in MFA
    When I open the collaborators panel
    Then every action is disabled with a tooltip explaining MFA is required
```

## 6. Unclear value

Everything observed in the code that you could not explain as value delivered to someone.
This is deliberately the laundry list, so the sections above stay about the product.
Each item gets a **disposition** so the verification loop knows what to do with it:

- `preserve`: we think it matters even though we can't say why yet; write a scenario once we can
- `fix`: behave differently in the rebuild; link an issue
- `drop`: not carrying it over; move to section 7 with a reason
- `decide`: needs a human; blocks `migrated`

### 6.1 Possible bugs

Behaviour that looks unintended. Cite the code. Say what a user would see. Default disposition is
`fix` unless someone argues for `preserve`.

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Role dropdown offers "Owner" to admins, but the policy rejects it on save | `settings.ex:412` | a confusing "not authorized" flash after picking a visible option | fix |

### 6.2 Quirks and implementation details

Behaviour that is real and reachable but reads as a side effect of how it was built: which
live_session a route sits in, a full page load where a patch would do, nulls sorting first,
exclusive vs inclusive date bounds, error copy that doesn't match the control.

| What | Where | Disposition |
|------|-------|-------------|
| Collaborator list is sorted by insertion, not name | `settings.ex:88` | decide |

### 6.3 Unreachable or dead code

Handlers with no caller, branches hidden by config, UI only visible in the test build, modules a
shared component carries that this view can't reach. These are expected to be uncovered by the
inventory lint; list them so it doesn't nag.

| What | Where | Why unreachable |
|------|-------|-----------------|
| `handle_event("resend_invite")` | `settings.ex:301` | no button renders it since 2.14 |

### 6.4 Performance and operational limits

Query caps, timeouts, chunk sizes, debounce, pagination size. Real behaviour, rarely
Gherkin-verifiable. Note which ones a user would notice; those may deserve a scenario in section 5
under "Product limits".

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Collaborator search capped at 50 results | `projects.ex:702` | yes, "50+" label | preserve |

### 6.5 Things seen but not understood

Anything the cataloguer couldn't classify. Better here than silently dropped.

## 7. Not migrating

Deliberate cuts, with the reason and who decided. A `@cut` scenario or a `drop` disposition
counts as resolved only when it has a row here.

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

Things that must be answered before this can be marked `migrated`.

---

## Flow annotation: what differs

A flow uses the same file with these changes:

- `type: flow`, and `surfaces:` lists every annotation it passes through, in order, including
  emails and controllers.
- Section 2 is the journey in one line.
- Section 5 scenarios may step across tabs, emails and pages. Use steps like
  `When I open the link in the "Confirm your new email" email` and
  `Then the original tab shows "Connected to GitHub"`.
- Section 4 lists side effects at every hop.

```yaml
---
id: flow-github-connect
type: flow
title: Connect a GitHub account
entry: profile-github                        # or project-settings-github-sync; both can start it
exit: profile-github
surfaces:
  - profile-github
  - project-settings-github-sync
  - controller:oauth-github-callback
  - pubsub:github_oauth:<user_id>
---
```

---

## Instruction for cataloguing agents

Read the view's code, the policies and contexts it calls, and its tests. Then:

1. **Write sections 1 and 2 first.** Section 1 says who this is for and why it matters. Section 2 is
   the bare list of what they can do. Everything else is checked against those.
2. **For each behaviour you find**, cite file and line and place it in one of:
   section 3 (authorization), section 4 (what it touches), section 5 (a scenario with a Value
   line), or section 6 (unclear value, with a disposition). If you can write the Value line, it
   goes in 5. If you can't, it goes in 6. Don't force it.
3. **Edge cases are scenarios when they protect something.** "The last owner can't be removed" protects
   against orphaned projects: scenario. "Nulls sort first in last-activity desc" protects nothing you
   can name: section 6.2.
4. **A crash, a stale assign, copy that doesn't match the button, or a count that doesn't match the
   action is a possible bug.** Put it in 6.1. Never write it as a `@passing-old` scenario.
5. **If a behaviour spans another route, a controller, an email or a second browser tab**, don't write
   the scenario here. Create or reference a flow annotation and assert only the handoff in this file.
6. **If a behaviour depends on config or build**, name the variant in `config_variants` and tag the
   scenario. Say which variant you verified against.
7. **If a shared component or hook is involved**, reference the shared annotation in `inherits` and
   list what this view can't reach in `inventory.not_reachable_here`.
8. **Don't infer behaviour from test names.** Read the assertion.
9. **Don't invent value.** A thin "so that the user is happy" is worse than putting the item in 6.5.

---

## How the verification loop reads this file

1. **Inventory lint.** Generate the old-app inventory (routes incl. config-injected ones, `handle_event`
   clauses, JS hooks, policy functions, workers, API endpoints, email templates, config keys). Every item
   must appear in some annotation's `inventory` block or `not_reachable_here` list or section 6.3.
2. **Scenario lint.** Every `@Sxx` has a test. Every scenario has a Value line. Every `@cut` and every
   `drop` has a row in section 7. Every line in section 2 is referenced by a scenario. Every section 6
   item has a disposition. Every `decide` blocks `migrated`.
3. **Flow lint.** Every flow's `surfaces` entries exist. Every view that names a flow is in that flow's
   `surfaces`.
4. **Old-app run.** `@pending` and `@passing-old` scenarios run against current Lightning on the tagged
   variant. A failure means the annotation is wrong.
5. **New-app run.** `@passing-old` scenarios run against the rebuild. Passing ones become `@passing-new`.
6. **Report**, kept as separate lists: uncovered inventory, failing scenarios on the rebuild, section 6
   items still at `decide`, deliberate cuts, and possible bugs by disposition.
   `status: migrated` requires: inventory covered, every non-cut scenario `@passing-new`, no `decide`
   items, section 8 empty.
