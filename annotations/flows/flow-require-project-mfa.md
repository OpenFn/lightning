---
id: flow-require-project-mfa
type: flow
title: Requiring MFA on a project
owner:

trigger:
  entry: project-settings-security
  exit: workflows-index
  surfaces:
    - project-settings-security
    - mfa-required
    - profile-mfa
    - workflows-index
    - profile-backup-codes
  reachable_when:
    - the actor is an owner or admin on the project and passes the usage limiter for `:require_mfa` (project-settings-security S01, S06; settings.ex:411-414)
    - the project is not a sandbox (project-settings-security S07; settings.html.heex:731-732)
    - at least one member (or a support user reaching the project through support access) has not enrolled in MFA (`users.mfa_enabled` not true; scope.ex:217-224)

inherits:
shared-project-scope            # the receiving gate: S05 sends an unenrolled member to /mfa_required
  - shared-authenticated-session    # /mfa_required and /profile are signed-in pages outside the project scope

url_params: []                      # /mfa_required takes no params; nothing records which project sent the member there (hooks.ex:100-101)

config_variants:
  default: { Lightning.Extensions.usage_limiter: Lightning.Extensions.UsageLimiter }   # read under this one; the entry switch is always enabled for admins (usage_limiter.ex:11)
  mfa-limited: { Lightning.Extensions.usage_limiter: <adapter refusing %Action{type: :require_mfa}> }   # the flow cannot start (project-settings-security S06)

inventory:
  routes:
    - live /mfa_required  ProjectLive.MFARequired :index            # router.ex:288-289, live_session :default
    - live /profile  ProfileLive.Edit :edit                         # config-injected, config/config.exs:58-59; MFA card at components.ex:57-61
    - live /profile/auth/backup_codes  BackupCodesLive.Index :index # router.ex:252-265, sudo; where first enrolment lands
    - live /projects/:project_id/w  WorkflowLive.Index :index      # exit, router.ex:301
  events:
    - ProjectLive.Settings#toggle-mfa                               # entry, owned by project-settings-security
    - ProfileLive.MfaComponent#show-mfa-options                     # mfa_component.ex:24-47
    - ProfileLive.MfaComponent#save_totp                            # mfa_component.ex:53-66
  js_hooks: []
  policies:
    - Lightning.Policies.ProjectUsers.permitted?/2 (MFA clause, project_users.ex:134)
    - Lightning.Policies.ProjectUsers.blocked_by_mfa?/1 (project_users.ex:186-188)
    - Lightning.Projects.Scope mfa_satisfied? (scope.ex:217-224)
  workers: []
  api_endpoints: []
  emails: []
  config:
    - :lightning, Lightning.Extensions, :usage_limiter (config/config.exs:43; entry only)
    - :lightning, :totp_client (mfa_component.ex:27; test seam for the TOTP secret)
  not_reachable_here:
    - ProfileLive.MfaComponent#hide-mfa-options and #disable_mfa (mfa_component.ex:49-51, :68-87); owned by profile-mfa
    - BackupCodesLive.Index#regenerate-backup-codes (backup_codes_live/index.ex:27-35); owned by profile-backup-codes

related:
  - lib/lightning_web/live/project_live/mfa_required.ex
  - lib/lightning_web/live/project_live/mfa_required.html.heex
  - lib/lightning_web/live/profile_live/mfa_component.ex
  - lib/lightning/accounts.ex           # upsert_user_totp/2 sets mfa_enabled (accounts.ex:415-437)
  - lib/lightning_web/hooks.ex          # :project_scope MFA branch (hooks.ex:98-101)
  - flow-digest-email                   # S04 there: unenrolled members stop getting digests once the requirement is on
  - flow-failure-alert-email            # S05 there: same rule for failure alerts
flows: []
---

## 1. Purpose

A project owner or admin decides that a project holding health or survey data
can only be reached from accounts protected by multi-factor authentication. This
flow carries that decision to every member: those already enrolled carry on, and
those who aren't are stopped at the door, told why, sent to enrol, and let back
in once they have. Without it the requirement would either not be enforced, or
would lock people out with no explanation and no way back.

