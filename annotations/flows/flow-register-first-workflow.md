---
id: flow-register-first-workflow
type: flow
title: Sign up and land on a first workflow
status: not-started
owner:

trigger:
  entry: auth-register
  exit: workflow-editor-new
  surfaces:
    - auth-register                          # GET/POST /users/register (router.ex:178-179)
    - controller:user-registration           # UserRegistrationController.create/2 (user_registration_controller.ex:13-50)
    - email:confirmation                     # welcome "Confirm your OpenFn account", sent in the same request (accounts.ex:579-589; user_notifier.ex:90-102); handed off to flow-resend-account-confirmation
    - pubsub:users:all                       # %UserRegistered{} (accounts.ex:585; accounts/events.ex:13-18); no subscriber in lib/
    - pubsub:projects_events:all             # %ProjectCreated{} for the starter project (projects.ex:573; projects/events.ex:81-86); no subscriber in lib/
    - workflow-editor-new                    # /projects/:id/w/new (router.ex:302; user_registration_controller.ex:45)
  reachable_when:
    - self-signup is on, otherwise the entry is a plain-text 404 (auth-register S11; router.ex:31-36)
    - the visitor is signed out (router.ex:175-179; user_auth.ex:271-279)
    - init_project_for_new_user is on; without it the new user has no project and lands on /projects or a stored return path (user_registration_controller.ex:29, :40-49; auth-register S01)

inherits:
  - shared-authenticated-session     # the session this flow creates passes its gates on landing (user_auth.ex:288-311); its S06 deadline warning is the one missing here (6.1)
  - shared-project-scope             # the landing page's on_mount :project_scope (collaborate.ex:25) admits the new owner
  - shared-editor-session            # the landing page's channel join with action "new" (workflow_channel.ex:2214-2237)

url_params: []                       # the redirect target is built from the starter project's id (user_registration_controller.ex:45); nothing is read from the query string

config_variants:
  default: { allow_signup: false, init_project_for_new_user: false }                     # bootstrap.ex:379-385; no entry, flow unreachable
  signup-allowed: { lightning.allow_signup: true }                                       # ALLOW_SIGNUP; on its own lands on /projects, so this flow does not run (auth-register S01)
  init-project-for-new-user: { signup-allowed, lightning.init_project_for_new_user: true }   # INIT_PROJECT_FOR_NEW_USER, bootstrap.ex:383-385; every scenario is read under this one, as is user_registration_controller_test.exs:62-106
  init-project-email-verification: { init-project-for-new-user, lightning.require_email_verification: true }   # REQUIRE_EMAIL_VERIFICATION, bootstrap.ex:387-389; changes what the landing page warns about (S03, 6.1)

inventory:
  routes:
    - post /users/register  UserRegistrationController :create      # router.ex:179; owned by auth-register
    - live /projects/:project_id/w/new  WorkflowLive.Collaborate :new   # router.ex:302; owned by workflow-editor-new
  events: []                          # the hop between surfaces is a controller redirect, not a LiveView event
  js_hooks: []
  policies:
    - Lightning.Policies.ProjectUsers :create_workflow (collaborate.ex:35-42; project_users.ex:39-49); the owner row the flow creates satisfies it
  workers: []                         # nothing is queued; the email is sent inline (user_notifier.ex:49-60)
  api_endpoints: []
  emails:
    - email:confirmation              # welcome variant (user_notifier.ex:90-102)
  config:
    - :lightning, :init_project_for_new_user        # user_registration_controller.ex:29
    - :lightning, :default_retention_period         # starter project's history retention (setup_utils.ex:196-197; config.exs:219)
    - Lightning.Extensions project_hook adapter     # ProjectHook.handle_create_project/1 (projects.ex:564; extensions/project_hook.ex:14-18; config.exs:47)
    - Lightning.Extensions account_hook adapter     # AccountHook.handle_register_user/1 (accounts.ex:579-583; config.exs:45)
  not_reachable_here:
    - SetupUtils.create_starter_project/3 with_workflow: true branch (setup_utils.ex:203-333); registration always passes false (user_registration_controller.ex:33-36), so the starter project has no workflow
    - Projects.schedule_project_addition_emails/2 (projects.ex:565-567); create_project/2 is called with schedule_email? false (setup_utils.ex:200)
    - UserAuth.redirect_with_return_to/2 on the project branch (user_registration_controller.ex:43-45); owned by flow-login-return-to and auth-register S01

