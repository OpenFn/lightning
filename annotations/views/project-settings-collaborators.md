---
id: project-settings-collaborators
type: view
title: Project settings › Collaboration
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/settings#collaboration
  new_route: /projects/:project_id/settings/collaboration
  old_route_disposition: redirect
  reachable_when:
    - the project scope gate admits the viewer (see shared-project-scope); this includes support users with no membership row when the project allows support access
    - the client-side tab hash is "collaboration" (settings.html.heex:47-50, :570; Tabbed.container defaults to "project", settings.html.heex:25-29)

inherits:
  - shared-project-scope            # on_mount :project_scope (settings.ex:51); login, MFA, membership, live revocation
  - shared-usage-limits-banner      # on_mount :check_limits (settings.ex:52)
  - shared-authenticated-session
  - shared-project-header
  - shared-project-settings-tab-chrome
  - shared-flash-messages   # added by lead (final pass)

url_params: []                      # the tab is selected by URL hash, not params; apply_action(:index) ignores params (settings.ex:233)

config_variants:
  default: { Lightning.Extensions.usage_limiter: Lightning.Extensions.UsageLimiter }       # always :ok (config/config.exs:41-43)
  usage-limited: { Lightning.Extensions.usage_limiter: <adapter whose limit_action(%{type: :new_user, amount: n}) returns {:error, _, %{text: msg}}> }
  failure-alerts-limited: { Lightning.Extensions.usage_limiter: <adapter whose limit_action(%{type: :alert_failure}) returns {:error, _, _}> }
  # Read under default (code) and under the test build's MockUsageLimiter stubs (project_live_test.exs:4066-4211, :4542-4606)

inventory:
  routes:
    - live /projects/:project_id/settings  ProjectLive.Settings :index   # config-injected, config/config.exs:54-57
  events:
    - ProjectLive.Settings#toggle_collaborators_modal          # settings.ex:433
    - ProjectLive.Settings#toggle_invite_collaborators_modal   # settings.ex:442
    - ProjectLive.Settings#remove_project_user                 # settings.ex:647
    - ProjectLive.Settings#set_failure_alert                   # settings.ex:612-645
    - ProjectLive.Settings#set_digest                          # settings.ex:612-645
    - ProjectLive.Settings#toggle_support_access               # settings.ex:380
    - ProjectLive.Settings handle_info {:show_invite_collaborators_modal, _}   # settings.ex:710
    - ProjectLive.NewCollaboratorComponent#validate            # new_collaborator_component.ex:25
    - ProjectLive.NewCollaboratorComponent#add_collaborators   # new_collaborator_component.ex:38
    - ProjectLive.InviteCollaboratorComponent#validate         # invite_collaborator_component.ex:32
    - ProjectLive.InviteCollaboratorComponent#add_collaborators  # invite_collaborator_component.ex:45
  js_hooks:
    - Tooltip (disabled "Add collaborator(s)" and "Remove collaborator" buttons, support access info icon; new_inputs.ex:877, settings.ex:946-950)
    - JS.dispatch("change") on add-row and drop-row buttons (new_collaborator_component.html.heex:97, :117; invite_collaborator_component.html.heex:114)
    - show_modal / hide_modal for removal confirmation (settings.html.heex:621, settings.ex:813, :853)
    - TabbedContainer (host page tab switching, live/components/tabbed.ex:37)
  policies:
    - Lightning.Policies.ProjectUsers (:add_project_user, :remove_project_user, :edit_project, :edit_failure_alerts, :edit_digest_alerts)
  workers:
    - Lightning.Accounts.UserNotifier (Oban, type project_addition; projects.ex:836-847, user_notifier.ex:29-46)
  api_endpoints: []
  emails:
    - email:project-addition          # "You now have access to \"<project>\"" (user_notifier.ex:138-151)
    - email:project-invitation        # "Join <project> on OpenFn as a collaborator" (user_notifier.ex:452-458)
  config:
    - :lightning, Lightning.Extensions, :usage_limiter (limit_action :new_user, :alert_failure)
  not_reachable_here: []

related:
  - lib/lightning_web/live/project_live/settings.ex
  - lib/lightning_web/live/components/data_tables.ex          # collaborators_table, used only here
  - lib/lightning/projects.ex
  - lib/lightning/projects/audit.ex
  - lib/lightning/policies/project_users.ex
  - lib/lightning/digest_email_worker.ex                       # consumes the digest preference
  - lib/lightning/pipeline/failure_alerter.ex                  # consumes the failure alert preference