## 2. What it does

1. A project owner or admin turns on "Require MFA?" on the project's security
   settings.
2. Members who already use multi-factor authentication carry on as normal.
3. A member who hasn't set it up is sent, on their next project page, to a page
   explaining that the project requires it.
4. They follow "Visit your account", turn on multi-factor on their profile and
   confirm a code from their authenticator app.
   - A code that doesn't check out leaves them locked out
   - Once set up, they land on their backup codes page, and the explanation page
     no longer holds them
5. The project's pages open for them again.

**Straightforwardness: 3 of 5.** The idea is simple, but the rule bites the
person switching it on.

### Most surprising behaviours

- **(2)** An owner or admin who hasn't set up multi-factor can turn the
  requirement on and is blocked by it at once, including from turning it back
  off, until they enrol; the superuser project form has no control for it. (6.1)
- **(3)** The explanation page doesn't say which project sent them there and
  doesn't bring them back afterwards, so after setting up they have to find the
  project again. (6.2)
- **(3)** Members who haven't set up multi-factor quietly stop getting the
  project's digest and failure alert emails until they do. (4)

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:134` (any action is refused
while MFA is unsatisfied), `:186-188` (`blocked_by_mfa?`: standing on the
project but MFA unsatisfied), `lib/lightning/projects/scope.ex:217-224` (only
`mfa_enabled == true` counts; support users are bound too). Starting the flow is
governed by project-settings-security section 3.

| Action                                   | Viewer         | Editor         | Admin          | Owner          | Superuser (no row)                       | Support (no row, access on) |
| ---------------------------------------- | -------------- | -------------- | -------------- | -------------- | ---------------------------------------- | --------------------------- |
| Turn the requirement on (start the flow) | no             | no             | yes            | yes            | no                                       | no                          |
| Sent to `/mfa_required` while unenrolled | yes            | yes            | yes            | yes            | no (Not Found, shared-project-scope S03) | yes                         |
| Enrol on the profile                     | yes, self only | yes, self only | yes, self only | yes, self only | yes, self only                           | yes, self only              |
| Open the project once enrolled           | yes            | yes            | yes            | yes            | no                                       | yes                         |

**Preconditions beyond role**

- The requirement applies to the actor who turned it on: an admin who has not
  enrolled is locked out by their own change (6.1).
- Enrolment needs a valid six-digit code from the app (`user_totp.ex:26-43`).
- `/mfa_required` admits any signed-in user who has not enrolled, whatever
  project sent them, and redirects enrolled users to `/projects`
  (`mfa_required.ex:16-24`).

## 4. What it touches

**Hop 1: owner turns on the requirement (project-settings-security)**

- Writes `projects.requires_mfa` and an audit event `requires_mfa_updated`
  (`settings.ex:411-427`; `projects.ex:589-598`; `audit.ex:15`, `:20-38`). Owned
  by project-settings-security S01.

**Hop 2: member's next project page (shared-project-scope)**

- Reads `projects`, `project_users`, `users.mfa_enabled` through `Scope.fetch/2`
  (`scope.ex:111-117`, `:184-200`).
- `:project_scope` halts with a redirect to `/mfa_required` when
  `blocked_by_mfa?` (`hooks.ex:98-101`). The socket has already subscribed to
  the project topic (`hooks.ex:86`, `:272-287`); the subscription dies with the
  halted mount.

**Hop 3: `/mfa_required`**

- Reads the viewer's projects for the menu (`mfa_required.ex:9`;
  `hooks.ex:194-202`). Writes nothing.

**Hop 4: enrolment on the profile (profile-mfa)**

- Generates a TOTP secret in memory (`mfa_component.ex:27-36`).
- On a valid code, one transaction: upserts `user_totps` (secret,
  `last_totp_at`), sets `users.mfa_enabled = true`, and generates backup codes
  if the user has none (`accounts.ex:415-437`).
- On first enrolment inserts a `sudo_session` user token and redirects to
  `/profile/auth/backup_codes?sudo_token=...` with flash "MFA Setup"
  (`mfa_component.ex:56-61`, `:89-97`; `accounts.ex:1021-1025`). Re-enrolling a
  device returns to `/profile` instead (`mfa_component.ex:90-91`).
- No broadcast.

**Hop 5: back into the project (workflows-index)**

- Same reads as hop 2; `blocked_by_mfa?` is now false and the page mounts
  (`hooks.ex:102-118`).

**Immediate side effects**

- Hop 1 audit event (above). Nothing else in this flow is immediate.

**Deferred side effects** (outside this flow's surfaces, asserted only as
handoffs)

- Digest and failure-alert emails stop reaching unenrolled members
  (`mail_recipients.ex:28-32`; flow-digest-email S04, flow-failure-alert-email
  S05) and resume once they enrol.
- Plain routes, the bearer-token API and websocket channel joins refuse
  unenrolled members through the same policy clause (`project_users.ex:134`;
  `project_mfa_enforcement_test.exs:1-35`;
  `workflow_channel_test.exs:1771-1822`).

**External, non-transactional effects**

- none

**Depends on config**

- `usage_limiter` decides whether hop 1 can happen at all (variant
  `mfa-limited`; project-settings-security S06).

**Product limits**

- none

## 5. Scenarios

```gherkin
Feature: Requiring MFA on a project
  In order to keep a project reachable only from MFA-protected accounts
  As a project owner, and as a member of that project
  I want the requirement to stop unenrolled members, tell them why, and let them back in once they enrol

  @S01
  Scenario: Turning on the requirement sends an unenrolled member to enrol on their next page
    # Value: the owner's decision takes effect for every member without anyone having to chase them, and the member is told why they were stopped.
    Given I am an owner on project "Malawi HIV" who has enrolled in MFA
    And "bob@example.org" is an editor on project "Malawi HIV" who has not enrolled in MFA
    When I turn on the "Require MFA?" switch on the "Security" tab
    And Bob, logged in, opens the workflows page of project "Malawi HIV"
    Then Bob is on "/mfa_required"
    And Bob sees "This project requires all members to use multi-factor authentication."
    And Bob sees a "Visit your account" link to "/profile"
    # entry: project-settings-security S01 (settings.ex:411-427)
    # gate: shared-project-scope S05 (hooks.ex:98-101; project_users.ex:186-188; scope.ex:221-222)
    # mfa_required.html.heex:29-46; mfa_required_live_test.exs:11-18; index_test.exs:85-111

  @S02
  Scenario: Members already enrolled keep working
    # Value: the requirement only gets in the way of accounts that aren't protected, so compliant members aren't disrupted.
    Given project "Malawi HIV" requires MFA
    And Amara is an admin on project "Malawi HIV" who has enrolled in MFA
    When Amara opens the workflows page of project "Malawi HIV"
    Then she sees the workflows page for project "Malawi HIV"
    # scope.ex:221-222; project_users.ex:136, :193-194; index_test.exs:89-102

  @S03
  Scenario: A stopped member enrols on their profile and gets back in
    # Value: a member turned away by the requirement can restore their own access in a few minutes, without asking an admin.
    Given project "Malawi HIV" requires MFA
    And I am an editor on project "Malawi HIV" who has not enrolled in MFA
    And I am on "/mfa_required"
    When I click "Visit your account"
    Then I am on "/profile"
    When I click the "Enable multi-factor authentication" switch
    Then I see "Scan the QR code"
    When I enter a valid code from my authenticator app in "Verify the code from the app" and click "Save"
    Then I see "MFA Setup"
    And I am on the two-factor backup codes page
    When I open the workflows page of project "Malawi HIV"
    Then I see the workflows page for project "Malawi HIV"
    # mfa_required.html.heex:35-46; components.ex:57-61; mfa_component.ex:24-66, :89-97
    # accounts.ex:415-437 (mfa_enabled set in the same transaction); hooks.ex:98-118
    # profile_live_test.exs:311-349 (enrol, sudo token, redirect, flash); the return to the project is untested

  @S04
  Scenario: Code that doesn't verify leaves the member locked out
    # Value: a member can't satisfy the requirement without actually having a working second factor.
    Given project "Malawi HIV" requires MFA
    And I am an editor on project "Malawi HIV" who has not enrolled in MFA
    And I have opened the QR code on "/profile"
    When I enter "123456", which is not a valid code, and click "Save"
    Then I see "invalid code"
    And opening the workflows page of project "Malawi HIV" still takes me to "/mfa_required"
    # user_totp.ex:26-43, :58-65; mfa_component.ex:63-64; accounts.ex:433-436 (no mfa_enabled write on error)

  @S05
  Scenario: Someone who has enrolled is not kept on the MFA required page
    # Value: a member who has just enrolled, or follows an old bookmark, isn't left on a page that tells them they are blocked.
    Given I have enrolled in MFA
    When I visit "/mfa_required"
    Then I am on "/projects"
    # mfa_required.ex:16-24; mfa_required_live_test.exs:20-29
