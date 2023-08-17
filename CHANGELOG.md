# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Log a warning in the console when the Editor/docs component is given latest
  [#958](https://github.com/OpenFn/Lightning/issues/958)

### Changed

### Fixed

## [v0.7.3] - 2023-08-15

### Added

### Changed

- Version control in project settings is now named Export your project
  [#1015](https://github.com/OpenFn/Lightning/issues/1015)

### Fixed

- Tooltip for credential select in Job Edit form is cut off
  [#972](https://github.com/OpenFn/Lightning/issues/972)
- Dataclip type and state assembly notice for creating new dataclip dropped
  during refactor [#975](https://github.com/OpenFn/Lightning/issues/975)

## [v0.7.2] - 2023-08-10

### Added

### Changed

- NodeJs security patch [1009](https://github.com/OpenFn/Lightning/pull/1009)

### Fixed

## [v0.7.1] - 2023-08-04

### Added

### Changed

### Fixed

- Fixed flickery icons on new workflow job creation.

## [v0.7.0] - 2023-08-04

### Added

- Project owners can require MFA for their users
  [892](https://github.com/OpenFn/Lightning/issues/892)

### Changed

- Moved to Elixir 1.15 and Erlang 26.0.2 to sort our an annoying ElixirLS issue
  that was slowing down our engineers.
- Update Debian base to use bookworm (Debian 12) for our Docker images
- Change new credential modal to take up less space on the screen
  [#931](https://github.com/OpenFn/Lightning/issues/931)
- Placeholder nodes are now purely handled client-side

### Fixed

- Fix issue creating a new credential from the Job editor where the new
  credential was not being set on the job.
  [#951](https://github.com/OpenFn/Lightning/issues/951)
- Fix issue where checking a credential type radio button shows as unchecked on
  first click. [#976](https://github.com/OpenFn/Lightning/issues/976)
- Return the pre-filled workflow names
  [#971](https://github.com/OpenFn/Lightning/issues/971)
- Fix version reporting and external reset_demo() call via
  Application.spec()[#1010](https://github.com/OpenFn/Lightning/issues/1010)
- Fixed issue where entering a placeholder name through the form would result an
  in unsaveable workflow
  [#1001](https://github.com/OpenFn/Lightning/issues/1001)
- Ensure the DownloadController checks for authentication and authorisation.

## [v0.7.0-pre5] - 2023-07-28

### Added

### Changed

- Unless otherwise specified, only show workorders with activity in last 14 days
  [#968](https://github.com/OpenFn/Lightning/issues/968)

### Fixed

## [v0.7.0-pre4] - 2023-07-27

### Added

### Changed

- Don't add cast fragments if the search_term is nil
  [#968](https://github.com/OpenFn/Lightning/issues/968)

### Fixed

## [v0.7.0-pre3] - 2023-07-26

### Added

### Changed

### Fixed

- Fixed an issue with newly created edges that prevented downstream jobs
  [977](https://github.com/OpenFn/Lightning/issues/977)

## [v0.7.0-pre2] - 2023-07-26

Note that this is a pre-release with a couple of known bugs that are tracked in
the Nodes and Edges [epic](https://github.com/OpenFn/Lightning/issues/793).

### Added

- Added ability for a user to enable MFA on their account; using 2FA apps like
  Authy, Google Authenticator etc
  [#890](https://github.com/OpenFn/Lightning/issues/890)
- Write/run sql script to convert triggers
  [#875](https://github.com/OpenFn/Lightning/issues/875)
- Export projects as `.yaml` via UI
  [#249](https://github.com/OpenFn/Lightning/issues/249)

### Changed

- In `v0.7.0` we change the underlying workflow building and execution
  infrastructure to align with a standard "nodes and edges" design for directed
  acyclic graphs (DAGs). Make sure to run the migrations!
  [793](<(https://github.com/OpenFn/Lightning/issues/793)>)

### Fixed

- Propagate url pushState/changes to Workflow Diagram selection
  [#944](https://github.com/OpenFn/Lightning/issues/944)
- Fix issue when deleting nodes from the workflow editor
  [#830](https://github.com/OpenFn/Lightning/issues/830)
- Fix issue when clicking a trigger on a new/unsaved workflow
  [#954](https://github.com/OpenFn/Lightning/issues/954)

## [0.6.7] - 2023-07-13

### Added

- Add feature to bulk rerun work orders from a specific step in their workflow;
  e.g., "rerun these 50 work orders, starting each at step 4."
  [#906](https://github.com/OpenFn/Lightning/pull/906)

### Changed

### Fixed

- Oban exception: "value too long" when log lines are longer than 255 chars
  [#929](https://github.com/OpenFn/Lightning/issues/929)

## [0.6.6] - 2023-06-30

### Added

- Add public API token to the demo site setup script
- Check and renew OAuth credentials when running a job
  [#646](https://github.com/OpenFn/Lightning/issues/646)

### Fixed

- Remove google sheets from adaptors list until supporting oauth flow
  [#792](https://github.com/OpenFn/Lightning/issues/792)
- Remove duplicate google sheets adaptor display on credential type picklist
  [#663](https://github.com/OpenFn/Lightning/issues/663)
- Fix demo setup script for calling from outside the app on Kubernetes
  deployments [#917](https://github.com/OpenFn/Lightning/issues/917)

## [0.6.5] - 2023-06-22

### Added

- Ability to rerun workorders from start by selecting one of more of them from
  the History page and clicking the "Rerun" button.
  [#659](https://github.com/OpenFn/Lightning/issues/659)

### Fixed

- Example runs for demo incorrect
  [#856](https://github.com/OpenFn/Lightning/issues/856)

## [0.6.3] - 2023-06-15

### Fixed

- Prevent saving null log lines to the database, fix issue with run display
  [#866](https://github.com/OpenFn/Lightning/issues/866)

## [0.6.2] - 2023-06-09

### Fixed

- Fixed viewer permissions for delete workflow

- Fixed bug with workflow cards
  [#859](https://github.com/OpenFn/Lightning/issues/859)

## [0.6.1] - 2023-06-08

### Fixed

- Fixed bug with run logs [#864](https://github.com/OpenFn/Lightning/issues/864)

- Correctly stagger demo runs to maintain order
  [#856](https://github.com/OpenFn/Lightning/issues/856)
- Remove `Timex` use from `SetupUtils` in favor of `DateTime` to fix issue when
  calling it in escript.

## [0.6.0]- 2023-04-12

### Added

- Create sample runs when generating sample workflow
  [#821](https://github.com/OpenFn/Lightning/issues/821)
- Added a provisioning api for creating and updating projects and their
  workflows See: [PROVISIONING.md](./PROVISIONING.md)
  [#641](https://github.com/OpenFn/Lightning/issues/641)
- Add ability for a `superuser` to schedule deletion, cancel deletion, and
  delete projects [#757](https://github.com/OpenFn/Lightning/issues/757)
- Add ability for a `project owner` to schedule deletion, cancel deletion, and
  delete projects [#746](https://github.com/OpenFn/Lightning/issues/746)

### Changed

- Ability to store run log lines as rows in a separate table
  [#514](https://github.com/OpenFn/Lightning/issues/514)

### Fixed

- Incorrect project digest queries
  [#768](https://github.com/OpenFn/Lightning/issues/768)]
- Fix issue when purging deleted users
  [#747](https://github.com/OpenFn/Lightning/issues/747)
- Generate a random name for Workflows when creating one via the UI.
  [#828](https://github.com/OpenFn/Lightning/issues/828)
- Handle error when deleting a job with runs.
  [#814](https://github.com/OpenFn/Lightning/issues/814)

## [0.5.2]

### Added

- Add `workflow_edges` table in preparation for new workflow editor
  implementation [#794](https://github.com/OpenFn/Lightning/issues/794)
- Stamped `credential_id` on run directly for easier auditing of the history
  interface. Admins can now see which credential was used to run a run.
  [#800](https://github.com/OpenFn/Lightning/issues/800)
- Better errors when using magic functions: "no magic yet" and "check
  credential" [#812](https://github.com/OpenFn/Lightning/issues/812)

### Changed

- The `delete-project` function now delete all associated activities
  [#759](https://github.com/OpenFn/Lightning/issues/759)

### Fixed

## [0.5.1] - 2023-04-12

### Added

- Added ability to create and revoke personal API tokens
  [#147](https://github.com/OpenFn/Lightning/issues/147)
- Add `last-used at` to API tokens
  [#722](https://github.com/OpenFn/Lightning/issues/722)
- Improved "save" for job builder; users can now press `Ctrl + S` or `⌘ + S` to
  save new or updated jobs job panel will _not_ close. (Click elsewhere in the
  canvas or click the "Close" button to close.)
  [#568](https://github.com/OpenFn/Lightning/issues/568)
- Add filtered search params to the history page URL
  [#660](https://github.com/OpenFn/Lightning/issues/660)

### Changed

- The secret scrubber now ignores booleans
  [690](https://github.com/OpenFn/Lightning/issues/690)

### Fixed

- The secret scrubber now properly handles integer secrets from credentials
  [690](https://github.com/OpenFn/Lightning/issues/690)
- Updated describe-package dependency, fixing sparkles in adaptor-docs
  [657](https://github.com/OpenFn/Lightning/issues/657)
- Clicks on the workflow canvas were not lining up with the nodes users clicked
  on; they are now [733](https://github.com/OpenFn/Lightning/issues/733)
- Job panel behaves better when collapsed
  [774](https://github.com/OpenFn/Lightning/issues/774)

## [0.5.0] - 2023-04-03

### Added

- Magic functions that fetch real metadata from connected systems via
  `credentials` and suggest completions in the job builder (e.g., pressing
  `control-space` when setting the `orgUnit` attribute for a DHIS2 create
  operation will pull the _actual_ list of orgUnits with human readable labels
  and fill in their orgUnit codes upon
  enter.)[670](https://github.com/OpenFn/Lightning/issues/670)
- A "metadata explorer" to browse actual system metadata for connected
  instances. [658](https://github.com/OpenFn/Lightning/issues/658)
- Resizable job builder panel for the main canvas/workflow view.
  [681](https://github.com/OpenFn/Lightning/issues/681)

### Changed

- Display timezone for cron schedule—it is always UTC.
  [#716](https://github.com/OpenFn/Lightning/issues/716)
- Instance administrators can now configure the interval between when a project
  owner or user requests deletion and when these records are purged from the
  database. It defaults to 7, but by providing a `PURGE_DELETED_AFTER_DAYS`
  environment variable the grace period can be altered. Note that setting this
  variable to `0` will make automatic purging _never_ occur but will still make
  "deleted" projects and users unavailable. This has been requested by certain
  organizations that must retain audit logs in a Lightning instance.
  [758](https://github.com/OpenFn/Lightning/issues/758)

### Fixed

- Locked CLI version to `@openfn/cli@0.0.35`.
  [#761](https://github.com/OpenFn/Lightning/issues/761)

## [0.4.8] - 2023-03-29

### Added

- Added a test harness for monitoring critical parts of the app using Telemetry
  [#654](https://github.com/OpenFn/Lightning/issues/654)

### Changed

- Set log level to `info` for runs. Most of the `debug` logging is useful for
  the CLI, but not for Lightning. In the future the log level will be
  configurable at instance > project > job level by the `superuser` and any
  project `admin`.
- Renamed license file so that automagic github icon is less confusing

### Fixed

- Broken links in failure alert email
  [#732](https://github.com/OpenFn/Lightning/issues/732)
- Registration Submission on app.openfn.org shows internal server error in
  browser [#686](https://github.com/OpenFn/Lightning/issues/686)
- Run the correct runtime install mix task in `Dockerfile-dev`
  [#541](https://github.com/OpenFn/Lightning/issues/541)
- Users not disabled when scheduled for deletion
  [#719](https://github.com/OpenFn/Lightning/issues/719)

## [0.4.6] - 2023-03-23

### Added

- Implement roles and permissions across entire app
  [#645](https://github.com/OpenFn/Lightning/issues/645)
- Fix webhook URL
  (`https://<<HOST_URL>>/i/cae544ab-03dc-4ccc-a09c-fb4edb255d7a`) for the
  OpenHIE demo workflow [448](https://github.com/OpenFn/Lightning/issues/448)
- Phoenix Storybook for improved component development
- Load test for webhook endpoint performance
  [#645](https://github.com/OpenFn/Lightning/issues/634)
- Notify user via email when they're added to a project
  [#306](https://github.com/OpenFn/Lightning/issues/306)
- Added notify user via email when their account is created
  [#307](https://github.com/OpenFn/Lightning/issues/307)

### Changed

- Improved errors when decoding encryption keys for use with Cloak.
  [#684](https://github.com/OpenFn/Lightning/issues/684)
- Allow users to run ANY job with a custom input.
  [#629](https://github.com/OpenFn/Lightning/issues/629)

### Fixed

- Ensure JSON schema form inputs are in the same order as they are written in
  the schema [#685](https://github.com/OpenFn/Lightning/issues/685)

## [0.4.4] - 2023-03-10

### Added

- Users can receive a digest email reporting on a specified project.
  [#638](https://github.com/OpenFn/Lightning/issues/638)
  [#585](https://github.com/OpenFn/Lightning/issues/585)

### Changed

### Fixed

## [0.4.3] - 2023-03-06

### Added

- Tooltips on Job Builder panel
  [#650](https://github.com/OpenFn/Lightning/issues/650)

### Changed

- Upgraded to Phoenix 1.7 (3945856)

### Fixed

- Issue with FailureAlerter configuration missing in `prod` mode.

## [0.4.2] - 2023-02-24

### Added

- A user can change their own email
  [#247](https://github.com/OpenFn/Lightning/issues/247)
- Added a `SCHEMAS_PATH` environment variable to override the default folder
  location for credential schemas
  [#604](https://github.com/OpenFn/Lightning/issues/604)
- Added the ability to configure Google Sheets credentials
  [#536](https://github.com/OpenFn/Lightning/issues/536)
- Function to import a project
  [#574](https://github.com/OpenFn/Lightning/issues/574)

### Changed

- Users cannot register if they have not selected the terms and conditions
  [#531](https://github.com/OpenFn/Lightning/issues/531)

### Fixed

- Jobs panel slow for first open after restart
  [#567](https://github.com/OpenFn/Lightning/issues/567)

## [0.4.0] - 2023-02-08

### Added

- Added a Delete job button in Inspector
- Filter workflow runs by text/value in run logs or input body
- Drop "configuration" key from Run output dataclips after completion
- Ability to 'rerun' a run from the Run list
- Attempts and Runs update themselves in the Runs list
- Configure a project and workflow for a new registering user
- Run a job with a custom input
- Added plausible analytics
- Allow user to click on Webhook Trigger Node to copy webhook URL on workflow
  diagram
- Allow any user to delete a credential that they own
- Create any credential through a form except for OAuth
- Refit all diagram nodes on browser and container resize
- Enable distributed Erlang, allowing any number of redundant Lightning nodes to
  communicate with each other.
- Users can set up realtime alerts for a project

### Changed

- Better code-assist and intelliense in the Job Editor
- Updated @openfn/workflow-diagram to 0.4.0
- Make plus button part of job nodes in Workflow Diagram
- Updated @openfn/adaptor-docs to 0.0.5
- Updated @openfn/describe-package to 0.0.10
- Create an follow a manual Run from the Job Inspector
- View all workflows in a project on the workflows index page
- Move @openfn/workflow-diagram into the application, the NPM module is now
  deprecated.
- Remove workflow name from first node
- Move the used parts of `@openfn/engine` into the application.
- [BREAKING CHANGE] Ported `mix openfn.install.runtime` into application, use
  `mix lightning.install_runtime`.
- [BREAKING CHANGE] Introduced `@openfn/cli` as the new runtime for Jobs
- Rename a workflow through the page heading
- Hide the dataclips tab for beta
- Make adaptor default to common@latest
- Remove jobs list page
- Better error handling in the docs panel
- Disable credential ownership transfer in dev and prod environments
- Add project settings page
- Change Workorder filters to apply to the aggregate state of the workorder and
  not the run directly
- Enable jobs by default
- Set log level to info
- Add Beta checkbox to register page
- User roles and permissions

### Fixed

- Don't consider disabled jobs when calculating subsequent runs
- Fixed overflow on Job Editor Tooltips
- Fixed auto-scroll when adding a new snippet in the Job Editor
- Fixed common operation typings in Job Editor

## [0.3.1] - 2022-11-22

### Fixed

- Fixed bug that attempted to execute HTML scripts in dataclips
- Fixed bug that prevented workorders from displaying in the order of their last
  run, descending.
- Remove alerts after set timeout or close

## [0.3.0] - 2022-11-21

### Added

- Add seed data for demo site
- Create adaptor credentials through a form
- Configure cron expressions through a form
- View runs grouped by workorders and attempts
- Run an existing Job with any dataclip uuid from the Job form

### Changed

- Redirect users to projects list page when they click on Admin Settings menu
- Move job, project, input and output Dataclips to Run table
- Reverse the relationship between Jobs and Triggers. Triggers now can exist on
  their own; setting the stage for branching and merging workflows
- Updated Elixir and frontend dependencies
- [BREAKING CHANGE] Pipeline now uses WorkOrders, previous data is not
  compatible.
- Runs, Dataclips and Attempts now all correctly use usec resolution timestamps.
- Upgraded LiveView to 0.18.0
- Upgraded Elixir to 1.14.1 and OTP 25
- Workflow Job editor now behaves like a panel
- Split JobLive.InspectorFormComponent into different plug-able subcomponents
- Ensure new jobs with cron triggers receive a default frequency
- Webhooks are now referenced by the trigger id instead of job id.
- Filter runs by status
- Filter runs by workflow
- Filter runs by date
- View a job run from the runs history
- View latest matching inputs to run a job with

## [0.2.0] - 2022-09-12

### Changed

- [BREAKING CHANGE] Add `Workflow` model, Jobs now belong to a Workflow This is
  a breaking change to the schema.
- Use Node.js 18, soon to be in LTS.
- Visualize success/fail triggers in workflow diagram.
- Move WorkflowDiagram related actions from DashboardLive into WorkflowLive
- Move WorkflowDiagram component into liveview, so that we can subscribe to
  channels (i.e. updating of the diagram when someone changes something).
- Integrate `@openfn/workflow-diagram@0.0.8` and use the new Store interface for
  updating it.
- Remove `component_mounted` event from WorkflowDiagram hook, using a
  MutationObserver and a Base64 encoded JSON payload.
- Fixed an issue where the compiler component would try and load a 'nothing
  adaptor', added a condition to check an adaptor is actually selected.
- Removed previous Workflow CTE queries, replaced by the introduction of the
  Workflow model, see
  (https://github.com/OpenFn/Lightning/blob/53da6883483e7d8d078783f348da327d1dd72d20/lib/lightning/workflows.ex#L111-L119).

## [0.1.13] - 2022-08-29

### Added

- Allow administrators to configure OIDC providers for authentication (note that
  this is just for authenticating, not yet for creating new accounts via OIDC)
- Add Monaco editor to the step/job panel
- Allow users to delete their own accounts. Schedule their user and credentials
  data for deletion when they do.
- Allow superusers to delete a user account. Schedule the user's credentials and
  user data for deletion when they do.
- If a user is scheduled for deletion, disable their account and prevent them
  from logging in.
- The 'User profile' and 'Credentials' page now have a sidebar menu

### Changed

- Project users now have one of the following roles: viewer, editor, admin,
  owner
- Users only have the following roles: user, superuser

## [0.1.12] - 2022-08-15

### Added

- Transfer credential ownership to another user.
- Create credentials via a form interface\*
- Show "projects with access" in credentials list view.
- Show job in runs list and run view.
- Added roles and permissions to workflows and history page
  [#645](https://github.com/OpenFn/Lightning/issues/645)

\*The form is defined by a JSON schema provided by an adaptor, in most cases:
e.g., `language-dhis2` provides a single schema which defines the required
attributes for `state.configuration`, while `language-common` provides multiple
credential schemas like "oauth" or "basic auth" which define attributes for
`state.configuration` and which might be used by lots of different jobs.)

### Fixed

- User menu (top right) appears on top of all other components.
- User profile screen integrated with the rest of the liveview app.

## [0.1.11] - 2022-08-05

### Fixed

- Fixed logging in Runner when `:debug` log level used; note that this caused
  crashes in Oban

## [0.1.10] - 2022-08-05

### Added

- Credential auditing
- Build/version information display for easier debugging

### Fixed

- Fixed a bug that enqueued cron-triggered jobs even when they were disabled

## [0.1.9] - 2022-07-27

### Added

- Navigate to user profile or credentials page and log out through the user icon
  dropdown
- Create and edit dataclips
- Add a production tag to credentials
- View a dropdown of operations and their description for the language-common
  `v2.0.0-rc2` adaptor (this pattern to be rolled out across adaptors)

### Changed

- Navigate between projects through a project picker on the navbar

### Fixed

- Run Lightning with docker

### Security

- Sensitive credential values are scrubbed from run logs
- All credentials are encrypted at REST

## [0.1.7] - 2022-06-24

### Added

- Run a job with a cron trigger
- Queue jobs via Oban/Postgres
- Edit jobs via the workflow canvas

## [0.1.6] - 2022-06-07

### Added

- Register, log in and log out of an account
- Allow superusers and admin users to create projects
- Allow admin users to create or disable a user’s account
- Allow superusers for local deployments to create users and give them access to
  project spaces

- Create and edit a job with a webhook, flow/fail or cron trigger
- Create and edit credentials for a job
- Copy a job's webhook URL
- View all workflows in a project visually
- Deploy lightning locally with Docker

- Enable a job to automatically process incoming requests
- Run a job with a webhook or flow/fail trigger
- View job runs along with their logs, exit code, start and end time
- View data clips that have initiated job runs (http requests for webhooks, run
  results)

### Changed

-

### Removed

-