flows:
  - flow-invite-new-collaborator
  - flow-collaborator-added-email
  - flow-failure-alert-email
  - flow-digest-email
---

## 1. Purpose

Project owners and admins use this tab to decide who can see and work in a project: they add
people who already have OpenFn accounts, invite people who don't, remove people who should no
longer have access, and decide whether the instance's support staff may enter. Every member also
uses it to choose which emails they get about the project (failure alerts and a periodic digest).
Without it, access to health and survey data could only be granted or withdrawn by a superuser,
and members could not stop or start the alerts that tell them a workflow is failing.

## 2. What it does

- **See who's on the project**
  - Anyone who can open the project sees every collaborator with their role and notification settings
  - Members without admin rights are told what they can and can't change here
  - In a sandbox, the tab says changes here stay in the sandbox
- **Bring people in** (owners and admins)
  - Add existing users as viewers, editors or admins, several at a time
  - Invite people without an OpenFn account, which creates the account and adds them
  - Hosted plans can cap the number of collaborators
- **Take people out** (owners and admins)
  - Remove a collaborator, which also withdraws that person's credentials from the project
  - Owners, the acting user themselves and parent-project admins (in a sandbox) cannot be removed
- **Set your own notifications** (every member)
  - Set your own failure alert and digest frequency, and only your own
  - Hosted plans can switch off failure alerts
- Owners and admins grant or revoke support access

**Straightforwardness: 3 of 5.** Adding, removing and notification settings are what you'd expect, but there are notable gaps (no role changes) and several ways the add and invite forms can fail without telling you why.

### Most surprising behaviours