related:
  - lib/lightning_web/controllers/user_registration_controller.ex
  - lib/lightning_web/controllers/user_auth.ex           # log_in_user/2 :28-31, new_session/2 :54-58, renew_session/1 :96-103
  - lib/lightning/accounts.ex                            # register_user/1 :579-589
  - lib/lightning/setup_utils.ex                         # create_starter_project/3 :191-201
  - lib/lightning/projects.ex                            # create_project/2 :562-575
  - lib/lightning/projects/project.ex                    # validate/1 :105-108, project_with_users_changeset/2 :282
  - lib/lightning/extensions/project_hook.ex
  - lib/lightning_web/live/workflow_live/collaborate.ex  # mount/3 :30-46
  - lib/lightning_web/components/layouts/live.html.heex  # flash :92-93
  - assets/js/collaborative-editor/CollaborativeEditor.tsx   # header hidden while new :315-316
  - test/lightning_web/controllers/user_registration_controller_test.exs
  - auth-register                    # S02 and S03 assert the start and the starter project; S14 asserts the email
  - workflow-editor-new              # S01 asserts what the landing screen offers; S04 onward own building the first workflow
flows:
  - flow-resend-account-confirmation # the welcome email this flow sends is confirmed through it
  - flow-login-return-to             # referenced; a stored return path is ignored on this flow's branch (6.2)
---

## 1. Purpose

On instances that offer self-signup with a starter project, a newcomer goes from no account to the
place where they build their first workflow in one submission: the account is created, they are
signed in, they are given a project they own, and they land on its new-workflow screen. Without
it, a new user on an open instance would arrive on an empty project list with nothing they are
allowed to build in, and would need an administrator to create a project before they could try
the product.

## 2. What it does

1. On instances that give new users a starter project, a visitor fills in the registration form.
2. Their account is created, a confirmation email is sent, and they're signed in.
3. They get a new, empty project of their own named after their first name (for example "amara-demo"), as its owner.
   - Two people with the same first name each get their own separate project with the same name.
4. They land on that project's new-workflow screen, with "User created successfully." and the choice to build from scratch or browse templates.
   - Where email verification is required, they can start building straight away, still unconfirmed.

**Straightforwardness: 3 of 5.** One form submission doing several things in a row is easy to follow, but a failure partway through leaves people in a confusing half-made state.

### Most surprising behaviours

- **(2)** Anyone whose first name has an accent, an apostrophe or non-Latin letters ("José", "O'Brien") gets an error page. Their account and confirmation email already exist but they have no project and aren't signed in, and trying again says the email "has already been taken". (6.1)
- **(3)** Where email verification is required, the first page gives no hint that they have 48 hours to confirm; the warning only appears once they save a workflow or go elsewhere. (6.1)
- **(3)** A page they were trying to reach before signing up is ignored but remembered, so it may pop up at their next login in the same browser, even after logging out. (6.2)
- **(4)** The confirmation email is sent before the project is made, so a slow mail server makes the Register button slow. (6.4)

## 3. Who can do what

No policy module gates registration; the gates are config and session state (`router.ex:31-36`,
`:175-179`; `user_auth.ex:271-279`). On landing, `:create_workflow` is checked against the role the
flow just granted (`collaborate.ex:35-42`; `project_users.ex:39-49`, `:167-172`).