```

The receiving gate itself (an unenrolled member of an MFA-required project is
sent to `/mfa_required`) is shared-project-scope S05. Not restated here; S01
only chains it to the entry. Withheld emails are flow-digest-email S04 and
flow-failure-alert-email S05.

## 6. Unclear value

### 6.1 Possible bugs

| What                                                                                                                                                                                                                                                        | Where                                                                                                                               | What a user sees                                                                                                      | Disposition |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ----------- |
| An owner or admin who hasn't enrolled can turn the requirement on and is blocked by it at once, including from turning it back off, until they enrol; the superuser project form has no control for it (it casts `requires_mfa` but renders nothing for it) | `settings.ex:411-427`; `project_users.ex:134`; `project.ex:165-180`; `form_component.ex:76-80`; project-settings-security 6.1 row 1 | success flash, then "not authorized" on every action and `/mfa_required` on the next page, with no warning beforehand | decide      |
| `/mfa_required` shows "This project requires..." to any signed-in unenrolled user who reaches it, including someone with no MFA-required project at all                                                                                                     | `mfa_required.ex:16-24`; `mfa_required.html.heex:33-38`                                                                             | a page saying a project requires MFA when none does                                                                   | fix         |

### 6.2 Quirks and implementation details

| What                                                                                                                                                       | Where                                                                            | Disposition |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | ----------- |
| `/mfa_required` doesn't name the project that sent the member there, and nothing remembers it, so after enrolling the member has to find the project again | `hooks.ex:100-101`; `mfa_required.html.heex:28-46`                               | decide      |
| First enrolment lands on the backup codes page, not back on the project or the profile                                                                     | `mfa_component.ex:89-97`                                                         | preserve    |
| Enrolment counts straight away for the current session; the member isn't asked to sign in again with the new factor                                        | `accounts.ex:415-437`; `scope.ex:221-222` reads only `users.mfa_enabled`         | preserve    |
| A member who later disables MFA on their profile is warned only that their account is less secure, not that they will lose access to MFA-required projects | `mfa_component.html.heex:91-95`; `mfa_component.ex:68-76`; `accounts.ex:444-457` | decide      |
| The MFA required page title is title case ("MFA Required for Project")                                                                                     | `mfa_required.ex:32`                                                             | decide      |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
| ---- | ----- | --------------- |
| none |       |                 |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
| ---- | ----- | ------------- | ----------- |
| none |       |               |             |

### 6.5 Things seen but not understood

- The test "redirects to / if user already has mfa enabled" asserts `/projects`,
  not `/` (`mfa_required_live_test.exs:20-29`); S05 follows the assertion.

## 7. Not migrating

| Item | Reason | Decided by | Date |
| ---- | ------ | ---------- | ---- |

## 8. Open questions

- Should an unenrolled owner or admin be blocked or warned before turning the
  requirement on (6.1)?
- Should `/mfa_required` name the project and return the member to it after
  enrolling (6.2)?

## Proposed flows

- none. Referenced: project-settings-security S08 (entry handoff),
  shared-project-scope S05 (gate), flow-digest-email S04 and
  flow-failure-alert-email S05 (withheld mail).

## Proposed shared

- none. Referenced: shared-project-scope, shared-authenticated-session.