- **(2)** There's no way to change an existing collaborator's role on this tab; it seems only a superuser can do that, from a separate admin page. (6.5, 8)
- **(2)** "Invite sent successfully" shows even if the email never left the server, leaving the invitee with an account they can't log into and nobody aware of it. (6.1)
- **(3)** Admins can remove other admins, not just editors and viewers. (6.2, 8)
- **(3)** The add form talks about inviting people, but anyone who already has an account is added straight away with no acceptance step. (6.1)
- **(3)** Entering the same email twice in the add or invite form, or going over the collaborator cap while inviting, may crash the page or do nothing at all, with no message saying why. (6.1)

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:29-37` (admin actions), `:51` and `:96-110` (self
actions), `:155-161`; view gates in `settings.ex:124-137`, `:887-897`, `:901-910`.

| Action                                  | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|-----------------------------------------|--------|--------|-------|-------|--------------------|-----------------------------|
| See the tab and collaborator list       | yes    | yes    | yes   | yes   | no (cannot open the project) | yes               |
| Add existing users                      | no     | no     | yes   | yes   | no                 | no                          |
| Invite new users                        | no     | no     | yes   | yes   | no                 | no                          |
| Remove a collaborator                   | no     | no     | yes   | yes   | no                 | no                          |
| Remove an owner                         | no     | no     | no    | no    | no                 | no                          |
| Remove self                             | no     | no     | no    | no    | n/a                | n/a                         |
| Edit own failure alert and digest       | yes    | yes    | yes   | yes   | n/a                | n/a (no row)                |
| Edit another member's alert or digest   | no     | no     | no    | no    | no                 | no                          |
| Grant or revoke support access          | no     | no     | yes   | yes   | no                 | no                          |

**Preconditions beyond role**
- All actions denied when the project requires MFA and the actor hasn't enrolled (`project_users.ex:105-109`, `:134`); in practice the scope gate redirects first.
- Add and remove re-check the actor's role at submit time, not the mount-time assign (`new_collaborator_component.ex:41-47`, `invite_collaborator_component.ex:48-54`, `settings.ex:659-666`).
- The target membership must belong to this project (`projects.ex:466-481`, used at `settings.ex:627-631`, `:652-657`).
- Notification preferences are self-only: the membership row must be the actor's own (`project_users.ex:96-110`).
- In a sandbox, a user who is admin or owner on any ancestor project cannot be removed (`settings.ex:894-896`, `sandboxes.ex:776-785`).
- Adding is blocked when the usage limiter refuses `:new_user` for the number of rows (`new_collaborator_component.ex:153-169`, `settings.ex:919-927`).
- Failure alert controls require the limiter to allow `:alert_failure` (`settings.ex:189-190`, `data_tables.ex:487-517`).
- The "owner" role cannot be granted from this tab (`collaborators.ex:13`, `invited_collaborators.ex:16`).

## 4. What it touches

**Reads**: `projects` (incl. parent and ancestors for sandboxes), `project_users`, `users`, `credentials` and `project_credentials` (removal warning, `credentials.ex:1889-1901`)

**Writes**
- `project_users`: insert (add, invite), delete (remove), update `failure_alert` / `digest` (`projects.ex:814-834`, `:864-891`)
- `users`: insert for invited people, with a random password (`projects.ex:2048-2062`)
- `users_tokens`: insert a `reset_password` token per invited user (`projects.ex:2102-2117`)
- `project_credentials`: delete rows for the removed user's credentials (`projects.ex:738-755`)
- `projects.allow_support_access` (`settings.ex:384-391`)
- `audit_events` (below)

**Immediate side effects** (in the same request)
- Audit on item `project`: `collaborator_added`, `collaborator_removed` (`projects/audit.ex:47-85`), `allow_support_access_updated` (`projects/audit.ex:20-38`). Actor is the acting user; invitations are audited against the inviter.
- PubSub on the project topic: `ProjectUserAdded`, `ProjectUserRemoved` (`projects.ex:757-770`, `projects/events.ex:95-107`), `SupportAccessUpdated` (`projects.ex:776-780`, `events.ex:133-138`). Consumed by shared-project-scope.
- Email `email:project-invitation` sent synchronously to each invited person (`projects.ex:2079-2099`)
- Oban job `UserNotifier` type `project_addition` per newly added existing user (`projects.ex:836-847`)

**Deferred side effects** (later, elsewhere)
- `email:project-addition` delivered by the Oban job (`user_notifier.ex:29-46`, `:138-151`)
- The digest preference drives `Lightning.DigestEmailWorker` (`digest_email_worker.ex:19-34`); the failure alert preference drives `Lightning.FailureAlerter`
- Removed or support-revoked users' open pages leave the project (shared-project-scope S07, S09)

**External, non-transactional effects**
- The invitation email is delivered from inside the database transaction (`projects.ex:2010-2025`, `:2079-2099`); it cannot be recalled if the transaction later rolls back.

**Depends on config**
- Usage limiter adapter (`config/config.exs:41-43`) for `:new_user` and `:alert_failure`

**Product limits**
- Collaborator cap per project on hosted plans, reported in the limiter's own words (variant `usage-limited`)

## 5. Scenarios

```gherkin
Feature: Project collaboration settings
  In order to control who can reach a project's data and who hears about its failures
  As a project owner, admin or member
  I want to manage collaborators, support access and my own notifications

  @S01 @pending
  Scenario: Everyone on the project sees who else is on it
    # Value: members can tell who has access to the project's data before sharing anything with it.
    Given I am a viewer on project "Malawi HIV"
    And "Amara Banda" is an editor on the project
    When I open the collaboration tab
    Then I see "Amara Banda" with her email and role "Editor"
    And I see each collaborator's failure alert and digest setting
    # settings.ex:234, settings.html.heex:616-622, data_tables.ex:413-462

  @S02 @pending
  Scenario: Admin adds an existing user
    # Value: a new team member gets access the same day, without waiting for a superuser.
    Given I am an admin on project "Malawi HIV"
    And "amara@example.org" is a registered user not on the project
    When I click "Add collaborator(s)"
    And I enter "amara@example.org" with role "Editor"
    And I click "Save collaborator"
    Then I see "Collaborator added successfully"
    And "amara@example.org" appears in the list with role "Editor"
    And an audit event "collaborator_added" is recorded against me
    And the flow "flow-collaborator-added-email" has started for "amara@example.org"
    # new_collaborator_component.ex:38-74, :76-79; projects.ex:827-847; audit.ex:66-71
    # project_live_test.exs:4013-4064

  @S03 @pending
  Scenario: Admin adds several users in one go
    # Value: onboarding a whole team takes one form, not one round trip per person.
    Given I am an owner on project "Malawi HIV"
    And three registered users are not on the project
    When I add rows until there are three
    And I enter each user's email with roles "Admin", "Editor" and "Viewer"
    And I click "Save collaborators"
    Then I see "Collaborators added successfully"
    And all three appear in the list with those roles
    # new_collaborator_component.html.heex:86-124, :135-137; project_live_test.exs:3653-3706, :4013-4064

  @S04 @pending
  Scenario: Viewers and editors cannot add collaborators
    # Value: only people trusted with access decisions can grant access.
    Given I am an editor on project "Malawi HIV"
    When I open the collaboration tab
    Then the "Add collaborator(s)" button is disabled with tooltip "You are not authorized to perform this action"
    And sending "toggle_collaborators_modal" does not open the add form
    # settings.html.heex:577-588, :599-606; project_live_test.exs:3600-3651

  @S05 @pending
  Scenario: The owner role cannot be granted when adding
    # Value: a project keeps exactly one owner, so ownership can't be handed out by accident.
    Given I am an admin on project "Malawi HIV"
    When I open the add form
    Then the role options are "Viewer", "Editor" and "Admin"
    And submitting role "owner" anyway shows "is invalid"
    # new_collaborator_component.html.heex:72-84; collaborators.ex:13; project_live_test.exs:3977-4011

  @S06 @pending
  Scenario: Adding someone already on the project is refused
    # Value: an admin can't silently overwrite an existing member's access.
    Given I am an admin on project "Malawi HIV"
    And "amara@example.org" is already on the project
    When I submit the add form with "amara@example.org"
    Then I see "This account is already part of this project"
    And nothing is saved
    # collaborators.ex:82-108; project_live_test.exs:3943-3975

  @S07 @pending
  Scenario: An invalid email is caught before saving
    # Value: access isn't granted to a typo.
    Given I am an owner on project "Malawi HIV"
    When I type "not-an-email" in the add form
    Then I see "Email address not valid."
    And the save button is disabled
    # collaborators.ex:28-33, new_collaborator_component.html.heex:133; project_live_test.exs:3708-3748

  @S08 @pending
  Scenario: People without an account move on to the invite form
    # Value: an admin can bring in a colleague who has never used OpenFn without retyping their details.
    Given I am an owner on project "Malawi HIV"
    And "new.person@example.org" has no OpenFn account
    When I submit the add form with "new.person@example.org" as "Editor"
    Then I see "This collaborator does not have an OpenFn account. Invite them to join OpenFn and grant access to the project."
    And the "Invite new user(s) to join OpenFn" form opens with that email and role filled in
    # new_collaborator_component.ex:58-64, :80-82; settings.ex:710-718; invite_collaborator_component.ex:12-29
    # project_live_test.exs:3811-3833

  @S09 @pending
  Scenario: Mixed list adds the people with accounts and invites the rest
    # Value: one submission handles a team where only some people already use OpenFn.
    Given I am an owner on project "Malawi HIV"
    And "amara@example.org" is registered and "new.person@example.org" is not
    When I submit the add form with both
    Then "amara@example.org" is added to the project
    And I see "1 out of 2 collaborators have OpenFn accounts and have been added to your project. You can invite others to join OpenFn and grant them access to this project."
    And the invite form opens for "new.person@example.org" only
    # new_collaborator_component.ex:49-64, :87-90, :115-132

  @S10 @pending
  Scenario: Admin invites a person without an account
    # Value: the project can grow beyond people who already have accounts on this instance.
    Given the invite form is open for "new.person@example.org" as "Editor"
    When I enter first name "Non" and last name "Exists"
    And I click "Invite new user"
    Then I see "Invite sent successfully"
    And "Non Exists" appears in the list with role "Editor"
    And no "You now have access to" email is sent to them
    And the flow "flow-invite-new-collaborator" has started for "new.person@example.org"
    # invite_collaborator_component.ex:45-75; projects.ex:2010-2025; project_live_test.exs:3811-3871

  @S11 @pending
  Scenario: An invite to an email that already has an account is refused
    # Value: inviting can't create a duplicate or take over an existing account.
    Given the invite form is open
    When I change the email to that of a registered user and submit
    Then I see "This email is already taken"
    And no email is sent
    # invited_collaborators.ex:38-81; project_live_test.exs:3873-3941

  @S12 @pending @variant:usage-limited
  Scenario: The add button is disabled when the collaborator cap is reached
    # Value: admins learn their plan's limit before filling in a form they can't submit.
    Given project "Malawi HIV" has reached its collaborator limit with message "You can only have 3 collaborators in this project"
    And I am an admin on the project
    When I open the collaboration tab
    Then the "Add collaborator(s)" button is disabled
    And its tooltip says "You can only have 3 collaborators in this project"
    # settings.html.heex:577-584, settings.ex:919-927; project_live_test.exs:4066-4096

  @S13 @pending @variant:usage-limited
  Scenario: Adding more rows than the plan allows is blocked in the form
    # Value: a project can't exceed the collaborator count its plan pays for.
    Given project "Malawi HIV" may add 2 more collaborators
    And I am an admin with the add form open
    When I add a third row
    Then I see the limiter's message in the form
    And the save button is disabled
    When I remove a row
    Then the message goes away
    # new_collaborator_component.ex:25-36, :153-169; .html.heex:41-52, :133; project_live_test.exs:4098-4211

  @S14 @pending
  Scenario: Admin removes a collaborator
    # Value: someone who has left the team loses access to the project's data straight away.
    Given I am an admin on project "Malawi HIV"
    And "Amara Banda" is a viewer on the project
    When I click "Remove collaborator" on her row
    And I confirm in "Remove Amara Banda"
    Then I see "Collaborator removed"
    And she is no longer in the list
    And her user account still exists
    And an audit event "collaborator_removed" is recorded against me
    And her open project pages are handed to shared-project-scope S07
    # settings.ex:647-681, :792-860; projects.ex:864-891; project_live_test.exs:4220-4302

  @S15 @pending
  Scenario: Removal warns about and withdraws the person's credentials
    # Value: the admin knows which workflow credentials will stop being available before confirming.
    Given I am an admin on project "Malawi HIV"
    And "Amy Admin" is a viewer who owns credentials "DHIS2 play" and "PostgreSQL" shared with the project
    When I open the removal confirmation for "Amy Admin"
    Then it says "and their owned credentials DHIS2 play, PostgreSQL will be removed from it"
    When I confirm
    Then neither credential is available in project "Malawi HIV"
    # settings.ex:792-815; projects.ex:738-755; project_live_test.exs:4608-4664; membership_events_test.exs:153

  @S16 @pending
  Scenario: Viewers and editors cannot remove collaborators
    # Value: only people trusted with access decisions can withdraw access.
    Given I am an editor on project "Malawi HIV"
    When I open the collaboration tab
    Then every "Remove collaborator" button is disabled with tooltip "You do not have permission to remove a user"
    And sending "remove_project_user" for a member shows "You are not authorized to perform this action."
    And the member is still on the project
    # settings.html.heex:617-645, settings.ex:870-871, :751-765; project_live_test.exs:4220-4256

  @S17 @pending
  Scenario: The owner cannot be removed
    # Value: a project never ends up with nobody able to administer it.
    Given I am an admin on project "Malawi HIV"
    When I open the collaboration tab
    Then the owner's "Remove collaborator" button is disabled with tooltip "You cannot remove an owner"
    And sending "remove_project_user" for the owner is refused
    # settings.ex:876-877, :894; projects.ex:867-870; project_live_test.exs:4304-4342

  @S18 @pending
  Scenario: Admins cannot remove themselves
    # Value: an admin can't lock themselves out by a misclick.
    Given I am an admin on project "Malawi HIV"
    When I open the collaboration tab
    Then my own "Remove collaborator" button is disabled with tooltip "You cannot remove yourself"
    And sending "remove_project_user" for my row is refused
    # settings.ex:873-874, :895; project_live_test.exs:4344-4380

  @S19 @pending
  Scenario: A parent project's admins cannot be removed from a sandbox
    # Value: a sandbox can't lock out the people who administer the project it came from.
    Given "Parent Admin" is an admin on project "Malawi HIV"
    And "Parent Admin" is an editor on its sandbox "dev"
    And I am the owner of "dev"
    When I open the collaboration tab of "dev"
    Then "Parent Admin"'s "Remove collaborator" button is disabled with tooltip "Cannot remove a user who is admin or owner on the parent project"
    # settings.ex:879-880, :896, :912-913; projects.ex:872-879; sandbox_settings_test.exs:418-447

  @S20 @pending
  Scenario: An admin demoted after loading the page cannot remove anyone
    # Value: withdrawn authority takes effect even on a page that was already open.
    Given I have the collaboration tab open as an admin on project "Malawi HIV"
    And I am demoted to editor without my page reloading
    When I confirm removing "Amara Banda"
    Then I see "You are not authorized to perform this action."
    And she is still on the project
    # settings.ex:659-666; membership_revocation_test.exs:118-141

  @S21 @pending
  Scenario: Memberships of another project cannot be touched from this one
    # Value: being an admin of one project gives no power over another project's members.
    Given I am an admin on project "Malawi HIV"
    And "Bob" is an editor on project "Kenya TB" only
    When I send "remove_project_user", "set_failure_alert" or "set_digest" with Bob's membership id
    Then I see "You are not authorized to perform this action."
    And Bob's membership is unchanged
    # projects.ex:466-481; settings.ex:627-643, :652-679; project_live_test.exs:4382-4430

  @S22 @pending
  Scenario: A member turns on their own failure alerts
    # Value: people responsible for a workflow find out when it fails, without asking an admin.
    Given I am an editor on project "Malawi HIV" with failure alerts disabled
    When I set my failure alert to "Enabled"
    Then I see a success message
    And my failure alert shows "Enabled"
    And the flow "flow-failure-alert-email" uses my new setting
    # data_tables.ex:480-517; settings.ex:619-645, :726-742; projects.ex:814-825; project_live_test.exs:2011-2060, :4484-4505

  @S23 @pending
  Scenario: A member chooses how often they get the digest
    # Value: each member controls how much project email they receive.
    Given I am a viewer on project "Malawi HIV" with digest "Never"
    When I set my digest to "Weekly"
    Then my digest shows "Weekly"
    # data_tables.ex:520-559; settings.ex:619-645; project_live_test.exs:4507-4526

  @S24 @pending
  Scenario: Members cannot change other members' notifications
    # Value: nobody can silence, or flood, a colleague's inbox.
    Given I am an admin on project "Malawi HIV"
    And "Amara Banda" has failure alerts enabled and digest "Never"
    When I open the collaboration tab
    Then Amara's failure alert and digest are shown as text, not selects
    And sending "set_failure_alert" or "set_digest" for her row shows "You are not authorized to perform this action."
    And her settings are unchanged
    # data_tables.ex:561-575; settings.ex:899-910; project_live_test.exs:4432-4482

  @S25 @pending @variant:failure-alerts-limited
  Scenario: Failure alerts show as unavailable when the plan doesn't include them
    # Value: members aren't promised alerts the instance won't send.
    Given failure alerts are not available for project "Malawi HIV"
    And I have failure alerts enabled
    When I open the collaboration tab
    Then my failure alert shows "Unavailable" and cannot be changed
    # settings.ex:189-190; data_tables.ex:510-515; project_live_test.exs:4542-4606

  @S26 @pending
  Scenario: Admin grants and revokes support access
    # Value: a customer decides when the instance's support staff may enter their project, and can take that back.
    Given I am an admin on project "Malawi HIV" with support access off
    When I switch on "Grant support access"
    Then I see "Granted access to support users successfully"
    And an audit event "allow_support_access_updated" is recorded
    When I switch it off
    Then I see "Revoked access to support users successfully"
    And open support sessions are handed to shared-project-scope S09
    # settings.ex:380-409, :929-957; projects.ex:589-618, :776-780; project_live_test.exs:2207-2235

  @S27 @pending
  Scenario: Viewers and editors don't see the support access switch
    # Value: only people trusted with access decisions can let outsiders in.
    Given I am an editor on project "Malawi HIV"
    When I open the collaboration tab
    Then I do not see "Grant support access"
    # settings.ex:935; project_live_test.exs:2237-2257

  @S28 @pending
  Scenario: Members without admin rights are told what they can change
    # Value: a member knows why the controls are disabled and that their own notifications are still theirs to set.
    Given I am a viewer on project "Malawi HIV"
    When I open the collaboration tab
    Then I see "Role based permissions: You cannot modify this project's collaboration settings, but you can change your notification preferences."
    # settings.html.heex:574-575; layout_components.ex:589-591, :623-629

  @S29 @pending
  Scenario: A sandbox says its membership changes stay in the sandbox
    # Value: admins know that adding someone to a sandbox does not add them to the live project.
    Given I am the owner of sandbox "dev" of project "Malawi HIV"
    When I open the collaboration tab of "dev"
    Then I see "Changes you make here only apply to this sandbox and do not sync to the parent project on merge."
    # settings.html.heex:590-594; sandbox_settings_banner.ex:30-38; sandbox_settings_test.exs:116-126
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Invite submit over the collaborator limit discards the limiter's message: `limit_adding_users` returns `{:noreply, socket_with_error}`, which falls to the `_error -> {:noreply, socket}` clause with the original socket | `invite_collaborator_component.ex:55`, `:83-84`, `:109-125` | clicking "Invite new user" does nothing and shows no reason (unless a prior keystroke already showed it) | fix |
| A failed invite transaction (user registration fails, or the membership changeset errors) assigns a non-form value as `@changeset`; `{:error, :user_registration_failed}` is an atom and a membership error is a `Project` changeset with no `:invited_collaborators` | `invite_collaborator_component.ex:80-81`; `projects.ex:2027-2031`, `:2048-2062` | the LiveView likely crashes and the page reloads without explanation (not reproduced) | fix |
| Two rows with the same email are not deduplicated. In the add form both reach `add_project_users`, the unique constraint fails, and the `Project` changeset is assigned to the component, whose template calls `inputs_for` on `:collaborators`. The same path is reached if someone else added the person after the form opened, since "already part of this project" checks the list captured when the modal rendered | `collaborators.ex:37-80`; `new_collaborator_component.ex:134-151`; `.html.heex:53-57`, `:93`; `project_user.ex:55-57` | likely a crash and page reload instead of a field error (not reproduced) | fix |
| Two invite rows with the same email build two `Ecto.Multi` steps named `{:new_user, email}`, which Ecto refuses | `projects.ex:2048-2062` | likely a crash on "Invite new users" (not reproduced) | fix |
| Invitation emails are sent with `Enum.each` and the mailer result is ignored; the flash reports success regardless | `projects.ex:2081-2096`, `invite_collaborator_component.ex:67-72` | "Invite sent successfully" even when no email left the server; the invitee has an account they can't log into | decide |
| `toggle_support_access` hard-matches `{:ok, project}` from `update_project` | `settings.ex:384-391` | a validation or hook error would crash the page instead of showing a message | fix |
| Add form subtitle says "Enter the email address and role of new collaborator(s) to invite them to this project", but existing users are added immediately without any invitation | `new_collaborator_component.html.heex:25-29` | admins may expect the person to accept something; they are already in | fix |
| The read-only notice says "but you can change your notification preferences" to support users with no membership row, who have no preferences to change | `settings.html.heex:574`; `data_tables.ex:427-457` | a promise the page can't keep | fix |
| Success flash for notification changes is misspelled: "Project user updated successfuly" | `settings.ex:735` | a typo in a flash | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Collaborators are ordered by first name only (ties in database order) | `projects.ex:527-535` | decide |
| Current user's row carries "Well hello, you!" | `data_tables.ex:432-436` | preserve |
| After adding only existing users the page does a full `push_navigate`; when some need inviting it does a `push_patch` and opens the invite modal by sending itself a message, relying on the patch's `handle_params` running before that message | `new_collaborator_component.ex:58-64`, `settings.ex:233-258`, `:710-718` | decide |
| Removal success re-mounts the whole page via `push_navigate` | `settings.ex:670-676` | decide |
| Refusals from the add and invite components navigate back to the tab (re-running the scope gate); refusals from the host page only flash | `live_helpers.ex:220-224`; `settings.ex:751-765` | decide |
| Refused actions log a warning naming the project and user | `settings.ex:761` | preserve |
| Submitting a notification value equal to the current one does nothing, with no flash | `projects.ex:814-825`, `settings.ex:637` | preserve |
| An invalid digest value shows "Error when updating the project user" | `settings.ex:737-741` | preserve |
| Non-admins see the "Add collaborator(s)" button disabled rather than hidden; tooltip shows the limit message only to admins | `settings.html.heex:577-588` | decide |
| Remove tooltip reasons are checked in a fixed order (permission, self, owner, parent admin), so only the first applicable reason shows | `settings.ex:868-884` | decide |
| An admin can remove other admins | `settings.ex:894-896` | decide |
| The removal confirmation lists credentials sorted case-insensitively by name | `credentials.ex:1897` | decide |
| The add form starts with one row; the remove-row button appears only when there are two or more | `new_collaborator_component.html.heex:53-57`, `:92-102`; project_live_test.exs:3653-3706 | decide |
| The invite form has no "add row" control; it can only drop rows carried over from the add form | `invite_collaborator_component.html.heex:53-127` | decide |
| Invited users get a random password; the invitation link is a reset-password token | `projects.ex:2052-2055`, `:2102-2117`; `user_notifier.ex:458` | preserve |
| The support access tooltip promises "editor permissions", which matches the policy for support users without a row | `settings.ex:946-950`; `project_users.ex:167-169` | preserve |
| The support access switch renders only on this tab, though it is a security setting | `settings.html.heex:595-598` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| Empty state "No collaborators found." with "Add a collaborator" button | `settings.html.heex:651-663` | every project has an owner row (`project.ex:282-320`), so the list is never empty for anyone who can open it |
| `delete_project_user!` raising for the owner or a parent admin | `projects.ex:867-879` | the view's `user_removable?/5` refuses both first (`settings.ex:887-897`) |
| `raise "membership update failed..."` | `projects.ex:657-660` | only on database failure |
| Catch-all `handle_info` for unknown messages | `settings.ex:720-724` | exists for Swoosh test messages per its comment |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| A removal modal, with its own credentials query, is rendered for every removable collaborator on every render | `settings.html.heex:665-678`, `settings.ex:792-797` | no, slower page on large projects | fix |
| `parent_admin?` walks the ancestor chain per row, up to three times per row (tooltip, disabled state, modal) | `settings.html.heex:623-645`, `:666-674`; `sandboxes.ex:776-795` | no | fix |
| The collaborator list is unpaginated | `projects.ex:527-535` | no | preserve |
| Email inputs debounce 300 ms | `new_collaborator_component.html.heex:68`, `invite_collaborator_component.html.heex:85` | barely | decide |
| Project addition email job runs once (`max_attempts: 1`) on the `background` queue | `user_notifier.ex:8-10` | yes, a transient mail failure means no email | decide |
| Limiter is called on every keystroke-driven validate in the add and invite forms | `new_collaborator_component.ex:33`, `invite_collaborator_component.ex:40` | no | preserve |