| Action | Signed-out visitor | Signed-in user | Any visitor, signup off |
|--------|--------------------|----------------|-------------------------|
| Start the flow (submit registration) | init-project-for-new-user only | no, redirected to /projects | no, plain-text 404 |
| Receive a starter project as owner | yes | n/a | n/a |
| See the starter project's new-workflow landing screen | yes, as owner | n/a | n/a |

**Preconditions beyond role**
- The new user is always role `user`, never superuser (`user.ex:184-195`; auth-register S08).
- The starter project is a root project with no MFA requirement, so the scope gate admits an account that has not enrolled (`project.ex:94-103`; shared-project-scope S05 does not apply).
- require-email-verification: the account is unconfirmed but not locked out for 48 hours, so the landing page opens (`accounts.ex:1362-1368`; `user_auth.ex:305-306`).

## 4. What it touches

**Reads**
- Hop 1 (register): `users` by email for the uniqueness check (`user.ex:241-256`)
- Hop 2 (redirect): `project_users` joined to `projects` for the new user (`user_registration_controller.ex:41`; `user.ex:49`)
- Hop 3 (landing): `projects`, `project_users` in the scope gate and policy (`collaborate.ex:25`, `:35-42`)

**Writes**
- Hop 1: `users` insert, committed in its own transaction (`accounts.ex:579-583`; `extensions/account_hook.ex:9-16`)
- Hop 1: `user_tokens` insert, context `confirm` (`accounts.ex:1135-1142`)
- Hop 2: `projects` insert named `<downcased first name, spaces as hyphens>-demo`, env `main`, history retention from `default_retention_period`; `project_users` insert with role `owner`, in a second transaction (`user_registration_controller.ex:28-37`; `setup_utils.ex:191-201`; `projects.ex:562-575`; `project.ex:94-103`)
- Hop 2: `user_tokens` insert, context `session`; session renewed and cleared except `user_return_to`, then `user_token` set (`user_auth.ex:28-31`, `:54-58`, `:96-103`)
- Hop 3: none until the user picks a starting point (owned by workflow-editor-new)

**Immediate side effects**
- Hop 1: PubSub `users:all` `%UserRegistered{}` (`accounts.ex:585`; `accounts/events.ex:13-18`)
- Hop 1: email `email:confirmation`, welcome variant "Confirm your OpenFn account", sent synchronously, result discarded (`accounts.ex:586`, `:1161-1175`; `user_notifier.ex:90-102`); Hammer bucket `confirmation_request::<user id>` incremented (`accounts.ex:758-767`)
- Hop 2: PubSub `projects_events:all` `%ProjectCreated{}` (`projects.ex:573`; `projects/events.ex:81-86`); no project-addition email (`setup_utils.ex:200`; `projects.ex:565-567`)
- Hop 2: flash "User created successfully." and redirect to `/projects/<id>/w/new` (`user_registration_controller.ex:19`, `:45`)
- Hop 3: the flash renders in the live layout (`layouts/live.html.heex:92-93`)
- No audit event at any hop

**Deferred side effects**
- require-email-verification: 48 hours after sign-up an unconfirmed account is locked out (`accounts.ex:1362-1368`; shared-authenticated-session S04)

**External, non-transactional effects**
- The confirmation email, sent after the user row has committed and before the starter project is created (`accounts.ex:579-589`; `user_registration_controller.ex:14-16`). Neither the email nor the user row is undone if project creation fails (6.1).

**Depends on config**
- `init_project_for_new_user`: whether this flow runs at all (`user_registration_controller.ex:29`)
- `default_retention_period`: the starter project's history retention (`setup_utils.ex:196-197`)
- `require_email_verification`: whether the landing page should warn about the deadline (S03, 6.1)
- `project_hook` and `account_hook` extension adapters (`config.exs:45`, `:47`)

**Product limits**
- none beyond those owned by auth-register (password and name lengths) and workflow-editor-new

## 5. Scenarios