### 6.5 Things seen but not understood

- There is no control on this tab to change a collaborator's role. The template example lists `update_role`, but no such event exists in `settings.ex`; role changes appear to happen only through the superuser project form (`membership_revocation_test.exs:143-175`). Unclear whether that is intended.
- `mount` assigns `project_user` (`settings.ex:113`) but this tab never reads it.
- The add form validates the role as required and the email format, but the email error is only shown after the field is used (`new_collaborator_component.ex:94-113`); unclear whether role errors render the same way.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Where do role changes for existing collaborators live in the rebuild? Today this tab cannot change a role.
- Should the support access switch stay on this tab or move to security?
- Should invitation emails be sent after the transaction commits, and should a mailer failure be reported to the inviter?
- Should admins be able to remove other admins, or only owners?

## Proposed flows

- `flow-invite-new-collaborator`: an admin invites someone without an account; they receive "Join <project> on OpenFn as a collaborator", follow the reset-password link, set a password and land in the project. Surfaces: project-settings-collaborators, email:project-invitation, auth-reset-password (`/users/reset_password/:token`), workflows-index.
- `flow-collaborator-added-email`: adding an existing user queues a `UserNotifier` job that emails "You now have access to \"<project>\"" with a link to the project's workflows. Surfaces: project-settings-collaborators, worker:UserNotifier(project_addition), email:project-addition, workflows-index.
- `flow-notification-preferences`: a member's failure alert and digest settings decide whether the failure alerter and the digest worker email them. Surfaces: project-settings-collaborators, capability:failure-alerter, email:failure-alert, capability:digest-email-worker, email:project-digest.
- Referenced, not proposed: removal and support-access revocation teardown are owned by shared-project-scope (S07, S09).

## Proposed shared

- `shared-project-settings-tab-chrome`: the section header with its role-based permissions notice, and the sandbox settings banner (local, editable, inherited variants), rendered at the top of every project settings tab. Surfaces: all nine project-settings-* views (`layout_components.ex:568-629`, `components/sandbox_settings_banner.ex:30-60`).

## Lead resolution (batch 1)

- Flows created as proposed, except `flow-notification-preferences`, merged into `flow-failure-alert-email` and `flow-digest-email`.
- `shared-project-settings-tab-chrome` created; it also absorbs the sandbox banner and section header proposed by project-settings-setup.
- `drop` dispositions changed to `decide`: cuts are for a human to make.