```gherkin
Feature: Sign up and land on a first workflow
  In order to try building a workflow as soon as I have an account
  As someone signing up on an instance that gives new users a starter project
  I want registration to leave me signed in, in a project I own, on the new-workflow screen

  @S01 @pending @variant:init-project-for-new-user
  Scenario: Registering lands me on my starter project's new-workflow screen
    # Value: a newcomer goes from no account to building a first workflow without waiting on an administrator.
    Given new users get a starter project
    And I am not logged in
    And "amara@example.org" has no account
    When I register as "Amara" "Okafor" with email "amara@example.org"
    Then I am logged in as "amara@example.org"
    And I am the owner of a new project "amara-demo"
    And I am on "/projects/<amara-demo id>/w/new"
    And I see "User created successfully."
    And I see "Where would you like to start today?"
    And I see a "Build from scratch" card and a "Browse templates" card
    And the flow "flow-resend-account-confirmation" has started for "amara@example.org"
    # user_registration_controller.ex:13-21, :28-37, :40-45; setup_utils.ex:191-201; projects.ex:562-575
    # user_auth.ex:28-31, :54-58; collaborate.ex:30-46; project_users.ex:39-49, :167-172; layouts/live.html.heex:92-93
    # LandingScreen.tsx:59-166 (workflow-editor-new S01); accounts.ex:586; user_notifier.ex:90-102
    # user_registration_controller_test.exs:62-106 follows the redirect with get("/") and asserts the project, not the landing URL or the landing screen

  @S02 @pending @variant:init-project-for-new-user
  Scenario: Two new users with the same first name each get their own project
    # Value: a starter project is never shared with a stranger who happens to have the same first name.
    Given new users get a starter project
    And "amara@example.org" registered as "Amara" and owns project "amara-demo"
    When "amara.b@example.org" registers as "Amara"
    Then "amara.b@example.org" lands on the new-workflow screen of a different project, also named "amara-demo"
    And "amara.b@example.org" is not a member of the first "amara-demo"
    And "amara@example.org" is not a member of the second
    # user_registration_controller.ex:30-36 (project_users holds only the new user); setup_utils.ex:191-201
    # project.ex:108, :122 (name uniqueness applies to sandbox children only, projects_unique_child_name)
    # no test registers two users with the same first name

  @S03 @pending @variant:init-project-email-verification
  Scenario: An unconfirmed new user can start building straight away
    # Value: email verification does not stand between a newcomer and their first workflow during the grace period.
    Given new users get a starter project
    And email verification is required
    When I register as "Amara"
    Then I am on the new-workflow screen of "amara-demo"
    And I can click "Build from scratch"
    And my account is still unconfirmed
    # accounts.ex:1362-1368 (no lockout inside 48 hours); user_auth.ex:305-306; collaborate.ex:30-46
    # user_registration_controller_test.exs:66-71 runs this variant but asserts neither the landing nor the warning
    # the landing screen does not show the 48-hour warning (6.1)
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The starter project is created with `{:ok, project} =` from `downcase(first_name) <> "-demo"` with only spaces replaced; any first name with a character outside `[a-z0-9-]` (an accent, an apostrophe, a non-Latin letter) fails the name format and raises MatchError. The user row is already committed, the confirmation email sent and `UserRegistered` broadcast, and the session cookie is never written. Owned as a row in auth-register 6.1; restated here because it breaks this flow's only hop between surfaces | `user_registration_controller.ex:14-16`, `:28-37`; `setup_utils.ex:191-201`; `project.ex:108`; `accounts.ex:579-589` | "José" or "O'Brien" gets a 500, is not signed in, has an unconfirmed account with no project, and on resubmitting is told the email "has already been taken" | fix |
| Under require-email-verification the landing page shows no confirmation deadline: Collaborate renders neither `LayoutComponents.header` (which carries the LiveView banner) nor the React `Header` while the workflow is new, and the React `EmailVerificationBanner` lives inside that `Header` | `collaborate.ex:236-276`; `layout_components.ex:259-277`; `CollaborativeEditor.tsx:315-316`; `Header.tsx:647` | a new user's first page gives no hint that they have 48 hours to confirm; the warning first appears after they save a workflow or open another page | fix |
| User creation and project creation are separate transactions with the email between them; a project creation failure of any kind (not only the name format, also a `project_hook` extension refusing) leaves a user with no project | `accounts.ex:579-589`; `projects.ex:562-575`; `user_registration_controller.ex:14-16` | the 500 above, then a half-onboarded account that lands on an empty /projects at its next login | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| On the project branch the stored `user_return_to` is neither honoured nor deleted; `renew_session` keeps it through sign-up and through a later logout, so it is applied at the next login in the same browser. The ignore half is already a decide row in flow-login-return-to 6.2 and auth-register 6.2 | `user_registration_controller.ex:43-45`; `user_auth.ex:63-70`, `:96-103`, `:114-130` | decide |
| The redirect goes to the first of `user.projects` with no ordering; if an `account_hook` extension also adds the user to a project, which one is chosen is undefined | `user_registration_controller.ex:41-45`; `user.ex:49` | decide |
| The starter project is empty: registration passes `with_workflow` false, so the landing screen is the only thing in it | `user_registration_controller.ex:33-36`; `setup_utils.ex:203` | preserve |
| Repeated inner spaces in the first name become repeated hyphens in the project name ("emory--h-demo") | `user_registration_controller.ex:30-31` | decide |
| The redirect is a full page load into the LiveView, not a live navigation, because it comes from a controller | `user_registration_controller.ex:45` | preserve |
| The landing URL carries no hint that this is a first visit; the landing screen is identical to the one an existing editor sees | `user_registration_controller.ex:45`; `collaborate.ex:30-46` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `[project \| _]` branch without init-project-for-new-user | `user_registration_controller.ex:43-45` | a brand-new user has no `project_users` unless the starter project was created or an `account_hook` extension adds one; already listed in auth-register 6.3 |
| `%UserRegistered{}` and `%ProjectCreated{}` broadcasts | `accounts.ex:585`; `projects.ex:573` | no subscriber in `lib/`; presumably for extensions |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| The confirmation email is sent synchronously before the starter project is created and the redirect issued, so a slow mail relay delays landing on the editor; owned by auth-register 6.4 | `accounts.ex:586`; `user_notifier.ex:57` | yes, a slow "Register" | decide |

### 6.5 Things seen but not understood

- Whether the "User created successfully." flash survives into the LiveView mount on `/w/new` and is shown above the landing screen was read from the live layout (`layouts/live.html.heex:92-93`), not run; the controller test only checks it on `/projects` (`user_registration_controller_test.exs:59`).
- `default_retention_period` defaults to nil (`config.exs:219`) and `history_retention_period` passes inclusion when nil (`project.ex:110`); what retention a nil value means for the starter project was not traced.
- flow-resend-account-confirmation's lead note says it now covers the first confirmation email, but its `not_reachable_here` still lists the welcome variant as outside it (`flow-resend-account-confirmation.md`, `not_reachable_here`); S01 asserts the handoff on the assumption that the lead note is current.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the starter project's name be derived so that any first name works, and should user and project creation share one transaction (6.1)? (owner: product)
- Should the landing page show the 48-hour confirmation warning to a new user under require-email-verification (6.1)? (owner: product)
- Should a pending return path win over the starter project, and should it be cleared either way (6.2)? (owner: product)
- Should a first-time landing differ from the ordinary new-workflow screen, for example by welcoming the user or opening a template (6.2)? (owner: product)

## Proposed flows

none. Referenced: flow-resend-account-confirmation (the welcome email, S01), flow-login-return-to (6.2).

## Proposed shared

none. Referenced: shared-authenticated-session, shared-project-scope, shared-editor-session.
