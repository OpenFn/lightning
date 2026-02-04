# Changelog

All notable changes to this project will be documented in this file.

- `Added` for new features.
- `Changed` for changes in existing functionality.
- `Deprecated` for soon-to-be removed features.
- `Removed` for now removed features.
- `Fixed` for any bug fixes.
- `Security` in case of vulnerabilities.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Sandbox compatibility with github sync(commit before & after merge)
  [#3957](https://github.com/OpenFn/lightning/issues/3957)
- Add PromEx plugin to track sandbox-related metrics for Prometheus including
  sandbox lifecycle events and workflow saves by project type
  [#4101](https://github.com/OpenFn/lightning/issues/4101)

### Changed

- Child nodes no longer switch position when an edge is selected
  [#4328](https://github.com/OpenFn/lightning/issues/4328)
- Copy parent project users when creating sandbox
  [#3761](https://github.com/OpenFn/lightning/issues/3761)
- Refactor bootstrap script for cross-platform support, splitting into modular
  files under `bin/bootstrap.d/` for macOS and Linux (Debian/Ubuntu)
  [#4377](https://github.com/OpenFn/lightning/pull/4377)
- Refactor AI Assistant Panel component by extracting focused hooks for diff
  management, URL sync, and workflow application logic
  [#4369](https://github.com/OpenFn/lightning/issues/4369)

### Fixed

- Fit screen when AI generates workflow & templates pick
  [#4345](https://github.com/OpenFn/lightning/issues/4345)
- AI-generated code diff now clears automatically when switching jobs in IDE
  [#4318](https://github.com/OpenFn/lightning/issues/4318)
- Update links in history page to use collab editor query params
  [#4371](https://github.com/OpenFn/lightning/issues/4371)
- Step events aren't appearing realtime on canvas
  [#4261](https://github.com/OpenFn/lightning/issues/4261)
- Send `suggest_code` flag to apollo for more robust suggestion parsing
  [#4373](https://github.com/OpenFn/lightning/issues/4373)

## [2.15.12] - 2026-01-29

### Fixed

- Legacy editor modal was covered up by side menu, now it sits above like before
  [PR#4358](https://github.com/OpenFn/lightning/pull/4358)

## [2.15.12-pre3] - 2026-01-28

- Refactor header component to use `:breadcrumbs` slot for flexible breadcrumb
  rendering [PR#4356](https://github.com/OpenFn/lightning/pull/4356)
- Fix version dropdown showing dot for workflows with cron/kafka triggers
  [#4352](https://github.com/OpenFn/lightning/issues/4352)

## [2.15.12-pre2] - 2026-01-28

### Added

- Provisioner updates version history of workflows on post
  [#4343](https://github.com/OpenFn/lightning/issues/4343)

### Changed

- Standardise copy button feedback across collaborative editor
  [#3578](https://github.com/OpenFn/lightning/issues/3578)
- Modified version hashing algorithm for CLI compatibility
  [#4346](https://github.com/OpenFn/lightning/issues/4346)

### Fixed

- Fix clicking nodes causing unwanted zoom in workflow diagram
  [#4327](https://github.com/OpenFn/lightning/issues/4327)

## [2.15.12-pre1] - 2026-01-21

### Added

- Add Unsaved Changes Indicator
  [#3682](https://github.com/OpenFn/lightning/issues/3682)
- Added sync/async mode controls to the trigger
  [#4321](https://github.com/OpenFn/lightning/issues/4321)

### Changed

- Validate WORKER_RUNS_PRIVATE_KEY is an RSA key at application startup
  [#4340](https://github.com/OpenFn/lightning/issues/4340)

## [2.15.12-pre] - 2026-01-19

### Added

- Add collapsible left sidebar with keyboard shortcut (Cmd/Ctrl+M) and
  command-palette style project picker (Cmd/Ctrl+Shift+P)
  [#4197](https://github.com/OpenFn/lightning/pull/4197)

### Changed

- Add configurable `CLAIM_WORK_MEM` environment variable (default: 32MB) to set
  PostgreSQL work_mem for claim query, eliminating temp file writes during
  window function sorting [#4331](https://github.com/OpenFn/lightning/pull/4331)
- Show version_history for workflows and not projects
  [#4329](https://github.com/OpenFn/lightning/issues/4329)

### Fixed

- Fix unable to save a workflow with a Kafka trigger in the collab editor
  [#4295](https://github.com/OpenFn/lightning/issues/4295)
- Credentials Scrubber uses too much memory. Introduce a limit on the number of
  sensitive values in a credential body via `MAX_CREDENTIAL_SENSITIVE_VALUES`
  [#4307](https://github.com/OpenFn/lightning/issues/4307)

## [2.15.11] - 2026-01-15

## [2.15.11-pre] - 2026-01-15

### Changed

- Render AI Assistant user messages as plain text instead of markdown to prevent
  incorrect code block formatting
  [#4288](https://github.com/OpenFn/lightning/issues/4288)
- Standardized "GitHub" brand capitalization throughout the UI
  [#4313](https://github.com/OpenFn/lightning/issues/4313)
- Optimized PromEx average claim duration query to use SQL aggregation instead
  of fetching rows into memory
  [#4317](https://github.com/OpenFn/lightning/pull/4317)
- Make new editor the default & warn for deprecation of legacy
  [#4111](https://github.com/OpenFn/lightning/issues/4111)

### Fixed

- Add clickable GitHub Actions link to collaborative editor's Save & Sync
  success toast [#4281](https://github.com/OpenFn/lightning/issues/4281)
- Fixed credential auto-selection when creating a new credential from the
  workflow editor's ConfigureAdaptorModal
  [#4287](https://github.com/OpenFn/lightning/issues/4287)
- Add index on `runs.finished_at` to fix UsageTracking ReportWorker timeouts
  [#4308](https://github.com/OpenFn/lightning/pull/4308)
- Fixed ConfigureAdaptorModal growing too tall when there are many credentials
  by adding scrollable credential lists with max-height
  [#4316](https://github.com/OpenFn/lightning/issues/4316)

## [2.15.10] - 2026-01-12

## [2.15.10-pre] - 2026-01-12

### Fixed

- Prevent returned workflow.yaml from appearing as a job code diff when opening
  job chat after workflow chat
  [#4296](https://github.com/OpenFn/lightning/issues/4296)

## [2.15.9] - 2026-01-09

### Fixed

- Fix credentials being removed from jobs after AI chat applies a generated
  workflow yaml [#4295](https://github.com/OpenFn/lightning/issues/4295)

## [2.15.8] - 2026-01-09

### Fixed

- Fixed AI Assistant button not being disabled when viewing pinned workflow
  versions in collaborative editor
  [#4292](https://github.com/OpenFn/lightning/issues/4292)

## [2.15.8-pre] - 2026-01-08

### Added

- AI Assistant can now preview and apply code suggestions directly to job code
  with Monaco diff editor
  [#3369](https://github.com/OpenFn/lightning/issues/3369)

### Changed

- Remove Environment input from Sandbox form
  [#3954](https://github.com/OpenFn/lightning/issues/3954)

## [2.15.7] - 2026-01-07

## [2.15.7-pre] - 2026-01-06

### Fixed

- Fixed bug where Oauth credentials and raw credentials couldn't be selected
  with the HTTP adaptor [#4284](https://github.com/OpenFn/lightning/issues/4284)

## [2.15.6] - 2025-12-24

### Fixed

- Fixed Code button being disabled when viewing old workflow versions
  [#4279](https://github.com/OpenFn/lightning/issues/4279)

## [2.15.5] - 2025-12-23

### Fixed

- Fixed Empty/Custom/Existing tabs being unresponsive when dataclip selected in
  FullScreenIDE run panel
  [#4275](https://github.com/OpenFn/lightning/issues/4275)

## [2.15.4] - 2025-12-20

### Fixed

- Allow `command+k` keystroke for AI chat while focusing Monaco editor on IDE
  [#4273](https://github.com/OpenFn/lightning/issues/4273)
- Fixed bug where previous run steps would not be associated with jobs after
  using AI chat [#4271](https://github.com/OpenFn/lightning/issues/4271)

## [2.15.3] - 2025-12-19

## [2.15.3-pre] - 2025-12-19

### Fixed

- Update workflow concurrency error message
  [#4216](https://github.com/OpenFn/lightning/issues/4216)
- Ensure workflow created via templates are disabled
  [#4262](https://github.com/OpenFn/lightning/issues/4262)
- Restore "Create workflow" flow
  [#4266](https://github.com/OpenFn/lightning/issues/4266)
- Allow users to add collaborators with long email domains
  [#4185](https://github.com/OpenFn/lightning/issues/4185)

## [2.15.2] - 2025-12-18

## [2.15.2-pre] - 2025-12-18

### Added

- Make AI chat sessions collaborative with real-time message sync
  [#4247](https://github.com/OpenFn/lightning/issues/4247)

### Changed

- Added `output_dataclip` to the default log exclusions if someone is running
  OpenFn in `:prod` mode. (Note that this also excludes `output_dataclip_id`.)

### Fixed

- Fix retried runs showing incorrect workflow version in history
  [#4186](https://github.com/OpenFn/lightning/issues/4186)
- Log lines were getting appended to previous run in the IDE
  [#4255](https://github.com/OpenFn/lightning/issues/4255)
- Waiting for worker (etc.) was missing from new IDE
  [#4257](https://github.com/OpenFn/lightning/issues/4257)
- Fixed Argument Error on session Collaborative editor session termination
  [#4251](https://github.com/OpenFn/lightning/issues/4251)
- Fix Session crashes when workflow has `deleted_at` field
  [#4245](https://github.com/OpenFn/lightning/issues/4245)

## [2.15.1] - 2025-12-17

### Fixed

- Fix run panel override all panels
  [#4243](https://github.com/OpenFn/lightning/issues/4243)

## [2.15.0] - 2025-12-17

## [2.15.0-pre7] - 2025-12-17

### Changed

- Update wording of errors on the canvas
  [#4224](https://github.com/OpenFn/lightning/issues/4224)
- Add default Logger param scrubbing for prod environments
  [#4231](https://github.com/OpenFn/lightning/issues/4231)
- Extend toast notification slightly
  [#4233](https://github.com/OpenFn/lightning/issues/4233)

### Fixed

- Fix workflow settings panel blocking the active panel
  [#4237](https://github.com/OpenFn/lightning/issues/4237)
- Fix AI Assistant having write privileges in readonly mode
  [#4227](https://github.com/OpenFn/lightning/issues/4227)
- Remove template selection URL state persistence to fix race conditions during
  workflow creation [#4221](https://github.com/OpenFn/lightning/issues/4221)
- Allow null value for workflow positions in Zod types
  [#4229](https://github.com/OpenFn/lightning/issues/4229)
- Alias `AiAssistant.Limiter` to satisfy credo:
  [PR#4223](https://github.com/OpenFn/lightning/pull/4223)

## [2.15.0-pre6] - 2025-12-16

### Added

- Enforce github sync, workflow activation and concurrency limits in the collab
  editor [#4104](https://github.com/OpenFn/lightning/pull/4104)
  [#4105](https://github.com/OpenFn/lightning/pull/4105)
  [#4106](https://github.com/OpenFn/lightning/pull/4106)
- Enforce AI assistant limits in the collab editor
  [#4107](https://github.com/OpenFn/lightning/pull/4107)

### Fixed

- Fix unable to open run panel when workflow settings panel is open
  [#4207](https://github.com/OpenFn/lightning/issues/4207)
- Fix workflow settings icon not red for server validation errros
  [#4155](https://github.com/OpenFn/lightning/issues/4155)
- Fix duplicate job name error stuck even when updated
  [#4169](https://github.com/OpenFn/lightning/issues/4169)
- Fix credential errors shown when credentials aren't set
  [#4162](https://github.com/OpenFn/lightning/issues/4162)
- Fix vertical alignment on enable/disable switch
  [#4211](https://github.com/OpenFn/lightning/issues/4211)
- Fix run selection not persisting across page reload in collaborative editor
  [#4188](https://github.com/OpenFn/lightning/issues/4188)
- Fix error propagation on collab editor
  [#4069](https://github.com/OpenFn/lightning/issues/4069)
- "Try the new editor" wasn't persisting properly to user preferences
  [#4199](https://github.com/OpenFn/lightning/issues/4199)
- Make template preview read-only in collaborative editor until workflow is
  created [#4203](https://github.com/OpenFn/lightning/issues/4203)

## [2.15.0-pre5] - 2025-12-13 🎂 ❤️ Happy Birthday, Mom!

### Changed

- Improve version pinning behavior in collaborative editor
  [#4121](https://github.com/OpenFn/lightning/issues/4121)
- Unify disabled button states across collaborative editor for consistent
  styling and behaviour [#4179](https://github.com/OpenFn/lightning/issues/4179)

### Fixed

- Fix IDE crash when viewing jobs that don't exist in workflow version - now
  shows informative message with option to select another job or change versions
  [#4173](https://github.com/OpenFn/lightning/issues/4173)
- Fix issue where selected step wasn't synced with selected workflow job
  [#4189](https://github.com/OpenFn/lightning/issues/4189)
- Fix job updates not persisted after saving
  [#4154](https://github.com/OpenFn/lightning/issues/4154)
- Fix infinite loading when reopening workflow in collaborative editor due to
  delta updates not being merged with persisted state
  [#4164](https://github.com/OpenFn/lightning/issues/4164)
- Fix incorrect field access and version type in checkpoint creation that would
  crash after 500 document updates
  [#4176](https://github.com/OpenFn/lightning/issues/4176)
- Fix issue where users were not able to go to the latest versin of a workflow
  [#4149](https://github.com/OpenFn/lightning/issues/4149)
- Fix AI Assistant disclaimer not persisting after acceptance
  [#4158](https://github.com/OpenFn/lightning/issues/4158)
- Credential form now shows inline validation errors for JSON schema and raw
  body fields after field interaction
  [#4168](https://github.com/OpenFn/lightning/issues/4168)
- Fix saving workflow with same name as deleted workflow
  [#4165](https://github.com/OpenFn/lightning/pull/4165)
- Fix validation error states not changing after undo (Ctrl+Z) on Workflow
  Settings [#4182](https://github.com/OpenFn/lightning/issues/4182))
- Fix credential modal stacking issue in collaborative editor IDE
  [#4171](https://github.com/OpenFn/lightning/issues/4171)
- Fix adaptor picker Escape key returning to configure modal when opened
  directly [#4183](https://github.com/OpenFn/lightning/issues/4183)

## [2.15.0-pre4] - 2025-12-08

### Added

- Display collab editor promotion in the legacy editor
  [#4091](https://github.com/OpenFn/lightning/issues/4091)
- Template search and selection in collaborative workflow editor with AI-powered
  workflow generation for missing templates
  [#4081](https://github.com/OpenFn/lightning/issues/4081)
  [#4052](https://github.com/OpenFn/lightning/issues/4052)
- AI Assistant integration in collaborative workflow editor
  [#4042](https://github.com/OpenFn/lightning/pull/4042)

### Changed

- Standardize run buttons so they all behave predictably
  [#4129](https://github.com/OpenFn/lightning/issues/4129)
- Make collab editor available to everyone (not just experimental feature users)
  [#4091](https://github.com/OpenFn/lightning/issues/4091)

### Fixed

- Fix Run/Retry button flash and improve History button UX in collaborative
  editor [#4108](https://github.com/OpenFn/lightning/issues/4108)
- Fix new jobs are misplaced on the canvas in manual layout
  [#4118](https://github.com/OpenFn/lightning/issues/4118)
- Fix docs not working for latest version of adaptors in IDE
  [#4136](https://github.com/OpenFn/lightning/issues/4136)

## [2.15.0-pre3] - 2025-12-05

### Added

- Collab Editor: Respect limits when creating runs and retries
  [#4102](https://github.com/OpenFn/lightning/issues/4102)

### Fixed

- Selected run sometimes fails to highlight step in the collab editor
  [#4127](https://github.com/OpenFn/lightning/issues/4127)
- Run logs no longer disappear after browser refresh in IDE
  [#4079](https://github.com/OpenFn/lightning/issues/4079)
- Fix version chip [#4120](https://github.com/OpenFn/lightning/issues/4120)
- Fix OAuth credential creation crash in Collaborate view when returning from
  provider authorization
  [#4131](https://github.com/OpenFn/lightning/issues/4131)

## [2.15.0-pre2] - 2025-12-04

### Added

- User preference persistence for collaborative editor - users can now toggle
  between legacy and collaborative editors, and their choice is remembered
  across sessions with automatic redirect
  [#4091](https://github.com/OpenFn/lightning/issues/4091)
- Added mini history to the IDE as a state machine that provides the same
  experience that's available on the canvas
  [#4054](https://github.com/OpenFn/lightning/issues/4054)
  - **If no run chosen?** You can browse from history or create a new one.
  - **If run chosen?** You can view the details or deselect to start over.

### Changed

- Refactor URLStore to use Record with Immer for proper structural sharing,
  reducing unnecessary re-renders when unrelated URL params change
  [#4097](https://github.com/OpenFn/lightning/issues/4097)
- Show "Connect" button when no credential is selected for non-language-common
  steps [#4085](https://github.com/OpenFn/lightning/issues/4085)
- Show credential name (and full name and owner on hover) when a credential is
  selected [#4085](https://github.com/OpenFn/lightning/issues/4085)
- Allow owners to edit credentials from the adaptor picker
  [#4085](https://github.com/OpenFn/lightning/issues/4085)

### Fixed

- Fix version not switching when selecting a run from history panel
  [#4097](https://github.com/OpenFn/lightning/issues/4097)
- User menu dropdown no longer clips or causes horizontal scroll in side
  navigation [#4092](https://github.com/OpenFn/lightning/issues/4092)
- Improved version mismatch banner UX: made compact, dismissible, and
  repositioned to top-center; improved history panel collapse behavior to
  maintain run selection with visual run chip indicator
  [#4044](https://github.com/OpenFn/lightning/issues/4044)
- Settings panel now opens correctly when Run Panel is visible; also improved
  Run Panel to stay open and update context when switching between nodes
  [#4008](https://github.com/OpenFn/lightning/issues/4008)
- Fix collaborative cursors disappearing after switching workflow versions
  [#4066](https://github.com/OpenFn/lightning/issues/4066)
- Throttle cursor awareness updates to reduce server load
  [#4066](https://github.com/OpenFn/lightning/issues/4066)
- Loading workflow screen appears when disconnected from server
  [#3972](https://github.com/OpenFn/lightning/issues/3972)
- IDE shows job expresion of previously selected job
  [#4022](https://github.com/OpenFn/lightning/issues/4022)
- Fix save & run buttons disabled after new workflow save
  [#4084](https://github.com/OpenFn/lightning/issues/4084)
- Fix flickering of canvas and job editor
  [#4095](https://github.com/OpenFn/lightning/issues/4095)
- Run channel crashes when sending `run:updated` event
  [#4093](https://github.com/OpenFn/lightning/issues/4093)
- Fix Version mismatch modal appears on top of IDE
  [#4096](https://github.com/OpenFn/lightning/issues/4096)

## [2.15.0-pre1] - 2025-11-27

### Added

- Add workflow template publishing to collaborative editor
  [#3921](https://github.com/OpenFn/lightning/issues/3921)

### Changed

- Optimize dashboard stats queries with database aggregation
  [#4070](https://github.com/OpenFn/lightning/issues/4070)
- Add composite indexes on steps and runs for dashboard queries
  [#4070](https://github.com/OpenFn/lightning/issues/4070)
- Enable usage limit checks across the whole application
  [#PR4050](https://github.com/OpenFn/lightning/pull/4050)
- Make IDE heading separate from top menu
  [#4077](https://github.com/OpenFn/lightning/issues/4077)
- Update IDE workflow step selector (order by proximity to trigger)
  [#4048](https://github.com/OpenFn/lightning/issues/4048)

### Fixed

- Version dropdown now updates correctly for all users after workflow save
  [#3985](https://github.com/OpenFn/lightning/issues/3985)
  [#4024](https://github.com/OpenFn/lightning/issues/4024)
- Put close button in top right
  [PR#4037](https://github.com/OpenFn/lightning/pull/4037)
- Don't grey out in-progress runs
  [PR#4037](https://github.com/OpenFn/lightning/pull/4037)
- Explain why run panel is grey for edge-case when the workflow step selected
  not in the list of run steps
  [PR#4037](https://github.com/OpenFn/lightning/pull/4037)
- Fix history panel unable to close after selecting/deselecting run
  [#4027](https://github.com/OpenFn/lightning/issues/4027)
- Fix version chip (and sidebar scroll) when line breaks needed
  [PR#4047](https://github.com/OpenFn/lightning/pull/4047)
- Fix error validation for nodes/edges & show better error messages on save
  [PR#4061](https://github.com/OpenFn/lightning/pull/4061)
- Fix custom cron expressions getting overwritten & additional cron support
  [#4011](https://github.com/OpenFn/lightning/issues/4011)
- Fix monaco popups and tooltips getting cut off
  [PR#4072](https://github.com/OpenFn/lightning/pull/4072)
- Fix metadata/docs panel reopening when resizing adjacent panel
  [#4073](https://github.com/OpenFn/lightning/issues/4073)
- Fix logs panel not allowing scroll after being resized to minimum height
  [PR#4067](https://github.com/OpenFn/lightning/pull/4067)

## [2.15.0-pre] - 2025-11-20

### Added

- Show collaborators mouse pointers on the workflow canvas
  [#3810](https://github.com/OpenFn/lightning/issues/3810)

### Changed

- Always keep the Diagram mounted even when the IDE is present
  [#3981](https://github.com/OpenFn/lightning/issues/3981)
- Dropped react-hotkeys-hook for custom priority based key handler hook
  [#3981](https://github.com/OpenFn/lightning/issues/3981)
- Simplified IDE by only letting users see the "Create a New Manual Run Panel"
  when an existing Run isn't already loaded. Cleaned up the Run panel.
  [#4006](https://github.com/OpenFn/lightning/issues/4006)
- Consolidated RunStore functionality into HistoryStore in collaborative editor
  for improved state management and reduced complexity
- Default failure notifications for project users are now disabled to minimize
  email volume [#3517](https://github.com/OpenFn/lightning/issues/3517)
- Simpler "disabled" state for workflows, still show last mod
  [#3962](https://github.com/OpenFn/lightning/issues/3962)
- Move user profile to top left corner
  [#3997](https://github.com/OpenFn/lightning/issues/3997)
- Collapse breadcrumbs when there are more than 2 of them
  [#3997](https://github.com/OpenFn/lightning/issues/3997)

### Fixed

- Fix flickering of active collaborator icons between states(active, inactive,
  unavailable) [#3931](https://github.com/OpenFn/lightning/issues/3931)
- Restored footers to inspectors on the canvas while in read only mode
  [#4018](https://github.com/OpenFn/lightning/issues/4018)
- Fix vertical scrolling in workflow panels
  [#3979](https://github.com/OpenFn/lightning/issues/3979)
- Fix ghost edges blocking saves and breaking autolayout when deleting jobs in
  collaborative editor [#3983](https://github.com/OpenFn/lightning/issues/3983)
- Fix tooltip styling inconsistencies in collaborative editor
  [#3980](https://github.com/OpenFn/lightning/issues/3980)
- Fix beaker icon appearing active in classical editor
  [#3988](https://github.com/OpenFn/lightning/issues/3988)
- Fix ESC key closing IDE when pressed on adaptor modal
  [#3978](https://github.com/OpenFn/lightning/issues/3978)
- Fix run/save-and-run keystroke mapping for canvas & IDE
  [#3902](https://github.com/OpenFn/lightning/issues/3902) &
  [#3903](https://github.com/OpenFn/lightning/issues/3903)
- Monaco tooltips get cut off
  [#3900](https://github.com/OpenFn/lightning/issues/3900)

## [2.14.15-pre] - 2025-11-13

### Added

- Add missing adaptor and credential tooltips to the collab editor
  [#3919](https://github.com/OpenFn/lightning/issues/3919)
- Show server validation errors in the collab editor forms
  [#3783](https://github.com/OpenFn/lightning/issues/3783)
- Add advanced credential type picker in collaborative workflow editor allowing
  users to create OAuth, raw JSON, and keychain credentials directly from the
  workflow canvas [#3906](https://github.com/OpenFn/lightning/issues/3906)
- Enforce readonly state in collaborative editor forms for viewers and old
  snapshots [#3948](https://github.com/OpenFn/lightning/pull/3948)
- Collab Editor: Add Workflow YAML code viewer panel
  [#3646](https://github.com/OpenFn/lightning/issues/3646)
- Webhook authentication management in the collaborative editor
  [#3887](https://github.com/OpenFn/lightning/issues/3887)
- Mix task to merge project state files without database access
  [#3615](https://github.com/OpenFn/lightning/issues/3615)
- Support Undo/Redo commands in the collab editor
  [#3712](https://github.com/OpenFn/lightning/issues/3712)
- Added adaptor docs & metadata panel to IDE
  [#3857](https://github.com/OpenFn/lightning/issues/3857)
- Show Error indication on workflow settings button
  [#3632](https://github.com/OpenFn/lightning/issues/3632)

### Changed

- Merged CollaborateNew and Collaborate LiveViews into a single unified LiveView
  for improved maintainability and consistent modal behavior
  [#3942](https://github.com/OpenFn/lightning/pull/3942)

### Fixed

- 500 error when navigating from collaborative editor to full history page
  [#3941](https://github.com/OpenFn/lightning/pull/3941)
- Duplicate `isReadOnly` declaration in TriggerForm that was blocking asset
  builds [#3976](https://github.com/OpenFn/lightning/issues/3976)
- Run duration and status alignment drift in history view
  [#3945](https://github.com/OpenFn/lightning/pull/3945)
- Shared doc lookup in clustered environments now works across nodes instead of
  only searching locally
  [#3910](https://github.com/OpenFn/lightning/issues/3910)

## [2.14.14] - 2025-11-05

### Added

- Add the ability to search by dataclip name on the history page
  [#3486](https://github.com/OpenFn/lightning/issues/3486)

### Fixed

- Exception when cleaning up old persisted documents
  [#3932](https://github.com/OpenFn/lightning/issues/3932)
- Legacy canvas new job nodes no longer auto-populate with adaptor name
  [#3920](https://github.com/OpenFn/lightning/issues/3920)

## [2.14.14-pre2] - 2025-11-04

### Added

- Run/retry split button in collaborative editor allowing users to retry
  existing runs or create new work orders from both the ManualRunPanel and
  fullscreen IDE header [#3876](https://github.com/OpenFn/lightning/issues/3876)
- Keyboard shortcuts for run/retry actions - `Cmd+Enter` (or `Ctrl+Enter`)
  triggers run/retry, `Cmd+Shift+Enter` create new work order
  [#3861](https://github.com/OpenFn/lightning/issues/3861)

### Changed

- Updated styles on new IDE to match (nay, exceed!) those on the legacy IDE
  [#3894](https://github.com/OpenFn/lightning/issues/3894)
- Add save & sync split button to new canvas & IDE header
  [#3908](https://github.com/OpenFn/lightning/issues/3908)
- Show collaborators in the header of the new canvas & IDE
  [#3845](https://github.com/OpenFn/lightning/issues/3845)

### Fixed

- Channel error handling crash when error responses don't include expected
  structure [#3928](https://github.com/OpenFn/lightning/issues/3928)
- Dataclip body display timing out due to slow credentials query - optimised
  query to leverage indexes better using a self-join
  [#3924](https://github.com/OpenFn/lightning/issues/3924)
- Adaptor picker changes now sync immediately to Y.Doc instead of requiring
  manual save [#3904](https://github.com/OpenFn/lightning/issues/3904)
- Fixed Cmd+Enter creating duplicate work orders in workflow editor - both
  ManualRunPanel and WorkflowEditor keyboard handlers were firing simultaneously
  [#3876](https://github.com/OpenFn/lightning/issues/3876)
- Fixed GenServer crash when retrying from collaborative editor due to Y.Doc
  workflow data structure issues
  [#3876](https://github.com/OpenFn/lightning/issues/3876)
- Fixed run panel blocking node selection and causing screen flashes when
  switching between nodes
  [#3876](https://github.com/OpenFn/lightning/issues/3876)

## [2.14.14-pre1] - 2025-10-30

### Added

- Adaptor and credential configuration in canvas job inspector - users can now
  configure adaptor version and connect credentials directly from the canvas
  [#3834](https://github.com/OpenFn/lightning/issues/3834)
- Press `Control-E` (or `⌘+E`) to open the IDE when a job/step is selected
  [#3890](https://github.com/OpenFn/lightning/issues/3890)
- Drag-to-connect nodes on workflow canvas - users can now drag from the plus
  button on a node and drop it onto another node to create connections
  [#3825](https://github.com/OpenFn/lightning/issues/3825)
- Read-only indicator in collaborative editor header
  [#3627](https://github.com/OpenFn/lightning/issues/3627)
- Sync workflow concurrency and enable_job_logs settings in collaborative
  editor - allows users to configure max concurrency and console.log() usage
  with real-time collaborative editing support
  [#3798](https://github.com/OpenFn/lightning/issues/3798) and
  [#3799](https://github.com/OpenFn/lightning/issues/3799)
- Show validation error message when creating sandbox with duplicate name
  [#3776](https://github.com/OpenFn/lightning/issues/3776)
- Divergence warning when merging sandboxes - displays alert if target branch
  was modified after sandbox creation to prevent data loss
  [#3747](https://github.com/OpenFn/lightning/issues/3747)
- Sandbox indicator banners in workflow editor (inspector) to help indicate when
  working in a sandbox environment
  [#3413](https://github.com/OpenFn/lightning/issues/3413)
- Manual runs from the canvas and the IDE
  [#3827](https://github.com/openfn/lightning/issues/3827) and
  [$3634](https://github.com/openfn/lightning/issues/3634)
- View and switch versions
  [#3819](https://github.com/openfn/lightning/issues/3819)
- Run viewer panel in collaborative IDE with Run, Log, Input, and Output tabs
  [#3844](https://github.com/OpenFn/lightning/issues/3844)

### Changed

- Error messages in collaborative editor now include field names for validation
  errors (e.g., "Name: can't be blank")
  [#3843](https://github.com/OpenFn/lightning/issues/3843)
- Added error notifications when workflow reset fails in collaborative editor
  [#3843](https://github.com/OpenFn/lightning/issues/3843)
- Consolidated toast notification styling in collaborative editor for better
  maintainability [#3843](https://github.com/OpenFn/lightning/issues/3843)

### Fixed

- Prevent manual run panel from opening via keystroke if running isn't possible
  (permissions or snapshot)
- Default Next Input for Cron-Triggered Workflows
  [#3856](https://github.com/OpenFn/lightning/issues/3856)
- Error toasts not appearing when workflow save fails (validation errors,
  permission denied, etc.) in collaborative editor
  [#3843](https://github.com/OpenFn/lightning/issues/3843)
- Toast notification colors not displaying correctly due to CSS specificity
  issues [#3843](https://github.com/OpenFn/lightning/issues/3843)
- Canvas goes blank when adding nodes in collaborative workflow editor
  [#3848](https://github.com/OpenFn/lightning/issues/3848)
- Crash when switching from old to collaborative editor
  [#3865](https://github.com/OpenFn/lightning/issues/3865)
- Position errors when rendering nodes
  [#3866](https://github.com/OpenFn/lightning/issues/3866)
- Layout animation crashes when adding nodes
  [#3867](https://github.com/OpenFn/lightning/issues/3867)
- Fixed sandbox merge failing with StaleEntryError when parent workflow was
  modified after sandbox creation
  [#3765](https://github.com/OpenFn/lightning/issues/3765)
- Workflow is either decapitated or uneditable
  [#3842](https://github.com/OpenFn/lightning/issues/3842)
- User can navigate to React canvas from LiveView version
  [#3847](https://github.com/openfn/lightning/issues/3847)
- Fixed missing cron icon in trigger on new canvas
  [#3849](https://github.com/OpenFn/lightning/issues/3849)

## [2.14.13] - 2025-10-24

## [2.14.13-pre1] - 2025-10-24

### Added

- Ability to run a workflow from the new react canvas
  [#3634](https://github.com/OpenFn/lightning/issues/3634)

## [2.14.13-pre] - 2025-10-24

### Added

- Ability to delay webhook trigger replies until a workflow finishes; ⚠️ note
  that this is an experimental feature (API subject to change, only enabled via
  DB updates) [#PR3785](https://github.com/OpenFn/lightning/pull/3785)
- REST API for runs, work_orders, and log_lines to refresh GovStack compliance
  [#1656](https://github.com/OpenFn/lightning/issues/1656) &
  [PR#3786](https://github.com/OpenFn/lightning/pull/3786)
- Added full-screen IDE for job editing
  [#3708](https://github.com/OpenFn/lightning/issues/3708)
- Show collaborative editor toggle (beaker icon) when creating new workflows
  [#3797](https://github.com/OpenFn/lightning/pull/3797)
- Auto-format code on commit with git hooks
  [#3806](https://github.com/OpenFn/lightning/pull/3806)
- Escape key support for closing inspector panels in collaborative workflow
  editor, using react-hotkeys-hook for scoped keyboard shortcuts with modal
  priority [#3768](https://github.com/OpenFn/lightning/issues/3768)

### Changed

- Removed Cancel button from inspector panel footers (redundant with X button
  and Escape key) [#3768](https://github.com/OpenFn/lightning/issues/3768)
- Refactored inspector component architecture to use composition pattern with
  reusable layout shell and pure form components
  [#3768](https://github.com/OpenFn/lightning/issues/3768)
- Updated breadcrumb navigation to display parent project name before sandbox
  name [#3474](https://github.com/OpenFn/lightning/issues/3474)

### Fixed

- Fixed credential preservation during sandbox workflow merge - credentials are
  now correctly maintained when merging sandboxes back to parent projects
  [#3782](https://github.com/OpenFn/lightning/issues/3782)
- Backfilled `env` field for existing root projects to ensure environment chips
  display correctly in workflow editor and inspector
  [#3839](https://github.com/OpenFn/lightning/issues/3839)

## [2.14.12] - 2025-10-21

## [2.14.12-pre1] - 2025-10-21

### Fixed

- Ensure default positions when using the Workflow Assistant with manual
  positioning enabled [#3795](https://github.com/OpenFn/lightning/issues/3795)

## [2.14.12-pre] - 2025-10-21

### Added

- Editable EdgeInspector form in collaborative workflow editor with TanStack
  Form, enabling users to configure edge properties (label, condition type, JS
  expressions, enabled state) with auto-save and real-time collaborative editing
  [#3701](https://github.com/OpenFn/lightning/issues/3701)
- Delete nodes from Job panel in Collaborative Editor
  [#3702](https://github.com/OpenFn/lightning/issues/3702)
- Reintroduce the impeded project with hopefully better performance
  characteristics [#3542](https://github.com/OpenFn/lightning/issues/3542)

### Changed

- Tweaked the Sandbox color palette
- Detect and clean stale CMake caches in bootstrap script
  [PR#3762](https://github.com/OpenFn/lightning/pull/3762)
- Implement workflow settings form using tanstack form
  [#3643](https://github.com/OpenFn/lightning/issues/3643)
- [#3774](https://github.com/OpenFn/lightning/pull/3774)Adjusted padding of
  labels in the Workflow Diagram.

### Fixed

- Jobs in collaborative editor can now be saved without selecting a credential
  [#3760](https://github.com/OpenFn/lightning/issues/3760)
- Runtime permission checks in WorkflowChannel save/reset operations to prevent
  unauthorized edits when user roles change during active collaboration sessions
  [#3749](https://github.com/OpenFn/lightning/issues/3749)

## [2.14.11] - 2025-10-15

## [2.14.11-pre1] - 2025-10-15

### Added

- Create new workflow via YAML in the collaborative editor
  [#3700](https://github.com/OpenFn/lightning/issues/3700)
- E2E tests for edge validation in collaborative editor
  [#3724](https://github.com/OpenFn/lightning/issues/3724)
- Ensure that TOTP codes cannot be reused.
  [#3758](https://github.com/OpenFn/lightning/issues/3758)

### Changed

- Detect and clean stale CMake caches in bootstrap script
  [PR#3762](https://github.com/OpenFn/lightning/pull/3762)

### Fixed

- Credentials added to parent projects now automatically propagate to all
  descendant sandbox projects, ensuring sandboxes have access to parent
  credentials. Includes migration to backfill existing missing associations.
  [#3756](https://github.com/OpenFn/lightning/issues/3756)

## [2.14.11-pre] - 2025-10-14

### Added

- User interface for merging sandboxes
  [#3436](https://github.com/OpenFn/lightning/issues/3436)
- Credential environments user interface and runtime
  [#3598](https://github.com/OpenFn/lightning/issues/3598)
- Save button with validation and permissions in collaborative workflow editor
  [#3635](https://github.com/OpenFn/lightning/issues/3635)
- Workflow reset functionality in collaborative editor
  [#3635](https://github.com/OpenFn/lightning/issues/3635)
- Toast notifications and Redux DevTools integration for collaborative editor
  [#3635](https://github.com/OpenFn/lightning/issues/3635)
- E2E test infrastructure with Page Object Models for workflow testing
- E2E testing guidelines for Playwright
- Add project merging functionality
  [#3432](https://github.com/OpenFn/lightning/issues/3432)
- SessionContextStore for collaborative workflow editor to provide user,
  project, and config data to React components via Phoenix Channel
- E2E test infrastructure with Page Object Models for workflow editor testing
- E2E test for workflow step creation and configuration
- Force restart and AdaptorRegistry warming on E2E manager script

### Changed

- Delete oauth_tokens tables
  [#3608](https://github.com/OpenFn/lightning/issues/3608)
- Improved state management and store architecture in collaborative editor
  [#3635](https://github.com/OpenFn/lightning/issues/3635)
- Upgraded Tailwind CSS from 4.0.13 to 4.1.14

### Fixed

- Project merge now correctly preserves target project identity (name,
  description, env, color) instead of overwriting with source metadata
  [#3742](https://github.com/OpenFn/lightning/issues/3742)
- New workflows created in sandboxes now properly retain all jobs, triggers, and
  edges when merged into target projects (previously only workflow metadata was
  copied, resulting in empty workflows)
  [#3744](https://github.com/OpenFn/lightning/issues/3744)

### Released

## [2.14.10] - 2025-10-07

## [2.14.10-pre] - 2025-10-07

### Added

- Worker "presence" module to track connected workers (and their capacity)
  across the app. [#3725](https://github.com/OpenFn/lightning/pull/3725)
- SessionContextStore for collaborative workflow editor to provide user,
  project, and config data to React components via Phoenix Channel
  [#3624](https://github.com/OpenFn/lightning/issues/3624)

### Changed

- Limit sandbox creation
  [PR#3655](https://github.com/OpenFn/lightning/pull/3655)

## [v2.14.9] - 2025-10-03

## [v2.14.9-pre] - 2025-10-02

### Added

### Changed

- Removed unused functions for getting dataclip bodies from postgres as
  JSON/maps [#3653](https://github.com/OpenFn/lightning/issues/3653)
- Limit sandbox creation
  [PR#3655](https://github.com/OpenFn/lightning/pull/3655)

### Fixed

- Prevent the janitor trying to mark runs as lost that aren't actually lost
  [PR#3672](https://github.com/OpenFn/lightning/pull/3672)
- Fix canvas "lockup" after AI chat errors, prevent sending empty message to AI
  [3605](https://github.com/OpenFn/lightning/issues/3605)

## [v2.14.8] - 2025-10-01

## [v2.14.8-pre1] - 2025-10-01

### Fixed

- Send back `null` if a requested dataclip has been wiped
  [PR#3652](https://github.com/OpenFn/lightning/pull/3652)

## [v2.14.8-pre] - 2025-10-01

### Fixed

- Reduced
  [high server memory usage on dataclip body retrieval](https://github.com/OpenFn/lightning/issues/3641)
  by 97% [PR#3651](https://github.com/OpenFn/lightning/pull/3651)

## [v2.14.7] - 2025-09-30

### Changed

- Optimized map and join with `Enum.map_join/3`
  [`c112f3d`](https://github.com/OpenFn/lightning/commit/c112f3df29f8ab83b187f3695fdaf32c0837a016)

### Fixed

- Fixed tests for dataclip live viewer
  [#3648](https://github.com/OpenFn/lightning/issues/3648)

## [v2.14.7-pre] - 2025-09-30

### Added

- Add database changes for credentials environments support
  [#3597](https://github.com/OpenFn/lightning/issues/3597)
- REST API for Credential creation, deletion, list
  [#3583](https://github.com/OpenFn/lightning/issues/3583)

### Changed

- Bumped devDeps `ws-worker` version to `1.15.0` to better handle job
  compilation memory issues
  [#3613](https://github.com/OpenFn/lightning/pull/3613)

### Fixed

- Fix memory bloat on dataclip viewer in dataclip detail page
  [#3641](https://github.com/OpenFn/lightning/issues/3641)
- Ameliorate memory usage when scrubbing dataclips for security
  [#3641](https://github.com/OpenFn/lightning/issues/3641)
- Fixed bootstrap script compatibility for Intel Macs and older Bash versions
  (3.1+) [#3623](https://github.com/OpenFn/lightning/pull/3623)
- Fixed GDPR Compliance component
  [#3611](https://github.com/OpenFn/lightning/issues/3611)
- Fixed vertical alignment in breadcrumbs
  [#3612](https://github.com/OpenFn/lightning/issues/3612)
- Updated Project Digest to include count of work orders in an unsuccessful
  state [#3616](https://github.com/OpenFn/lightning/issues/3616)

## [v2.14.6] - 2025-09-30

## [v2.14.6-pre1] - 2025-09-26

### Changed

- Modify `Common.root_name` to display any map with a `:name` key

## [v2.14.6-pre] - 2025-09-25

### Added

- Sandbox Basic CRUD UI [#3412](https://github.com/OpenFn/lightning/issues/3412)
  [#3431](https://github.com/OpenFn/lightning/issues/3431)
- Generate workflow version on save
  [#3452](https://github.com/OpenFn/lightning/issues/3452)
- Add `bin/update-images` script for automated Dockerfile version management

### Changed

- Optimized queue query planner stability to prevent 60s+ spikes
  [#3564](https://github.com/OpenFn/lightning/issues/3564)
- Fix aarch64 (Apple Silicon) Dockerfile-dev build
  [PR#3589](https://github.com/OpenFn/lightning/pull/3589)

### Fixed

- Fix project deletion for projects with webhook auth methods
  [#3619](https://github.com/OpenFn/lightning/issues/3619),
  [#3523](https://github.com/OpenFn/lightning/issues/3523)
- Fix pagination bar rounding to match table corners
  [#3595](https://github.com/OpenFn/lightning/issues/3595)
- Restore export history button
  [#3594](https://github.com/OpenFn/lightning/issues/3594)
- Wrong timestamp information in mini-history for in-progress runs
  [#3579](https://github.com/OpenFn/lightning/pull/3579)

## [v2.14.5] - 2025-09-24

## [v2.14.5-pre1] - 2025-09-11

### Added

- Hide sandboxes from project lists and project picker
  [#3573](https://github.com/OpenFn/lightning/issues/3573)

### Changed

- Update deps

## [v2.14.5-pre] - 2025-09-11

### Added

- Experimental feature - Collaborative Editing
  [#3509](https://github.com/OpenFn/lightning/issues/3509)
- API for provisioning Sandboxes
  [#3430](https://github.com/OpenFn/lightning/issues/3430)
- Added DB support for sandboxes and workflow version provenance.
  [#3422](https://github.com/OpenFn/lightning/issues/3422)
- Retry webhook events on transient database connection errors
  [#3097](https://github.com/OpenFn/lightning/issues/3097)
- Allow users to retry followed runs from the job panel
  [#3502](https://github.com/OpenFn/lightning/issues/3502)

### Changed

- Make `:work_available` broadcast opt-out-able via ENV.
  [#3574](https://github.com/OpenFn/lightning/pull/3574)
- Enable X-Content-Type-Options header for static pages.
  [#3534](https://github.com/OpenFn/lightning/issues/3534)
- Refactor webhook auth methods modals
  [#1588](https://github.com/OpenFn/lightning/issues/1588)

### Fixed

- Tooltip gets stuck when switching pages
  [#3559](https://github.com/OpenFn/lightning/pull/3559)
- Current run dataclip stuck when switching nodes
  [#3560](https://github.com/OpenFn/lightning/pull/3560)

## [v2.14.4] - 2025-09-09

### Fixed

- Fix Workflow AI Assistant apearing above inspector panel
  [#3567](https://github.com/OpenFn/lightning/issues/3567)

## [v2.14.3] - 2025-08-29

## [v2.14.3-pre1] - 2025-08-22

### Fixed

- Clean UI for errors with recovery from the errors
  [#3239](https://github.com/OpenFn/lightning/issues/3239)

## [v2.14.3-pre] - 2025-08-21

### Added

- Visualizing runs on the workflow editor canvas
  [#3387](https://github.com/OpenFn/lightning/issues/3387)
- Add test gauge metric that can be used to set arbitrary values for the
  purposes of triggering behaviour in metric consumers.
  [3510](https://github.com/OpenFn/lightning/issues/3510)
- Add test gauge metric that can be used to set arbitrary values for the
  purposes of triggering behaviour in metric consumers.
  [#3510](https://github.com/OpenFn/lightning/issues/3510)
- Possibly temporary plumbing to allow the use of libcluster_postgres as an
  additional mechanism for discovering Erlang nodes.
  [#3482](https://github.com/OpenFn/lightning/issues/3482)
- Remove redundant 'preconnect' link
  [#3532](https://github.com/OpenFn/lightning/issues/3532)

### Fixed

- Fix cannot read properties of undefined (reading 'x') error on canvas
  [#3530](https://github.com/OpenFn/lightning/issues/3530)
- Hide Mini-History on new template page
  [#3531](https://github.com/OpenFn/lightning/pull/3531)

## [v2.14.2] - 2025-08-15

## [v2.14.2-pre] - 2025-08-15

### Fixed

- Fixed issue where adaptors icons didn't change on the canvas when in
  auto-layout mode [#3526](https://github.com/OpenFn/lightning/issues/3526)

## [v2.14.1] - 2025-08-14

### Changed

- Removed impeded project metric until performance improvements can be made.
  [#3519](https://github.com/OpenFn/lightning/issues/3519)

## [v2.14.1-pre2] - 2025-08-12

### Fixed

- Fix workflow diagram collapsing in on itself to become a neutron star
  [#3506](https://github.com/OpenFn/lightning/issues/3506)
- Fix Oban crash when Apollo times out
  [#3497](https://github.com/OpenFn/lightning/issues/3497)
- Fix PostgreSQL UTF-8 error when inserting log lines with null bytes
  [#3090](https://github.com/OpenFn/lightning/issues/3090)

## [v2.14.1-pre1] - 2025-08-07

### Fixed

- Restored historical migration (⚠️ if you ran migrations on `v2.14.1-pre` by
  editing your DB directly or dropping your DB first, you must undo those
  changes by hand before running this migration) and added a migration to change
  `:workflow_code` to `:code` on the AI Chat Messages table
  [3495](https://github.com/OpenFn/lightning/issues/3495)

## [v2.14.1-pre] - 2025-08-06

### Added

- Extended the AI Assistant to support editing existing workflows
  [#3247](https://github.com/OpenFn/lightning/issues/3247)
- Alert that workflows may break before letting users revoke access to a project
  for their credential [#537](https://github.com/OpenFn/lightning/issues/537)

### Changed

- Upgraded Elixir from 1.17 to 1.18
  [d35a6d1](https://github.com/OpenFn/lightning/commit/d35a6d1)

### Fixed

- Fix CTRL+S saving previously selected template when creating a workflow
  [#3442](https://github.com/OpenFn/lightning/issues/3442)

## [v2.14.0] - 2025-08-05

### Fixed

- Added "interactive" to checkbox disabled tooltip to allow user to click link,
  ensure permissions line up with admin or above.
  [PR-3473](https://github.com/OpenFn/lightning/pull/3473)
- Fixed table action menus
  [#3476](https://github.com/OpenFn/lightning/issues/3476)
- Fixed "⚠️ Production" icon size in credentials table
  [#3483](https://github.com/OpenFn/lightning/issues/3483)
- Fixed test on history page
  [3475](https://github.com/OpenFn/lightning/issues/3475)

## [v2.14.0-pre1] - 2025-08-04

### Added

- Added a retry button to the work order row itself
  [PR-3472](https://github.com/OpenFn/lightning/pull/3472)

### Fixed

- Fixed small table UI regression for history
  [PR-3472](https://github.com/OpenFn/lightning/pull/3472)

## [v2.14.0-pre] - 2025-08-01

### Added

- Allow users to name and preserve existing dataclips
  [#311](https://github.com/OpenFn/lightning/issues/311)

### Changed

- Click to copy all timestamps in UTC across the application
  [#1419](https://github.com/OpenFn/lightning/issues/1419)
- Display relative times and respect browser timezones
  [#1255](https://github.com/OpenFn/lightning/issues/1255)
- Sortable history table
  [PR-3356](https://github.com/OpenFn/lightning/pull/3356)
- Visible run durations on the history table
  [PR-3356](https://github.com/OpenFn/lightning/pull/3356)
- Easier expansion of work orders in the history table
  [PR-3356](https://github.com/OpenFn/lightning/pull/3356)

## [v2.13.7-pre1] 2025-08-01

### Added

- Keychain credentials allow variable authentication/secret selection based on a
  run's input dataclip [#3359](https://github.com/OpenFn/lightning/issues/3359)

## [v2.13.7-pre] 2025-07-31

### Fixed

- Prevent requests to webhook URLs from matching non-webhook triggers
  [#3453](https://github.com/OpenFn/lightning/issues/3453)
- Authorized users unable to change the workflow concurrency setting
  [#3459](https://github.com/OpenFn/lightning/issues/3459)

## [v2.13.6] - 2025-07-24

### Added

- Extended impeded project to take workflow concurrency into account.
  [#3408](https://github.com/OpenFn/lightning/issues/3408)

### Changed

- Upgrade Ecto from v3.11 to v3.13
  [#3448](https://github.com/OpenFn/lightning/pull/3448)

### Fixed

- Fixed bug that prevented HTTP credentials from loading, now allow JSON objects
  to be passed as credential form inputs for complex settings like custom TLS
  options [#3437](https://github.com/OpenFn/lightning/issues/3437)

## [v2.13.6-pre] 2025-07-18

### Changed

- Bump bcrypt_elixir from 3.2.1 to 3.3.2
  [#3264](https://github.com/OpenFn/lightning/issues/3264)
- Bump sobelow from 0.13.0 to 0.14.0
  [#3263](https://github.com/OpenFn/lightning/issues/3263)
- Bump jsonpatch from 1.0.2 to 2.2.2
  [#3262](https://github.com/OpenFn/lightning/issues/3262)
- Bump oban from 2.18.3 to 2.19.4
  [#3159](https://github.com/OpenFn/lightning/issues/3159)
- Bump eqrcode from 0.1.10 to 0.2.1
  [#3116](https://github.com/OpenFn/lightning/issues/3116)
- Remove unused test as well as puppeteer dependency.
  [#3404](https://github.com/OpenFn/lightning/issues/3404)

### Fixed

- Don't render credential modals inside table cells
  [#1588](https://github.com/OpenFn/lightning/issues/1588)
- Handling of CLI error messages when fetching metadata via an adaptor
  [#3367](https://github.com/OpenFn/lightning/issues/3367)
- Error messages in forms not appearing when LastPass enabled
  [#3402](https://github.com/OpenFn/lightning/issues/3402)

## [v2.13.5] 2025-07-11

## [v2.13.5-pre] 2025-07-11

### Added

- Allow users to see & _use_ the "next input" state that would be used by a cron
  trigger when inspecting and running cron-triggered jobs
  [3335](https://github.com/OpenFn/lightning/issues/3335)
- Enable Undo and Redo in the Workflow Editor
  [#3358](https://github.com/OpenFn/lightning/pull/3358)

### Changed

- Bump CLI to 1.13.1 [#3351](https://github.com/OpenFn/lightning/issues/3351)

### Fixed

- Isolate failed to refresh token errors from other oauth errros
  [#3332](https://github.com/OpenFn/lightning/issues/3332)

## [v2.13.4] - 2025-07-05

## [v2.13.4-pre1] - 2025-07-04

### Changed

- Standardize modal footers and paddings
  [#3277](https://github.com/OpenFn/lightning/issues/3277)

### Fixed

- Fix text content overflowing in credential modal
  [#3280](https://github.com/OpenFn/lightning/pull/3280)
- Fix tables UI broken [#3324](https://github.com/OpenFn/lightning/issues/3324)

## [v2.13.4-pre] - 2025-07-04

### Added

- New buttons to run a workflow directly from the canvas, both from the start of
  the workflow [#3290](https://github.com/OpenFn/lightning/issues/3290) and from
  an individual step [#3294](https://github.com/OpenFn/lightning/issues/3294)
- Sorting & filtering superuser interfaces for Projects, Project, and Users
  [#3354](https://github.com/OpenFn/lightning/pull/3354)

### Changed

- Dont send oauth token expiry errors to Sentry
  [#3334](https://github.com/OpenFn/lightning/issues/3334)
- Improve error message when credential fails during runs
  [#3332](https://github.com/OpenFn/lightning/issues/3332)

### Fixed

- Fix OAuth scope validation error caused by `offline_access`
  [#3363](https://github.com/OpenFn/lightning/issues/3363)
- Cannot send message in old ai chat sessions
  [#3347](https://github.com/OpenFn/lightning/issues/3347)
- Fixes brief flash of previously viewed diagram when switching workflows
  [#3352](https://github.com/OpenFn/lightning/pull/3352)
- Fixes import of workflow YML for a manual laid out workflow.
  [#3360](https://github.com/OpenFn/lightning/pull/3360)

## [v2.13.3] 2025-06-26

## [v2.13.3-pre1] 2025-06-26

### Fixed

- ⚠️️ **Security patch for cases when a single user creates multiple Oauth
  credentials for the same Oauth client.** This fix prevents credential token
  sharing for users with _multiple_ Oauth credentials linked to a single OpenFn
  username, a single Oauth Client, and the _same_ set of scopes. Previously,
  these credentials would be considered the unique (`user_id`, `client_id`,
  `scopes`) and only the _last_ issued token would be persisted. This fix binds
  oauth_tokens to credentials 1:1 and provides a number of enhancements for
  debugging and reauthorizing Oauth credentials.
  [#3326](https://github.com/OpenFn/lightning/issues/3326)

## [v2.13.3-pre]

### Added

- Give users the option to attach job code and logs to AI Assistant
  [#2935](https://github.com/OpenFn/lightning/issues/2935)
- Allow users to edit position of nodes in the workflow
  [#3123](https://github.com/OpenFn/lightning/issues/3123)
- Minimap for easier workflow navigation
  [#3125](https://github.com/OpenFn/lightning/issues/3125)
- Added icons to control layout in the workflow
  [PR #3242](https://github.com/OpenFn/lightning/pull/3242)

### Changed

- Update React Flow to version 12
  [PR #3242](https://github.com/OpenFn/lightning/pull/3242)
- Create nodes and edges with the same button in the workflow
  [#2175](https://github.com/OpenFn/lightning/issues/2175)

### Fixed

- AI Assistant fails to send job context in subsequent messages
  [#3329](https://github.com/OpenFn/lightning/issues/3329)
- Fix snapshot cleanup incorrectly deleting runs via cascade deletion
  [#3313](https://github.com/OpenFn/lightning/issues/3313)
- `Lightning.Demo.reset_demo()` was broken by an ordering issue between
  Credentials and Oauth tokens.

## [v2.13.2] - 2025-06-18

⚠️️ Please note that **this version fixes an issue that caused premature run
history deletion** when snapshots were cleaned. Certain additional runs related
to pre-existing work orders were being deleted before their retention period.
This bug was introduced in version `v2.12.3-pre` on May 29th. If you're tracking
`latest` you'd see this bug come out in `v2.13.0` on June 4th.

## [v2.13.2-pre] - 2025-06-18

### Added

- Show who started each run
  [#3309](https://github.com/OpenFn/lightning/issues/3309)

### Changed

### Fixed

- Stop cleanup of snapshots (was causing data loss)
- The application env `queue_result_retention_period` was previously pulling
  from a wrongly named `QUEUE_RESULT_RETENTION_PERIOD_SECONDS`; the calculation
  is actually done in minutes; we now set this env from
  `QUEUE_RESULT_RETENTION_PERIOD_MINUTES`
  [#3316](https://github.com/OpenFn/lightning/issues/3316)

## [v2.13.1] - 2025-06-12

## [v2.13.1-pre] - 2025-06-11

### Changed

- Report AI Assistant errors to Sentry
  [#3010](https://github.com/OpenFn/lightning/issues/3010)
- Do not validate edge js condition expression
  [#3028](https://github.com/OpenFn/lightning/issues/3028)

### Fixed

- Allow scrolling in the template grid
  [#3284](https://github.com/OpenFn/lightning/issues/3284)
- Search input in run history is cleared when you click on the filter buttons
  [#1951](https://github.com/OpenFn/lightning/issues/1951)
- Fix Inspector Input panel not showing current run's dataclip for older
  workflow runs [#3288](https://github.com/OpenFn/lightning/issues/3288)

## [v2.13.0] - 2025-06-04

## [v2.13.0-pre2] - 2025-06-04

### Fixed

- Only show credentials owned by current user in `/credentials` (not those
  shared with them also) [3273](https://github.com/OpenFn/lightning/issues/3273)
- Fix texts not getting wrapped in modals that are inside table rows
  [3274](https://github.com/OpenFn/lightning/issues/3274)

## [v2.13.0-pre1] - 2025-06-03

### Changed

- Removed heavy Arcade videos, replaced with time-aware, friendly greeting.
  [#3267](https://github.com/OpenFn/lightning/issues/3267)

### Fixed

- Don't display hidden secondary buttons
  [#3265](https://github.com/OpenFn/lightning/issues/3265)

## [v2.13.0-pre] - 2025-06-02

### Added

- Set timeout for Apollo client requests.
  [#3009](https://github.com/OpenFn/lightning/issues/3009)
- Generate workflows using AI
  [#3174](https://github.com/OpenFn/lightning/issues/3174)
- Enhance workflows templates UI
  [#3175](https://github.com/OpenFn/lightning/issues/3175)

### Changed

- Standardize sub-tabs (tabs inside tabs on Inspector)
  [#3261](https://github.com/OpenFn/lightning/pull/3261)
- No longer blocking the "Create new workflow" button based on _active_ workflow
  limits [#3251](https://github.com/OpenFn/lightning/pull/3251)

### Fixed

- Fix magic metadata [#3134](https://github.com/OpenFn/lightning/issues/3134)
- Padding Changes on Project Setup Page
  [#3257](https://github.com/OpenFn/lightning/issues/3257)

## [v2.12.3-pre] - 2025-05-29

### Added

- Added a custom metric to track projects that could benefit from additional
  worker pods. [#3189](https://github.com/OpenFn/lightning/issues/3189)
- Add a test metric that can be used to test external infrastructure (e.g.
  alerting) in a deployed Lightning instance.
  [#3229](https://github.com/OpenFn/lightning/issues/3229)
- Broadcast work-available to worker when runs are enqueued
  [#2934](https://github.com/OpenFn/lightning/issues/2934)

### Changed

- Update Elixir to 1.18.3 [#2748](https://github.com/OpenFn/lightning/pull/2748)
- Standardized table components across the application
  [#2905](https://github.com/OpenFn/lightning/issues/2905)
- Standardize buttons [#3093](https://github.com/OpenFn/lightning/issues/3093)
- Make the chunk size for deleting expired activty configurable via ENV
  [#3181](https://github.com/OpenFn/lightning/pull/3181)
- Reduce the cardinality of `lightning_run_lost_count`.
  [#3226](https://github.com/OpenFn/lightning/issues/3226)
- Improve manual run component
  [#3089](https://github.com/OpenFn/lightning/issues/3089)

### Fixed

- Delay purge user having project file(s)
  [#2919](https://github.com/OpenFn/lightning/issues/2919)
- Display all github repositories even if they're more than 30
  [#3206](https://github.com/OpenFn/lightning/issues/3206)
- Github repo names getting truncated
  [#3037](https://github.com/OpenFn/lightning/issues/3037)

## [v2.12.2] - 2025-05-01

### Changed

- Tweak language on webhook auth method modal and list action
  [#3166](https://github.com/OpenFn/lightning/pull/3166)
- Re-order nightly cron jobs to reduce acute stress on db
  [#3179](https://github.com/OpenFn/lightning/pull/3179)

### Fixed

- Fix save and sync not working in the workflow editor
  [#3177](https://github.com/OpenFn/lightning/issues/3177)

## [v2.12.1] - 2025-04-29

### Changed

- Sort logs in failure notification emails by timestamp, ascending
  [#2347](https://github.com/OpenFn/lightning/issues/2347)
- Rename webhook auth method button and title
  [#3165](https://github.com/OpenFn/lightning/issues/3165)

### Fixed

- Importer not updating canvas properly
  [#3156](https://github.com/OpenFn/lightning/issues/3156)
- Template name overwritten by workflow name when updating an existing template
  [#3157](https://github.com/OpenFn/lightning/issues/3157)
- Route not found after pressing Enter to create a workflow
  [#3142](https://github.com/OpenFn/lightning/issues/3142)
- Make Collections delete_all idempotent
  [#3143](https://github.com/OpenFn/lightning/issues/3143)
- Blank modal showing when you click to show webhook auth method password
  [#3154](https://github.com/OpenFn/lightning/issues/3154)

## [v2.12.0] - 2025-04-25

### Added

- Create workflows from base templates
  [#3018](https://github.com/OpenFn/lightning/issues/3018),
  [#3031](https://github.com/OpenFn/lightning/issues/3031)
  [#3080](https://github.com/OpenFn/lightning/issues/3080)
- Custom metrics to track lost runs
  [#3070](https://github.com/OpenFn/lightning/issues/3070)
- AI Assistant: add metadata column to chat sessions
  [#3054](https://github.com/OpenFn/lightning/issues/3054)
- Added a message to explain to the user why they're waiting for a run
  [#3131](https://github.com/OpenFn/lightning/issues/3131)
- Allow users to create workflows from base templates
  [#3110](https://github.com/OpenFn/lightning/issues/3110)
- Simplified adding credentials to projects
  [#3034](https://github.com/OpenFn/lightning/issues/3034)
- Enabled displaying full workflow name when hovering workflow name in the
  workflows list page [#2894](https://github.com/OpenFn/lightning/issues/2894)
- Enabled clickable rows in the workflows list page
  [#3047](https://github.com/OpenFn/lightning/issues/3047)
- Added sorting & filtering workflows
  [#3046](https://github.com/OpenFn/lightning/issues/3046)
- Add helper function to create latest snapshot
  [#3099](https://github.com/OpenFn/lightning/issues/3099)
- Restart the credential setup from selecting the credential type
  [#2284](https://github.com/OpenFn/lightning/issues/2284)
- Enable Support User and adds audit trail for MFA.
  [#3072](https://github.com/OpenFn/lightning/issues/3072)
- Allow users to view and copy their workflow as a code
  [#3016](https://github.com/OpenFn/lightning/issues/3016)
- Allow users to create workflow via YAML import
  [#3013](https://github.com/OpenFn/lightning/issues/3013)
- Make provision for the inclusion of 'external' metrics.
  [#3096](https://github.com/OpenFn/lightning/issues/3096)
- Introduce 'seeding' of PromEx event metrics
  [#3096](https://github.com/OpenFn/lightning/issues/3096)
- When claiming a run, a worker name can optionally be provided to the adaptor
  that is responsible for claiming runs.
  [#3079](https://github.com/OpenFn/lightning/issues/3079)
- Persist worker name provided by worker when claiming a run. NOTE: This
  requires version `1.13.2` of the worker.
  [#3079](https://github.com/OpenFn/lightning/issues/3079)

### Changed

- Add project name to failure email subject
  [#2974](https://github.com/OpenFn/lightning/issues/2974)
- Large refactor of the inspector and React components
  [#3043](https://github.com/OpenFn/lightning/pull/3043)
- The AI Assistant now has access to docs.openfn.org to better inform its
  responses [apollo#209](https://github.com/OpenFn/apollo/pull/209)
- Adjusted flash messages
- Updated dependencies [#3086](https://github.com/OpenFn/lightning/pull/3086):
  - `phoenix` from 1.7.20 to 1.7.21
  - `phoenix_live_view` from 1.0.5 to 1.0.9
  - `petal_components` from 2.9.0 to 3.0.1
- Move new workflow form into the edit page
  [#3083](https://github.com/OpenFn/lightning/issues/3083)
- Added logos & case-insensitive sorting of credential types
  [#3107](https://github.com/OpenFn/lightning/pull/3107)
- Added a "BETA" label to the Kafka trigger type
  [#3098](https://github.com/OpenFn/lightning/pull/3098)

## [v2.11.2] - 2025-04-10

### Added

- Remove Credentials for Collaborators Removed from a Project
  [#2942](https://github.com/OpenFn/lightning/issues/2942)
- Enable Credential Transfer In Projects Credentials Table
  [#2978](https://github.com/OpenFn/lightning/issues/2978)
- Allow possibility to inject components for implementing GDPR compliance
  [PR#3056](https://github.com/OpenFn/lightning/pull/3056)
- Change edge color in the workflow when there is an error
  [#2999](https://github.com/OpenFn/lightning/issues/2999)

### Changed

- Stagger cleanup crons in the hopes that it reduces the imapct on the database.
  [#3061](https://github.com/OpenFn/lightning/issues/3061)
- Default to latest specific version instead of @latest when selecting adaptors
  [#2843](https://github.com/OpenFn/lightning/issues/2843)
- Remove OpenTelemetry suport as it is not currently in use
  [#3081](https://github.com/OpenFn/lightning/issues/3081)

## [v2.11.1] - 2025-04-03

### Added

- Fix putting project credentials on a new credential
  [#2993](https://github.com/OpenFn/lightning/issues/2993)
- Allow users to book for demo sessions
  [PR#3035](https://github.com/OpenFn/lightning/pull/3035)
- Allow workflow and project concurrency progress windows
  [#2995](https://github.com/OpenFn/lightning/issues/2995)

### Changed

- Update flash message to contain link to github actions after save & sync
  [#2989](https://github.com/OpenFn/lightning/issues/2989)
- Added alphabetical sort to credential and Oauth2 client lists.
  [#2994](https://github.com/OpenFn/lightning/issues/2994)
- Update Phoenix LiveView to 1.0.5, Petal Components to 2.9.0 and TailwindCSS to
  v4 [#3033](https://github.com/OpenFn/lightning/pull/3033)

### Fixed

- Fixes to some issues with code-complete in the editor
  [#3052](https://github.com/OpenFn/lightning/pull/3052)

## [v2.11.0] - 2025-03-19

### Added

- Update Collections admin UI storage counter after deleting all
  [#2986](https://github.com/OpenFn/lightning/issues/2986)
- Refactor OAuth credentials to reuse existing refresh tokens for same scopes
  [#2908](https://github.com/OpenFn/lightning/issues/2908) \
  ⚠️️ Please note that you will need to migrate your existing OAuth credentials.
  To do that run the following command:
  `mix run priv/repo/migrate_oauth_credentials.exs` for local setup or
  `docker exec -it <lightning_container_name> /app/bin/lightning eval "Lightning.Credentials.OauthMigration.run()"`
  for production environments.

### Changed

- Changed the way Monaco workers are loaded, using ESM modules instead.
- Do not include `v` param in workflow links when it is latest
  [#2941](https://github.com/OpenFn/lightning/issues/2941)
- Use dropdown instead of modal for the log level filter
  [#2980](https://github.com/OpenFn/lightning/issues/2980)
- Upgrade esbuild to 0.25.0
  [#2962](https://github.com/OpenFn/lightning/issues/2962)

### Fixed

- Fix broken highlighter for selected step in the log viewer
  [#2980](https://github.com/OpenFn/lightning/issues/2980)
- Don't delete latest snapshot when deleting unused snaphots in workorders
  [#2996](https://github.com/OpenFn/lightning/issues/2996)
- Don't allow users to disable edges coming from a trigger
  [#3008](https://github.com/OpenFn/lightning/issues/3008)

## [v2.10.16] - 2025-02-28

### Added

- Disable jobs with non retriable steps
  [#2925](https://github.com/OpenFn/lightning/issues/2925)

### Fixed

- Fix toggle button not visually disabled
  [#2976](https://github.com/OpenFn/lightning/issues/2976)
- Dont clear dataclip input when user saves workflow
  [#2944](https://github.com/OpenFn/lightning/issues/2944)

## [v2.10.16-pre.0] - 2025-02-26

### Added

- Allow the billing app to schedule project deletion
  [#2972](https://github.com/OpenFn/lightning/issues/2972)
- Enable project level concurrency limit
  [#2906](https://github.com/OpenFn/lightning/issues/2906)
- Transfer credentials ownership to a project collaborator
  [#2820](https://github.com/OpenFn/lightning/issues/2820)
- Delete unused snapshots on workorders retention cleanup
  [#1832](https://github.com/OpenFn/lightning/issues/1832)
- Allow users to configure their preferred log levels
  [#2206](https://github.com/OpenFn/lightning/issues/2206)
- Allow project admins and owners to disable `console.log()` in jobs
  [#2205](https://github.com/OpenFn/lightning/issues/2205)

### Changed

- Bumped CI NodeJS and Postgres versions to 22.12.0 and 17.3 respectively
  [#2938](https://github.com/OpenFn/lightning/pull/2938)

### Fixed

- Creating a dataclip fails on indexing when it's too large
  [#2682](https://github.com/OpenFn/lightning/issues/2682)

## [v2.10.15] - 2025-02-14

### Changed

- Allow empty/blank log lines from the worker/jobs
  [#2914](https://github.com/OpenFn/lightning/issues/2914)
- Only allow `owner` and `admin` users to manage collections
  [#2923](https://github.com/OpenFn/lightning/issues/2923)

### Fixed

- Fixed issue where we failed to send failure alerts via email when runs were
  "lost". [#2921](https://github.com/OpenFn/lightning/issues/2921)

## [v2.10.14] - 2025-02-06

### Added

- Extend provisioner to support collections
  [#2830](https://github.com/OpenFn/lightning/issues/2830)
- Add collection limiter in the provisioner
  [PR#2910](https://github.com/OpenFn/lightning/pull/2910)
- Adds project name to failure alert email
  [#2884](https://github.com/OpenFn/lightning/pull/2884)
- Allow project users to manage collections
  [#2838](https://github.com/OpenFn/lightning/issues/2838)
- Allow limiting Collection create, put and put_all
  [#2853](https://github.com/OpenFn/lightning/issues/2853)

### Changed

- Makes the whole project row in the projects table clickable.
  [#2889](https://github.com/OpenFn/lightning/pull/2889)
- Standardizes date formats to YYYY-MM-DD
  [#2884](https://github.com/OpenFn/lightning/pull/2884)

### Fixed

- Allow ordering of Plug Injection
  [#2903](https://github.com/OpenFn/lightning/issues/2903)
- Removed empty first line in job editor helper text
  [#2887](https://github.com/OpenFn/lightning/pull/2887)
- Standardizes sort order arrows (all now show the direction of sort, rather
  than the direction they would sort if toggled)
  [#2423](https://github.com/OpenFn/lightning/issues/2423)
- Project combobox is populated when viewing MFA backup codes.
  [#2870](https://github.com/OpenFn/lightning/issues/2870)
- Allow JobEditor metrics to be tracked when the version of the workflow being
  viewed is not the latest version.
  [#2891](https://github.com/OpenFn/lightning/issues/2891)

## [v2.10.13] - 2025-01-29

### Added

- Add support for local adaptors. This can be enabled via `LOCAL_ADAPTORS=true`
  and path specified via `OPENFN_ADAPTORS_REPO=./path/to/repo/`
  [#905](https://github.com/OpenFn/lightning/issues/905)
- Add component injection for AI responses feedback
  [#2495](https://github.com/OpenFn/lightning/issues/2495)
- Audit the provisioning of projects via the API
  [#2718](https://github.com/OpenFn/lightning/issues/2718)
- Track Collections storage usage based on items key and value sizes
  [#2853](https://github.com/OpenFn/lightning/issues/2853)
- Temporary instrumentation for JobEditor to help identify performance issues.
  [#2617](https://github.com/OpenFn/lightning/issues/2617)
- Indexes to foreign keys on `workflow_edges` and `steps` tables to try and
  alleviate slow loading of the job editor.
  [#2617](https://github.com/OpenFn/lightning/issues/2617)
- Remove `Snapshot.get_or_create_latest_for`.
  [#2703](https://github.com/OpenFn/lightning/issues/2703)
- Add temporary events to allow Lightning to log metrics reported by editors.
  [#2617](https://github.com/OpenFn/lightning/issues/2617)
- Audit when workflow deletion is requested.
  [#2727](https://github.com/OpenFn/lightning/issues/2727)

### Changed

- Remove snapshot creation when performing the Github sync - no longer needed
  post-migration. [#2703](https://github.com/OpenFn/lightning/issues/2703)
- Remove some redundant code related to `WorkOrders.create_for`.
  [#2703](https://github.com/OpenFn/lightning/issues/2703)
- Remove use of Snapshot.get_or_create_latest_for from tests.
  [#2703](https://github.com/OpenFn/lightning/issues/2703)
- Bump PostCSS [#2863](https://github.com/OpenFn/lightning/pull/2863)
- Replaced HTTPoison with Tesla in the AdaptorRegistry.
  [#2861](https://github.com/OpenFn/lightning/pull/2861)
- Remove googlesheets, gmail and collections from credential schemas list
  [#2854](https://github.com/OpenFn/lightning/issues/2854)
- Remove ring on save workflow button
  [#2829](https://github.com/OpenFn/lightning/issues/2829)

### Fixed

- Do not send digest emails for projects with no workflows
  [#2688](https://github.com/OpenFn/lightning/issues/2688)
- Fixed navbar items alignment in the workflow builder
  [#2825](https://github.com/OpenFn/lightning/issues/2825)
- PromEx metrics no longer detaching on error
  [#2875](https://github.com/OpenFn/lightning/issues/2875)

## [v2.10.12] - 2025-01-21

### Changed

- PromEx metrics endpoint returns 401 on unauthorized requests.
  [#2823](https://github.com/OpenFn/lightning/issues/2823)
- Allow non-openfn.org users to access AI Assistant
  [#2845](https://github.com/OpenFn/lightning/issues/2845)

## [v2.10.11] - 2025-01-21

### Added

- Add component injection for AI responses feedback
  [#2495](https://github.com/OpenFn/lightning/issues/2495)

### Fixed

- Fix `z-index` for unsaved workflow dot on workflow edit page
  [#2809](https://github.com/OpenFn/lightning/issues/2809)

## [v2.10.10] - 2025-01-15

### Added

- Add workflows API to create, update, get and list.
  [#1887](https://github.com/OpenFn/lightning/issues/1887)
- Show email address of credential owner on project credentials page
  [#2210](https://github.com/OpenFn/lightning/issues/2210)

### Changed

- Configure Monaco to load files from lightning instead of cdn
  [#2786](https://github.com/OpenFn/lightning/issues/2786)

### Fixed

- Fixed Save and Run to always execute jobs with latest changes
  [#2804](https://github.com/OpenFn/lightning/issues/2804)
- Fixed aggressive CSS rule in app.css that made it hard to style menu items
  [#2807](https://github.com/OpenFn/lightning/pull/2807)
- `z-index` broken on unsaved dot on workflow edit page
  [#2809](https://github.com/OpenFn/lightning/issues/2809)
- Fixed an issue in the editor where the Loading Types message displays forever
  while running offline [#2813](https://github.com/OpenFn/lightning/issues/2813)
- Fixed an a small layout issue in the Docs panel when loading the editor
  offline [#2813](https://github.com/OpenFn/lightning/issues/2813)

## [v2.10.9] - 2025-01-09

### Added

- Audit the creation and removal of Github repo connections.
  [#2668](https://github.com/OpenFn/lightning/issues/2668)
- Add save and sync option in the workflow edit page
  [#2707](https://github.com/OpenFn/lightning/issues/2707)

### Changed

- Git-ignore files from mix assets.deploy
  [#2788](https://github.com/OpenFn/lightning/issues/2788)
- Added Claude integration in job chat
  [#2403](https://github.com/OpenFn/lightning/pull/2403)
- OPENAI_API_KEY renamed to AI_ASSISTANT_API_KEY
  [#2403](https://github.com/OpenFn/lightning/pull/2403)
- Remove snapshot creation from WorkOrders, no longer necessary post-migration.
  [#2703](https://github.com/OpenFn/lightning/issues/2703)

## [v2.10.8] - 2024-12-18

### Added

- Add ability to retry or cancel AI Assistant error responses for user messages
  [#2704](https://github.com/OpenFn/lightning/issues/2704)

### Changed

## [v2.10.7] - 2024-12-13 🎂 ❤️ Happy Birthday, Mom!

### Added

- Clear AI assistant's chat input after a message is sent
  [#2781](https://github.com/OpenFn/lightning/issues/2781)
- Allow different rules and action for delete user.
  [#2500](https://github.com/OpenFn/lightning/issues/2500)
- Handle errors from the AI Assistant more gracefully
  [#2474](https://github.com/OpenFn/lightning/issues/2474)

### Changed

- Make the AdaptorRegistry cache path configurable
  [#2780](https://github.com/OpenFn/lightning/issues/2780)

### Fixed

- Delete user modal no longer uses the same id as the underlying user record.
  [#2751](https://github.com/OpenFn/lightning/issues/2751)
- Use workflow activation limiter on index toggle.
  [#2777](https://github.com/OpenFn/lightning/issues/2777)

## [v2.10.6] - 2024-12-10

### Added

- Handle errors from the AI Assistant more gracefully
  [#2741](https://github.com/OpenFn/lightning/issues/2741)

### Changed

- Updated the About the AI Assistant help text
- Make user email verification optional. Defaults to `false`
  [#2755](https://github.com/OpenFn/lightning/issues/2755)
  > ⚠️ The default was behaviour was to always require email verification. Set
  > `REQUIRE_EMAIL_VERIFICATION` to `true` to revert to the old behaviour.
- Enhance AI assistant panel UI
  [#2497](https://github.com/OpenFn/lightning/issues/2497)
- Allow superusers to be created via the user UI.
  [#2719](https://github.com/OpenFn/lightning/issues/2719)

### Fixed

- Fix Priority and Scope Issues in Inspector Key Bindings
  [#2770](https://github.com/OpenFn/lightning/issues/2770)
- Fixed an issue where sometimes adaptor docs won't load in the Inspector
  [#2749](https://github.com/OpenFn/lightning/pull/2749)
- Return a 422 when a duplicate key is sent to the collections post/put_all API
  [#2752](https://github.com/OpenFn/lightning/issues/2752)
- Do not require the user's password when a superuser updates a user.
  [#2757](https://github.com/OpenFn/lightning/issues/2757)

## [v2.10.5] - 2024-12-04

### Added

- Enable Tab Key for Indenting Text in AI Assistant Input Box
  [#2407](https://github.com/OpenFn/lightning/issues/2407)
- Ctrl/Cmd + Enter to Send a Message to the AI Assistant
  [#2406](https://github.com/OpenFn/lightning/issues/2406)
- Add styles to AI chat messages
  [#2484](https://github.com/OpenFn/lightning/issues/2484)
- Auditing when enabling/disabling a workflow
  [#2697](https://github.com/OpenFn/lightning/issues/2697)
- Ability to enable/disable a workflow from the workflow editor
  [#2698](https://github.com/OpenFn/lightning/issues/2698)

### Changed

- Insert all on a collection with the same timestamp
  [#2711](https://github.com/OpenFn/lightning/issues/2711)
- AI Assistant: Show disclaimer once every day per user
  [#2481](https://github.com/OpenFn/lightning/issues/2481)
- AI Assistant: Scroll to new message when it arrives
  [#2409](https://github.com/OpenFn/lightning/issues/2409)
- AI Assistant: Set vertical scrollbar below the session title
  [#2477](https://github.com/OpenFn/lightning/issues/2477)
- AI Assistant: Increase size of input box for easier handling of large inputs
  [#2408](https://github.com/OpenFn/lightning/issues/2408)
- Bumped dependencies
- Extend display of audit events to cater for deletions.
  [#2701](https://github.com/OpenFn/lightning/issues/2701)
- Kafka documentation housekeeping.
  [#2414](https://github.com/OpenFn/lightning/issues/2414)

### Fixed

- Collections controller sending an invalid response body when a item doesn't
  exist [#2733](https://github.com/OpenFn/lightning/issues/2733)
- AI Assistant: Text in the form gets cleared when you change the editor content
  [#2739](https://github.com/OpenFn/lightning/issues/2739)

## [v2.10.4] - 2024-11-22

### Added

- Support dynamic json schema email format validation.
  [#2664](https://github.com/OpenFn/lightning/issues/2664)
- Audit snapshot creation
  [#2601](https://github.com/OpenFn/lightning/issues/2601)
- Allow filtering collection items by updated_before and updated_after.
  [#2693](https://github.com/OpenFn/lightning/issues/2693)
- Add support for SMTP email configuration
  [#2699](https://github.com/OpenFn/lightning/issues/2699) ⚠️️ Please note that
  `EMAIL_ADMIN` defaults to `lightning@example.com` in production environments

### Fixed

- Fix cursor for small limit on collections request
  [#2683](https://github.com/OpenFn/lightning/issues/2683)
- Disable save and run actions on deleted workflows
  [#2170](https://github.com/OpenFn/lightning/issues/2170)
- Distinguish active and inactive sort arrows in projects overview table
  [#2423](https://github.com/OpenFn/lightning/issues/2423)
- Fix show password toggle icon gets flipped after changing the password value
  [#2611](https://github.com/OpenFn/lightning/issues/2611)

## [v2.10.3] - 2024-11-13

### Added

- Disable monaco command palette in Input and Log viewers
  [#2643](https://github.com/OpenFn/lightning/issues/2643)
- Make provision for non-User actors when creating Audit entries.
  [#2601](https://github.com/OpenFn/lightning/issues/2601)

### Fixed

- Superusers can't update users passwords
  [#2621](https://github.com/OpenFn/lightning/issues/2621)
- Attempt to reduce memory consumption when generating UsageTracking reports.
  [#2636](https://github.com/OpenFn/lightning/issues/2636)

## [v2.10.2] - 2024-11-14

### Added

- Audit history exports events
  [#2637](https://github.com/OpenFn/lightning/issues/2637)

### Changed

- Ignore Plug.Conn.InvalidQueryError in Sentry
  [#2672](https://github.com/OpenFn/lightning/issues/2672)
- Add Index to `dataclip_id` on `runs` and `work_orders` tables to speed up
  deletion [PR#2677](https://github.com/OpenFn/lightning/pull/2677)

### Fixed

- Error when the logger receives a boolean
  [#2666](https://github.com/OpenFn/lightning/issues/2666)

## [v2.10.1] - 2024-11-13

### Fixed

- Fix metadata loading as code-assist in the editor
  [#2669](https://github.com/OpenFn/lightning/pull/2669)
- Fix Broken Input Dataclip UI
  [#2670](https://github.com/OpenFn/lightning/pull/2670)

## [v2.10.0] - 2024-11-13

### Changed

- Increase collection items value limit to 1M characters
  [#2661](https://github.com/OpenFn/lightning/pull/2661)

### Fixed

- Fix issues loading suggestions for code-assist
  [#2662](https://github.com/OpenFn/lightning/pull/2662)

## [v2.10.0-rc.2] - 2024-11-12

### Added

- Bootstrap script to help install and configure the Lightning app for
  development [#2654](https://github.com/OpenFn/lightning/pull/2654)

### Changed

- Upgrade dependencies [#2624](https://github.com/OpenFn/lightning/pull/2624)
- Hide the collections and fhir-jembi adaptors from the available adaptors list
  [#2648](https://github.com/OpenFn/lightning/issues/2648)
- Change column name for "Last Activity" to "Last Modified" on Projects list
  [#2593](https://github.com/OpenFn/lightning/issues/2593)

### Fixed

- Fix LiveView crash when pressing "esc" on inspector
  [#2622](https://github.com/OpenFn/lightning/issues/2622)
- Delete project data in batches to avoid timeouts in the db connection
  [#2632](https://github.com/OpenFn/lightning/issues/2632)
- Fix MetadataService crashing when errors are encountered
  [#2659](https://github.com/OpenFn/lightning/issues/2659)

## [v2.10.0-rc.1] - 2024-11-08

### Changed

- Reduce transaction time when fetching collection items by fetching upfront
  [#2645](https://github.com/OpenFn/lightning/issues/2645)

## [v2.10.0-rc.0] - 2024-11-07

### Added

- Adds a UI for managing collections
  [#2567](https://github.com/OpenFn/lightning/issues/2567)
- Introduces collections, a programatic workflow data sharing resource.
  [#2551](https://github.com/OpenFn/lightning/issues/2551)

## [v2.9.15] - 2024-11-06

### Added

- Added some basic editor usage tips to the docs panel
  [#2629](https://github.com/OpenFn/lightning/pull/2629)
- Create audit events when the retention periods for a project's dataclips and
  history are modified. [#2589](https://github.com/OpenFn/lightning/issues/2589)

### Changed

- The Docs panel in the inspector will now be closed by default
  [#2629](https://github.com/OpenFn/lightning/pull/2629)
- JSDoc annotations are removed from code assist descriptions
  [#2629](https://github.com/OpenFn/lightning/pull/2629)
- Show project name during delete confirmation
  [#2634](https://github.com/OpenFn/lightning/pull/2634)

### Fixed

- Fix misaligned margins on collapsed panels in the inspector
  [#2571](https://github.com/OpenFn/lightning/issues/2571)
- Fix sorting directions icons in projects table in the project dashboard page
  [#2631](https://github.com/OpenFn/lightning/pull/2631)
- Fixed an issue where code-completion prompts don't load properly in the
  inspector [#2629](https://github.com/OpenFn/lightning/pull/2629)
- Fixed an issue where namespaces (like http.) don't appear in code assist
  prompts [#2629](https://github.com/OpenFn/lightning/pull/2629)

## [v2.9.14] - 2024-10-31

### Added

- Additional documentation and notification text relating to the importance of
  alternate storage for Kafka triggers.
  [#2614](https://github.com/OpenFn/lightning/issues/2614)
- Add support for run memory limit option
  [#2623](https://github.com/OpenFn/lightning/pull/2623)

### Changed

- Enforcing MFA for a project can be enforced by the usage limiter
  [#2607](https://github.com/OpenFn/lightning/pull/2607)
- Add extensions for limiting retention period
  [#2618](https://github.com/OpenFn/lightning/pull/2618)

## [v2.9.13] - 2024-10-28

### Changed

- Add responsible ai disclaimer to arcade video
  [#2610](https://github.com/OpenFn/lightning/pull/2610)

## [v2.9.12] - 2024-10-25

### Fixed

- Fix editor panel buttons gets out of shape on smaller screens
  [#2278](https://github.com/OpenFn/lightning/issues/2278)
- Do not send empty strings in credential body to the worker
  [#2585](https://github.com/OpenFn/lightning/issues/2585)
- Refactor projects dashboard page and fix bug on last activity column
  [#2593](https://github.com/OpenFn/lightning/issues/2593)

## [v2.9.11] - 2024-10-23

### Added

- Optionally write Kafka messages that can not be persisted to the file system.
  [#2386](https://github.com/OpenFn/lightning/issues/2386)
- Add `MessageRecovery` utility code to restore Kafka messages that were
  pesisted to the file system.
  [#2386](https://github.com/OpenFn/lightning/issues/2386)
- Projects page welcome section: allow users to learn how to use the app thru
  Arcade videos [#2563](https://github.com/OpenFn/lightning/issues/2563)
- Store user preferences in database
  [#2564](https://github.com/OpenFn/lightning/issues/2564)

### Changed

- Allow users to to preview password fields in credential forms
  [#2584](https://github.com/OpenFn/lightning/issues/2584)
- Remove superuser flag for oauth clients creation
  [#2417](https://github.com/OpenFn/lightning/issues/2417)
- Make URL validator more flexible to support URLs with dashes and other cases
  [#2417](https://github.com/OpenFn/lightning/issues/2417)

### Fixed

- Fix retry many workorders when built for job
  [#2597](https://github.com/OpenFn/lightning/issues/2597)
- Do not count deleted workflows in the projects table
  [#2540](https://github.com/OpenFn/lightning/issues/2540)

## [v2.9.10] - 2024-10-16

### Added

- Notify users when a Kafka trigger can not persist a message to the database.
  [#2386](https://github.com/OpenFn/lightning/issues/2386)
- Support `kafka` trigger type in the provisioner
  [#2506](https://github.com/OpenFn/lightning/issues/2506)

### Fixed

- Fix work order retry sorting and avoids loading dataclips
  [#2581](https://github.com/OpenFn/lightning/issues/2581)
- Fix editor panel overlays output panel when scrolled
  [#2291](https://github.com/OpenFn/lightning/issues/2291)

## [v2.9.9] - 2024-10-09

### Changed

- Make project description multiline in project.yaml
  [#2534](https://github.com/OpenFn/lightning/issues/2534)
- Do not track partition timestamps when ingesting Kafka messages.
  [#2531](https://github.com/OpenFn/lightning/issues/2531)
- Always use the `initial_offset_reset_policy` when enabling a Kafka pipeline.
  [#2531](https://github.com/OpenFn/lightning/issues/2531)
- Add plumbing to simulate a persistence failure in a Kafka trigger pipeline.
  [#2386](https://github.com/OpenFn/lightning/issues/2386)

### Fixed

- Fix Oban errors not getting logged in Sentry
  [#2542](https://github.com/OpenFn/lightning/issues/2542)
- Perform data retention purging in batches to avoid timeouts
  [#2528](https://github.com/OpenFn/lightning/issues/2528)
- Fix editor panel title gets pushed away when collapsed
  [#2545](https://github.com/OpenFn/lightning/issues/2545)
- Mark unfinished steps having finished runs as `lost`
  [#2416](https://github.com/OpenFn/lightning/issues/2416)

## [v2.9.8] - 2024-10-03

### Added

- Ability for users to to retry Runs and create manual Work Orders from the job
  inspector #2496 [#2496](https://github.com/OpenFn/lightning/issues/2496)

### Fixed

- Fix panel icons overlays on top title when collapsed
  [#2537](https://github.com/OpenFn/lightning/issues/2537)

## [v2.9.7] - 2024-10-02

### Added

- Enqueues many work orders retries in the same transaction per Oban job.
  [#2363](https://github.com/OpenFn/lightning/issues/2363)
- Added the ability to retry rejected work orders.
  [#2391](https://github.com/OpenFn/lightning/issues/2391)

### Changed

- Notify other present users when the promoted user saves the workflow
  [#2282](https://github.com/OpenFn/lightning/issues/2282)
- User email change: Add debounce on blur to input forms to avoid validation
  after every keystroke [#2365](https://github.com/OpenFn/lightning/issues/2365)

### Fixed

- Use timestamps sent from worker when starting and completing runs
  [#2434](https://github.com/OpenFn/lightning/issues/2434)
- User email change: Add debounce on blur to input forms to avoid validation
  after every keystroke [#2365](https://github.com/OpenFn/lightning/issues/2365)

### Fixed

- User email change: Send notification of change to the old email address and
  confirmation to the new email address
  [#2365](https://github.com/OpenFn/lightning/issues/2365)
- Fixes filters to properly handle the "rejected" status for work orders.
  [#2391](https://github.com/OpenFn/lightning/issues/2391)
- Fix item selection (project / billing account) in the context switcher
  [#2518](https://github.com/OpenFn/lightning/issues/2518)
- Export edge condition expressions as multiline in project spec
  [#2521](https://github.com/OpenFn/lightning/issues/2521)
- Fix line spacing on AI Assistant
  [#2498](https://github.com/OpenFn/lightning/issues/2498)

## [v2.9.6] - 2024-09-23

### Added

### Changed

- Increase minimum password length to 12 in accordance with ASVS 4.0.3
  recommendation V2.1.2 [#2507](https://github.com/OpenFn/lightning/pull/2507)
- Changed the public sandbox (https://demo.openfn.org) setup script to use
  `welcome12345` passwords to comply with a 12-character minimum

### Fixed

- Dataclip selector always shows that the dataclip is wiped even when the job
  wasn't run [#2303](https://github.com/OpenFn/lightning/issues/2303)
- Send run channel errors to sentry
  [#2515](https://github.com/OpenFn/lightning/issues/2515)

## [v2.9.5] - 2024-09-18

### Changed

- Hide export history button when no workorder is rendered in the table
  [#2440](https://github.com/OpenFn/lightning/issues/2440)
- Improve docs for running lightning locally #2499
  [#2499](https://github.com/OpenFn/lightning/pull/2499)

### Fixed

- Fix empty webhook URL when switching workflow trigger type
  [#2050](https://github.com/OpenFn/lightning/issues/2050)
- Add quotes when special YAML characters are present in the exported project
  [#2446](https://github.com/OpenFn/lightning/issues/2446)
- In the AI Assistant, don't open the help page when clicking the Responsible AI
  Link [#2511](https://github.com/OpenFn/lightning/issues/2511)

## [v2.9.4] - 2024-09-16

### Changed

- Responsible AI review of AI Assistant
  [#2478](https://github.com/OpenFn/lightning/pull/2478)
- Improve history export page UI
  [#2442](https://github.com/OpenFn/lightning/issues/2442)
- When selecting a node in the workflow diagram, connected edges will also be
  highlighted [#2396](https://github.com/OpenFn/lightning/issues/2358)

### Fixed

- Fix AI Assitant crashes on a job that is not saved yet
  [#2479](https://github.com/OpenFn/lightning/issues/2479)
- Fix jumpy combobox for scope switcher
  [#2469](https://github.com/OpenFn/lightning/issues/2469)
- Fix console errors when rending edge labels in the workflow diagram
- Fix tooltip on export workorder button
  [#2430](https://github.com/OpenFn/lightning/issues/2430)

## [v2.9.3] - 2024-09-11

### Added

- Add utility module to seed a DB to support query performance analysis.
  [#2441](https://github.com/OpenFn/lightning/issues/2441)

### Changed

- Enhance user profile page to add a section for updating basic information
  [#2470](https://github.com/OpenFn/lightning/pull/2470)
- Upgraded Heroicons to v2.1.5, from v2.0.18
  [#2483](https://github.com/OpenFn/lightning/pull/2483)
- Standardize `link-uuid` style for uuid chips
- Updated PromEx configuration to align with custom Oban naming.
  [#2488](https://github.com/OpenFn/lightning/issues/2488)

## [v2.9.2] - 2024-09-09

### Changed

- Temporarily limit AI to @openfn emails while testing
  [#2482](https://github.com/OpenFn/lightning/pull/2482)

## [v2.9.1] - 2024-09-09

### Fixed

- Provisioner creates invalid snapshots when doing CLI deploy
  [#2461](https://github.com/OpenFn/lightning/issues/2461)
  [#2460](https://github.com/OpenFn/lightning/issues/2460)

  > This is a fix for future Workflow updates that are deployed by the CLI and
  > Github integrations. Unfortunately, there is a high likelihood that your
  > existing snapshots could be incorrect (e.g. missing steps, missing edges).
  > In order to fix this, you will need to manually create new snapshots for
  > each of your workflows. This can be done either by modifying the workflow in
  > the UI and saving it. Or running a command on the running instance:
  >
  > ```elixir
  > alias Lightning.Repo
  > alias Lightning.Workflows.{Workflow, Snapshot}
  >
  > Repo.transaction(fn ->
  >   snapshots =
  >     Repo.all(Workflow)
  >     |> Enum.map(&Workflow.touch/1)
  >     |> Enum.map(&Repo.update!/1)
  >     |> Enum.map(fn workflow ->
  >       {:ok, snapshot} = Snapshot.create(workflow)
  >       snapshot
  >     end)
  >
  >  {:ok, snapshots}
  > end)
  > ```

## [v2.9.0] - 2024-09-06

### Added

- Limit AI queries and hook the increment of AI queries to allow usage limiting.
  [#2438](https://github.com/OpenFn/lightning/pull/2438)
- Persist AI Assistant conversations and enable it for all users
  [#2296](https://github.com/OpenFn/lightning/issues/2296)

### Changed

- Rename `new_table` component to `table`.
  [#2448](https://github.com/OpenFn/lightning/pull/2448)

### Fixed

- Fix `workflow_id` presence in state.json during Github sync
  [#2445](https://github.com/OpenFn/lightning/issues/2445)

## [v2.8.2] - 2024-09-04

### Added

- Change navbar colors depending on scope.
  [#2449](https://github.com/OpenFn/lightning/pull/2449)
- Add support for configurable idle connection timeouts via the `IDLE_TIMEOUT`
  environment variable. [#2443](https://github.com/OpenFn/lightning/issues/2443)

### Changed

- Allow setup_user command to be execute from outside the container with
  `/app/bin/lightning eval Lightning.Setup.setup_user/3`
- Implement a combo-box to make navigating between projects easier
  [#241](https://github.com/OpenFn/lightning/pull/2424)
- Updated vulnerable version of micromatch.
  [#2454](https://github.com/OpenFn/lightning/issues/2454)

## [v2.8.1] - 2024-08-28

### Changed

- Improve run claim query by removing extraneous sorts
  [#2431](https://github.com/OpenFn/lightning/issues/2431)

## [v2.8.0] - 2024-08-27

### Added

- Users are now able to export work orders, runs, steps, logs, and dataclips
  from the History page.
  [#1698](https://github.com/OpenFn/lightning/issues/1698)

### Changed

- Add index over `run_id` and `step_id` in run_steps to improve worker claim
  speed. [#2428](https://github.com/OpenFn/lightning/issues/2428)
- Show Github Error messages as they are to help troubleshooting
  [#2156](https://github.com/OpenFn/lightning/issues/2156)
- Allow `Setup_utils.setup_user` to be used for the initial superuser creation.
- Update to code assist in the Job Editor to import namespaces from adaptors.
  [#2432](https://github.com/OpenFn/lightning/issues/2432)

### Fixed

- Unable to remove/reconnect github app in lightning after uninstalling directly
  from Github [#2168](https://github.com/OpenFn/lightning/issues/2168)
- Github sync buttons available even when usage limiter returns error
  [PR#2390](https://github.com/OpenFn/lightning/pull/2390)
- Fix issue with the persisting of a Kafka message with headers.
  [#2402](https://github.com/OpenFn/lightning/issues/2402)
- Protect against race conditions when updating partition timestamps for a Kafka
  trigger. [#2378](https://github.com/OpenFn/lightning/issues/2378)

## [v2.7.19] - 2024-08-19

### Added

- Pass the user_id param on check usage limits.
  [#2387](https://github.com/OpenFn/lightning/issues/2387)

## [v2.7.18] - 2024-08-17

### Added

- Ensure that all users in an instance have a confirmed email address within 48
  hours [#2389](https://github.com/OpenFn/lightning/issues/2389)

### Changed

- Ensure that all the demo accounts are confirmed by default
  [#2395](https://github.com/OpenFn/lightning/issues/2395)

### Fixed

- Removed all Kafka trigger code that ensured that message sequence is honoured
  for messages with keys. Functionality to ensure that message sequence is
  honoured will be added in the future, but in an abstraction that is a better
  fit for the current Lightning design.
  [#2362](https://github.com/OpenFn/lightning/issues/2362)
- Dropped the `trigger_kafka_messages` table that formed part of the Kafka
  trigger implementation, but which is now obsolete given the removal of the
  code related to message sequence preservation.
  [#2362](https://github.com/OpenFn/lightning/issues/2362)

## [v2.7.17] - 2024-08-14

### Added

- Added an `iex` command to setup a user, an apiToken, and credentials so that
  it's possible to get a fully running lightning instance via external shell
  script. (This is a tricky requirement for a distributed set of local
  deployments) [#2369](https://github.com/OpenFn/lightning/issues/2369) and
  [#2373](https://github.com/OpenFn/lightning/pull/2373)
- Added support for _very basic_ project-credential management (add, associate
  with job) via provisioning API.
  [#2367](https://github.com/OpenFn/lightning/issues/2367)

### Changed

- Enforced uniqueness on credential names _by user_.
  [#2371](https://github.com/OpenFn/lightning/pull/2371)
- Use Swoosh to format User models into recipients
  [#2374](https://github.com/OpenFn/lightning/pull/2374)
- Bump default CLI to `@openfn/cli@1.8.1`

### Fixed

- When a Workflow is deleted, any associated Kafka trigger pipelines will be
  stopped and deleted. [#2379](https://github.com/OpenFn/lightning/issues/2379)

## [v2.7.16] - 2024-08-07

### Fixed

- @ibrahimwickama fixed issue that prevented users from creating new workflows
  if they are running in an `http` environment (rather than `localhost` or
  `https`). [#2365](https://github.com/OpenFn/lightning/pull/2356)

## [v2.7.15] - 2024-08-07

### Changed

- Kafka messages without keys are synchronously converted into a Workorder,
  Dataclip and Run. Messages with keys are stored as TriggerKafkaMessage
  records, however the code needed to process them has been disabled, pending
  removal. [#2351](https://github.com/OpenFn/lightning/issues/2351)

## [v2.7.14] - 2024-08-05

### Changed

- Use standard styles for link, fix home button in breadcrumbs
  [#2354](https://github.com/OpenFn/lightning/pull/2354)

## [v2.7.13] - 2024-08-05

### Changed

- Don't log 406 Not Acceptable errors to Sentry
  [#2350](https://github.com/OpenFn/lightning/issues/2350)

### Fixed

- Correctly handle floats in LogMessage
  [#2348](https://github.com/OpenFn/lightning/issues/2348)

## [v2.7.12] - 2024-07-31

### Changed

- Make root layout configurable
  [#2310](https://github.com/OpenFn/lightning/pull/2310)
- Use snapshots when initiating Github Sync
  [#1827](https://github.com/OpenFn/lightning/issues/1827)
- Move runtime logic into module
  [#2338](https://github.com/OpenFn/lightning/pull/2338)
- Use `AccountHook Extension` to register new users invited in a project
  [#2341](https://github.com/OpenFn/lightning/pull/2341)
- Standardized top bars across the UI with a navigable breadcrumbs interface
  [#2299](https://github.com/OpenFn/lightning/pull/2299)

### Fixed

- Limit frame size of worker socket connections
  [#2339](https://github.com/OpenFn/lightning/issues/2339)
- Limit number of days to 31 in cron trigger dropdown
  [#2331](https://github.com/OpenFn/lightning/issues/2331)

## [v2.7.11] - 2024-07-26

### Added

- Expose more Kafka configuration at instance-level.
  [#2329](https://github.com/OpenFn/lightning/issues/2329)

### Fixed

- Table action css tweaks
  [#2333](https://github.com/OpenFn/lightning/issues/2333)

## [v2.7.10]

### Added

- A rudimentary optimisation for Kafka messages that do not have a key as the
  sequence of these messages can not be guaranteed.
  [#2323](https://github.com/OpenFn/lightning/issues/2323)

### Fixed

- Fix an intermittent bug when trying to intern Kafka offset reset policy.
  [#2327](https://github.com/OpenFn/lightning/issues/2327)

## [v2.7.9] - 2024-07-24

### Changed

- CSS - standardized some more tailwind components
  [PR#2324](https://github.com/OpenFn/lightning/pull/2324)

## [v2.7.8] - 2024-07-24

### Changed

- Enable End to End Integration tests
  [#2187](https://github.com/OpenFn/lightning/issues/2187)
- Make selected Kafka trigger parameters configurable via ENV vars.
  [#2315](https://github.com/OpenFn/lightning/issues/2315)
- Use the Oauth2 `revocation_endpoint` to revoke token access (1) before
  attempting to reauthorize and (2) when users schedule a credential for
  deletion [#2314](https://github.com/OpenFn/lightning/issues/2314)
- Standardized tailwind alerts
  [#2314](https://github.com/OpenFn/lightning/issues/2314)
- Standardized `link` tailwind style (and provided `link-plain`, `link-info`,
  `link-error`, and `link-warning`)
  [#2314](https://github.com/OpenFn/lightning/issues/2314)

### Fixed

- Fix work order URL in failure alerts
  [#2305](https://github.com/OpenFn/lightning/pull/2305)
- Fix error when handling existing encrypted credentials
  [#2316](https://github.com/OpenFn/lightning/issues/2316)
- Fix job editor switches to the snapshot version when body is changed
  [#2306](https://github.com/OpenFn/lightning/issues/2306)
- Fix misaligned "Retry from here" button on inspector page
  [#2308](https://github.com/OpenFn/lightning/issues/2308)

## [v2.7.7] - 2024-07-18

### Added

- Add experimental support for triggers that consume message from a Kafka
  cluster [#1801](https://github.com/OpenFn/lightning/issues/1801)
- Workflows can now specify concurrency, allowing runs to be executed
  syncronously or to a maximum concurrency level. Note that this applies to the
  default FifoRunQueue only.
  [#2022](https://github.com/OpenFn/lightning/issues/2022)
- Invite Non-Registered Users to a Project
  [#2288](https://github.com/OpenFn/lightning/pull/2288)

### Changed

- Make modal close events configurable
  [#2298](https://github.com/OpenFn/lightning/issues/2298)

### Fixed

- Prevent Oauth credentials from being created if they don't have a
  `refresh_token` [#2289](https://github.com/OpenFn/lightning/pull/2289) and
  send more helpful error data back to the worker during token refresh failure
  [#2135](https://github.com/OpenFn/lightning/issues/2135)
- Fix CLI deploy not creating snapshots for workflows
  [#2271](https://github.com/OpenFn/lightning/issues/2271)

## [v2.7.6] - 2024-07-11

### Fixed

- UsageTracking crons are enabled again (if config is enabled)
  [#2276](https://github.com/OpenFn/lightning/issues/2276)
- UsageTracking metrics absorb the fact that a step's job_id may not currently
  exist when counting unique jobs
  [#2279](https://github.com/OpenFn/lightning/issues/2279)
- Adjusted layout and text displayed when preventing simultaneous edits to
  accommodate more screen sizes
  [#2277](https://github.com/OpenFn/lightning/issues/2277)

## [v2.7.5] - 2024-07-10

### Changed

- Prevent two editors from making changes to the same workflow at the same time
  [#1949](https://github.com/OpenFn/lightning/issues/1949)
- Moved the Edge Condition Label field to the top of the form, so it's always
  visible [#2236](https://github.com/OpenFn/lightning/pull/2236)
- Update edge condition labels in the Workflow Diagram to always show the
  condition type icon and the label
  [#2236](https://github.com/OpenFn/lightning/pull/2236)

### Fixed

- Do Not Require Lock Version In URL Parameters
  [#2267](https://github.com/OpenFn/lightning/pull/2267)
- Trim erroneous spaces on user first and last names
  [#2269](https://github.com/OpenFn/lightning/pull/2269)

## [v2.7.4] - 2024-07-06

### Changed

- When the entire log string is a valid JSON object, pretty print it with a
  standard `JSON.stringify(str, null, 2)` but if it's something else then let
  the user do whatever they want (e.g., if you write
  `console.log('some', 'cool', state.data)` we won't mess with it.)
  [#2260](https://github.com/OpenFn/lightning/pull/2260)

### Fixed

- Fixed sticky toggle button for switching between latest version and a snapshot
  of a workflow [#2264](https://github.com/OpenFn/lightning/pull/2264)

## [v2.7.3] - 2024-07-05

### Changed

- Bumped the ws-worker to v1.3

### Fixed

- Fix issue when selecting different steps in RunViewer and the parent liveview
  not being informed [#2253](https://github.com/OpenFn/lightning/issues/2253)
- Stopped inspector from crashing when looking for a step by a run/job
  combination [#2201](https://github.com/OpenFn/lightning/issues/2201)
- Workflow activation only considers new and changed workflows
  [#2237](https://github.com/OpenFn/lightning/pull/2237)

## [v2.7.2] - 2024-07-03

### Changed

- Allow endpoint plugs to be injected at compile time.
  [#2248](https://github.com/OpenFn/lightning/pull/2248)
- All models to use the `public` schema.
  [#2249](https://github.com/OpenFn/lightning/pull/2249)
- In the workflow diagram, smartly update the view when adding new nodes
  [#2174](https://github.com/OpenFn/lightning/issues/2174)
- In the workflow diagram, remove the "autofit" toggle in the control bar

### Fixed

- Remove prompt parameter from the authorization URL parameters for the Generic
  Oauth Clients [#2250](https://github.com/OpenFn/lightning/issues/2250)
- Fixed react key error [#2233](https://github.com/OpenFn/lightning/issues/2233)
- Show common functions in the Docs panel
  [#1733](https://github.com/OpenFn/lightning/issues/1733)

## [v2.7.1] - 2024-07-01

### Changed

- Update email copies [#2213](https://github.com/OpenFn/lightning/issues/2213)

### Fixed

- Fix jumpy cursor in the Job editor.
  [#2229](https://github.com/OpenFn/lightning/issues/2229)
- Rework syncing behaviour to prevent changes getting thrown out on a socket
  reconnect. [#2007](https://github.com/OpenFn/lightning/issues/2007)

## [v2.7.0] - 2024-06-26

### Added

- Use of snapshots for displaying runs and their associated steps in the History
  page. [#1825](https://github.com/OpenFn/lightning/issues/1825)
- Added view-only mode for rendering workflows and runs in the Workflow Canvas
  and the Inspector page using snapshots, with the option to switch between a
  specific snapshot version and the latest version. Edit mode is available when
  displaying the latest version.
  [#1843](https://github.com/OpenFn/lightning/issues/1843)
- Allow users to delete steps sssociated with runs in the Workflow Canvas
  [#2027](https://github.com/OpenFn/lightning/issues/2027)
- Link to adaptor `/src` from inspector.
- Prototype AI Assistant for working with job code.
  [#2193](https://github.com/OpenFn/lightning/issues/2193)

### Changed

- Reverted behaviour on "Rerun from here" to select the Log tab.
  [#2202](https://github.com/OpenFn/lightning/issues/2202)
- Don't allow connections between an orphaned node and a
  Trigger[#2188](https://github.com/OpenFn/lightning/issues/2188)
- Reduce the minimum zoom in the workflow diagram
  [#2214](https://github.com/OpenFn/lightning/issues/2214)

### Fixed

- Fix some adaptor docs not displaying
  [#2019](https://github.com/OpenFn/lightning/issues/2019)
- Fix broken `mix lightning.install_adaptor_icons` task due to addition of Finch
  http client change.

## [v2.6.3] - 2024-06-19

### Changed

- Added a notice on application start about anonymous public impact reporting
  and its importance for the sustainability of
  [Digital Public Goods](https://digitalpublicgoods.net/) and
  [Digital Public Infrastructure](https://www.codevelop.fund/insights-1/what-is-digital-public-infrastructure).
- Increase default `WORKER_MAX_RUN_DURATION_SECONDS` to 300 to match the
  [ws-worker default](https://github.com/OpenFn/kit/blob/main/packages/ws-worker/src/util/cli.ts#L149-L153)
  so if people don't set their timeout via ENV, at least the two match up.

## [v2.6.2] - 2024-06-13

### Fixed

- Fix vanishing Docs panel when Editor panel is collapsed and opened again
  [#2195](https://github.com/OpenFn/lightning/issues/2195)
- Maintain tab when RunViewer remounts/push state drops tab hash
  [#2199](https://github.com/OpenFn/lightning/issues/2199)

## [v2.6.1] - 2024-06-12

### Changed

- Erlang to 26.2.5
- Update debian bookworm from 20240130 to 20240513.
- Return 403s when Provisioning API fails because of usage limits
  [#2182](https://github.com/OpenFn/lightning/pull/2182)
- Update email notification for changing retention period
  [#2066](https://github.com/OpenFn/lightning/issues/2066)
- Return 415s when Webhooks are sent Content-Types what are not supported.
  [#2180](https://github.com/OpenFn/lightning/issues/2180)
- Updated the default step text

### Fixed

- Rewrite TabSelector (now Tabbed) components fixing a number of navigation
  issues [#2051](https://github.com/OpenFn/lightning/issues/2051)

## [v2.6.0] - 2024-06-05

### Added

- Support multiple edges leading to the same step (a.k.a., "drag & drop")
  [#2008](https://github.com/OpenFn/lightning/issues/2008)

### Changed

### Fixed

## [v2.5.5] - 2024-06-05

### Added

- Replace LiveView Log Viewer component with React Monaco
  [#1863](https://github.com/OpenFn/lightning/issues/1863)

### Changed

- Bump default CLI to `@openfn/cli@1.3.2`
- Don't show deprecated adaptor versions in the adaptor version picklist (to be
  followed by some graceful deprecation handling/warning in
  [later work](https://github.com/OpenFn/lightning/issues/2172))
  [#2169](https://github.com/OpenFn/lightning/issues/2169)
- Refactor count workorders to reuse search code
  [#2121](https://github.com/OpenFn/lightning/issues/2121)
- Updated provisioning error message to include workflow and job names
  [#2140](https://github.com/OpenFn/lightning/issues/2140)

### Fixed

- Don't let two deploy workflows run at the same time to prevent git collisions
  [#2044](https://github.com/OpenFn/lightning/issues/2044)
- Stopped sending emails when creating a starter project
  [#2161](https://github.com/OpenFn/lightning/issues/2161)

## [v2.5.4] - 2024-05-31

### Added

- CORS support [#2157](https://github.com/OpenFn/lightning/issues/2157)
- Track users emails preferences
  [#2163](https://github.com/OpenFn/lightning/issues/2163)

### Changed

- Change Default Text For New Job Nodes
  [#2014](https://github.com/OpenFn/lightning/pull/2014)
- Persisted run options when runs are _created_, not when they are _claimed_.
  This has the benefit of "locking in" the behavior desired by the user at the
  time they demand a run, not whenever the worker picks it up.
  [#2085](https://github.com/OpenFn/lightning/pull/2085)
- Made `RUN_GRACE_PERIOD_SECONDS` a configurable ENV instead of 20% of the
  `WORKER_MAX_RUN_DURATION`
  [#2085](https://github.com/OpenFn/lightning/pull/2085)

### Fixed

- Stopped Janitor from calling runs lost if they have special runtime options
  [#2079](https://github.com/OpenFn/lightning/issues/2079)
- Dataclip Viewer now responds to page resize and internal page layout
  [#2120](https://github.com/OpenFn/lightning/issues/2120)

## [v2.5.3] - 2024-05-27

### Changed

- Stop users from creating deprecated Salesforce and GoogleSheets credentials.
  [#2142](https://github.com/OpenFn/lightning/issues/2142)
- Delegate menu customization and create menu components for reuse.
  [#1988](https://github.com/OpenFn/lightning/issues/1988)

### Fixed

- Disable Credential Save Button Until All Form Fields Are Validated
  [#2099](https://github.com/OpenFn/lightning/issues/2099)
- Fix Credential Modal Closure Error When Workflow Is Unsaved
  [#2101](https://github.com/OpenFn/lightning/pull/2101)
- Fix error when socket reconnects and user is viewing a run via the inspector
  [#2148](https://github.com/OpenFn/lightning/issues/2148)

## [v2.5.2] - 2024-05-23

### Fixed

- Preserve custom values (like `apiVersion`) during token refresh for OAuth2
  credentials [#2131](https://github.com/OpenFn/lightning/issues/2131)

## [v2.5.1] - 2024-05-21

### Fixed

- Don't compile Phoenix Storybook in production and test environments
  [#2119](https://github.com/OpenFn/lightning/pull/2119)
- Improve performance and memory consumption on queries and logic for digest
  mailer [#2121](https://github.com/OpenFn/lightning/issues/2121)

## [v2.5.0] - 2024-05-20

### Fixed

- When a refresh token is updated, save it!
  [#2124](https://github.com/OpenFn/lightning/pull/2124)

## [v2.5.0-pre4] - 2024-05-20

### Fixed

- Fix duplicate credential type bug
  [#2100](https://github.com/OpenFn/lightning/issues/2100)
- Ensure Global OAuth Clients Accessibility for All Users
  [#2114](https://github.com/OpenFn/lightning/issues/2114)

## [v2.5.0-pre3] - 2024-05-20

### Fixed

- Fix credential not added automatically after being created from the canvas.
  [#2105](https://github.com/OpenFn/lightning/issues/2105)
- Replace the "not working?" prompt by "All good, but if your credential stops
  working, you may need to re-authorize here.".
  [#2102](https://github.com/OpenFn/lightning/issues/1872)
- Fix Generic Oauth credentials don't get included in the refresh flow
  [#2106](https://github.com/OpenFn/lightning/pull/2106)

## [v2.5.0-pre2] - 2024-05-17

### Changed

- Replace LiveView Dataclip component with React Monaco bringing large
  performance improvements when viewing large dataclips.
  [#1872](https://github.com/OpenFn/lightning/issues/1872)

## [v2.5.0-pre] - 2024-05-17

### Added

- Allow users to build Oauth clients and associated credentials via the user
  interface. [#1919](https://github.com/OpenFn/lightning/issues/1919)

## [v2.4.14] - 2024-05-16

### Changed

- Refactored image and version info
  [#2097](https://github.com/OpenFn/lightning/pull/2097)

### Fixed

- Fixed issue where updating adaptor name and version of job node in the
  workflow canvas crashes the app when no credential is selected
  [#99](https://github.com/OpenFn/lightning/issues/99)
- Removes stacked viewer after switching tabs and steps.
  [#2064](https://github.com/OpenFn/lightning/issues/2064)

## [v2.4.13] - 2024-05-16

### Fixed

- Fixed issue where updating an existing Salesforce credential to use a
  `sandbox` endpoint would not properly re-authenticate.
  [#1842](https://github.com/OpenFn/lightning/issues/1842)
- Navigate directly to settings from url hash and renders default panel when
  there is no hash. [#1971](https://github.com/OpenFn/lightning/issues/1971)

## [v2.4.12] - 2024-05-15

### Fixed

- Fix render settings default panel on first load
  [#1971](https://github.com/OpenFn/lightning/issues/1971)

## [v2.4.11] - 2024-05-15

### Changed

- Upgraded Sentry to v10 for better error reporting.

## [v2.4.10] - 2024-05-14

### Fixed

- Fix the "reset demo" script by disabling the emailing that was introduced to
  the `create_project` function.
  [#2063](https://github.com/OpenFn/lightning/pull/2063)

## [v2.4.9] - 2024-05-14

### Changed

- Bumped @openfn/ws-worker to 1.1.8

### Fixed

- Correctly pass max allowed run time into the Run token, ensuring it's valid
  for the entirety of the Runs execution time
  [#2072](https://github.com/OpenFn/lightning/issues/2072)

## [v2.4.8] - 2024-05-13

### Added

- Add Github sync to usage limiter
  [#2031](https://github.com/OpenFn/lightning/pull/2031)

### Changed

- Remove illogical cancel buttons on user/pass change screen
  [#2067](https://github.com/OpenFn/lightning/issues/2067)

### Fixed

- Stop users from configuring failure alerts when the limiter returns error
  [#2076](https://github.com/OpenFn/lightning/pull/2076)

## [v2.4.7] - 2024-05-11

### Fixed

- Fixed early worker token expiry bug
  [#2070](https://github.com/OpenFn/lightning/issues/2070)

## [v2.4.6] - 2024-05-08

### Added

- Allow for automatic resubmission of failed usage tracking report submissions.
  [1789](https://github.com/OpenFn/lightning/issues/1789)
- Make signup feature configurable
  [#2049](https://github.com/OpenFn/lightning/issues/2049)
- Apply runtime limits to worker execution
  [#2015](https://github.com/OpenFn/lightning/pull/2015)
- Limit usage for failure alerts
  [#2011](https://github.com/OpenFn/lightning/pull/2011)

## [v2.4.5] - 2024-05-07

### Fixed

- Fix provioning API calls workflow limiter without the project ID
  [#2057](https://github.com/OpenFn/lightning/issues/2057)

## [v2.4.4] - 2024-05-03

### Added

- Benchmarking script that simulates data from a cold chain.
  [#1993](https://github.com/OpenFn/lightning/issues/1993)

### Changed

- Changed Snapshot `get_or_create_latest_for` to accept multis allow controlling
  of which repo it uses.
- Require exactly one owner for each project
  [#1991](https://github.com/OpenFn/lightning/issues/1991)

### Fixed

- Fixed issue preventing credential updates
  [#1861](https://github.com/OpenFn/lightning/issues/1861)

## [v2.4.3] - 2024-05-01

### Added

- Allow menu items customization
  [#1988](https://github.com/OpenFn/lightning/issues/1988)
- Workflow Snapshot support
  [#1822](https://github.com/OpenFn/lightning/issues/1822)
- Fix sample workflow from init_project_for_new_user
  [#2016](https://github.com/OpenFn/lightning/issues/2016)

### Changed

- Bumped @openfn/ws-worker to 1.1.6

### Fixed

- Assure workflow is always passed to Run.enqueue
  [#2032](https://github.com/OpenFn/lightning/issues/2032)
- Fix regression on History page where snapshots were not preloaded correctly
  [#2026](https://github.com/OpenFn/lightning/issues/2026)

## [v2.4.2] - 2024-04-24

### Fixed

- Fix missing credential types when running Lightning using Docker
  [#2010](https://github.com/OpenFn/lightning/issues/2010)
- Fix provisioning API includes deleted workflows in project state
  [#2001](https://github.com/OpenFn/lightning/issues/2001)

## [v2.4.1] - 2024-04-19

### Fixed

- Fix github cli deploy action failing to auto-commit
  [#1995](https://github.com/OpenFn/lightning/issues/1995)

## [v2.4.1-pre] - 2024-04-18

### Added

- Add custom metric to track the number of finalised runs.
  [#1790](https://github.com/OpenFn/lightning/issues/1790)

### Changed

- Set better defaults for the GitHub connection creation screen
  [#1994](https://github.com/OpenFn/lightning/issues/1994)
- Update `submission_status` for any Usagetracking.Report that does not have it
  set. [#1789](https://github.com/OpenFn/lightning/issues/1789)

## [v2.4.0] - 2024-04-12

### Added

- Allow description below the page title
  [#1975](https://github.com/OpenFn/lightning/issues/1975)
- Enable users to connect projects to their Github repos and branches that they
  have access to [#1895](https://github.com/OpenFn/lightning/issues/1895)
- Enable users to connect multiple projects to a single Github repo
  [#1811](https://github.com/OpenFn/lightning/issues/1811)

### Changed

- Change all System.get_env calls in runtime.exs to use dotenvy
  [#1968](https://github.com/OpenFn/lightning/issues/1968)
- Track usage tracking submission status in new field
  [#1789](https://github.com/OpenFn/lightning/issues/1789)
- Send richer version info as part of usage tracking submission.
  [#1819](https://github.com/OpenFn/lightning/issues/1819)

### Fixed

- Fix sync to branch only targetting main branch
  [#1892](https://github.com/OpenFn/lightning/issues/1892)
- Fix enqueue run without the workflow info
  [#1981](https://github.com/OpenFn/lightning/issues/1981)

## [v2.3.1] - 2024-04-03

### Changed

- Run the usage tracking submission job more frequently to reduce the risk of
  Oban unavailability at a particular time.
  [#1778](https://github.com/OpenFn/lightning/issues/1778)
- Remove code supporting V1 usage tracking submissions.
  [#1853](https://github.com/OpenFn/lightning/issues/1853)

### Fixed

- Fix scrolling behaviour on inspector for small screens
  [#1962](https://github.com/OpenFn/lightning/issues/1962)
- Fix project picker for users with many projects
  [#1952](https://github.com/OpenFn/lightning/issues/1952)

## [v2.3.0] - 2024-04-02

### Added

- Support for additional paths on a webhook URL such as `/i/<uuid>/Patient`
  [#1954](https://github.com/OpenFn/lightning/issues/1954)
- Support for a GET endpoint to "check" webhook URL availability
  [#1063](https://github.com/OpenFn/lightning/issues/1063)
- Allow external apps to control the run enqueue db transaction
  [#1958](https://github.com/OpenFn/lightning/issues/1958)

## [v2.2.2] - 2024-04-01

### Changed

- Changed dataclip search from string `LIKE` to tsvector on keys and values.
  While this will limit partial string matching to the beginning of words (not
  the middle or end) it will make searching way more performant
  [#1939](https://github.com/OpenFn/lightning/issues/1939)
- Translate job error messages using errors.po file
  [#1935](https://github.com/OpenFn/lightning/issues/1935)
- Improve the UI/UX of the run panel on the inspector for small screens
  [#1909](https://github.com/OpenFn/lightning/issues/1909)

### Fixed

- Regular database timeouts when searching across dataclip bodies
  [#1794](https://github.com/OpenFn/lightning/issues/1794)

## [v2.2.1] - 2024-03-27

### Added

- Enable users to connect to their Github accounts in preparation for
  streamlined GitHub project sync setup
  [#1894](https://github.com/OpenFn/lightning/issues/1894)

### Fixed

- Apply usage limit to bulk-reruns
  [#1931](https://github.com/OpenFn/lightning/issues/1931)
- Fix edge case that could result in duplicate usage tracking submissions.
  [#1853](https://github.com/OpenFn/lightning/issues/1853)
- Fix query timeout issue on history retention deletion
  [#1937](https://github.com/OpenFn/lightning/issues/1937)

## [v2.2.0] - 2024-03-21

### Added

- Allow admins to set project retention periods
  [#1760](https://github.com/OpenFn/lightning/issues/1760)
- Automatically wipe input/output data after their retention period
  [#1762](https://github.com/OpenFn/lightning/issues/1762)
- Automatically delete work order history after their retention period
  [#1761](https://github.com/OpenFn/lightning/issues/1761)

### Changed

- When automatically creating a project for a newly registered user (via the
  `INIT_PROJECT_FOR_NEW_USER=true` environment variable) that user should be the
  `owner` of the project.
  [#1927](https://github.com/OpenFn/lightning/issues/1927)
- Give priority to manual runs (over webhook requests and cron) so that active
  users on the inspector don't have to wait ages for thier work during high load
  periods [#1918](https://github.com/OpenFn/lightning/issues/1918)

## [v2.1.0] - 2024-03-20

### Added

- TSVector index to log_lines, and gin index to dataclips
  [#1898](https://github.com/OpenFn/lightning/issues/1898)
- Add API Version field to Salesforce OAuth credentials
  [#1838](https://github.com/OpenFn/lightning/issues/1838)

### Changed

- Replace v1 usage tracking with v2 usage tracking.
  [#1853](https://github.com/OpenFn/lightning/issues/1853)

## [v2.0.10]

### Changed

- Updated anonymous usage tracker submissions
  [#1853](https://github.com/OpenFn/lightning/issues/1853)

## [v2.0.9] - 2024-03-19

### Added

- Support for smaller screens on history and inspector.
  [#1908](https://github.com/OpenFn/lightning/issues/1908)
- Polling metric to track number of available runs.
  [#1790](https://github.com/OpenFn/lightning/issues/1790)
- Allows limiting creation of new runs and retries.
  [#1754](https://github.com/OpenFn/Lightning/issues/1754)
- Add specific messages for log, input, and output tabs when a run is lost
  [#1757](https://github.com/OpenFn/lightning/issues/1757)
- Soft and hard limits for runs created by webhook trigger.
  [#1859](https://github.com/OpenFn/Lightning/issues/1859)
- Publish an event when a new user is registered
  [#1873](https://github.com/OpenFn/lightning/issues/1873)
- Adds ability to add project collaborators from existing users
  [#1836](https://github.com/OpenFn/lightning/issues/1836)
- Added ability to remove project collaborators
  [#1837](https://github.com/OpenFn/lightning/issues/1837)
- Added new usage tracking submission code.
  [#1853](https://github.com/OpenFn/lightning/issues/1853)

### Changed

- Upgrade Elixir to 1.16.2
- Remove all values from `.env.example`.
  [#1904](https://github.com/OpenFn/lightning/issues/1904)

### Fixed

- Verify only stale project credentials
  [#1861](https://github.com/OpenFn/lightning/issues/1861)

## [v2.0.8] - 2024-02-29

### Fixed

- Show flash error when editing stale project credentials
  [#1795](https://github.com/OpenFn/lightning/issues/1795)
- Fixed bug with Github sync installation on docker-based deployments
  [#1845](https://github.com/OpenFn/lightning/issues/1845)

## [v2.0.6] - 2024-02-29

### Added

- Automatically create Github workflows in a target repository/branch when users
  set up a Github repo::OpenFn project sync
  [#1046](https://github.com/OpenFn/lightning/issues/1046)
- Allows limiting creation of new runs and retries.
  [#1754](https://github.com/OpenFn/Lightning/issues/1754)

### Changed

- Change bucket size used by the run queue delay custom metric.
  [#1790](https://github.com/OpenFn/lightning/issues/1790)
- Require setting `IS_RESETTABLE_DEMO` to "yes" via ENV before allowing the
  destructive `Demo.reset_demo/0` function from being called.
  [#1720](https://github.com/OpenFn/lightning/issues/1720)
- Remove version display condition that was redundant due to shadowing
  [#1819](https://github.com/OpenFn/lightning/issues/1819)

### Fixed

- Fix series of sentry issues related to OAuth credentials
  [#1799](https://github.com/OpenFn/lightning/issues/1799)

## [v2.0.5] - 2024-02-25

### Fixed

- Fixed error in Credentials without `sanbox` field set; only display `sandbox`
  field for Salesforce oauth credentials.
  [#1798](https://github.com/OpenFn/lightning/issues/1798)

## [v2.0.4] - 2024-02-24

### Added

- Display and edit OAuth credentials
  scopes[#1706](https://github.com/OpenFn/Lightning/issues/1706)

### Changed

- Stop sending `operating_system_detail` to the usage tracker
  [#1785](https://github.com/OpenFn/lightning/issues/1785)

### Fixed

- Make handling of usage tracking errors more robust.
  [#1787](https://github.com/OpenFn/lightning/issues/1787)
- Fix inspector shows selected dataclip as wiped after retying workorder from a
  non-first step [#1780](https://github.com/OpenFn/lightning/issues/1780)

## [v2.0.3] - 2024-02-21

### Added

- Actual metrics will now be submitted by Lightning to the Usage Tracker.
  [#1742](https://github.com/OpenFn/lightning/issues/1742)
- Added a support link to the menu that goes to the instance admin contact
  [#1783](https://github.com/OpenFn/lightning/issues/1783)

### Changed

- Usage Tracking submissions are now opt-out, rather than opt-in. Hashed UUIDs
  to ensure anonymity are default.
  [#1742](https://github.com/OpenFn/lightning/issues/1742)
- Usage Tracking submissions will now run daily rather than hourly.
  [#1742](https://github.com/OpenFn/lightning/issues/1742)

- Bumped @openfn/ws-worker to `v1.0` (this is used in dev mode when starting the
  worker from your mix app: `RTM=true iex -S mix phx.server`)
- Bumped @openfn/cli to `v1.0` (this is used for adaptor docs and magic)

### Fixed

- Non-responsive workflow canvas after web socket disconnection
  [#1750](https://github.com/OpenFn/lightning/issues/1750)

## [v2.0.2] - 2024-02-14

### Fixed

- Fixed a bug with the OAuth2 credential refresh flow that prevented
  GoogleSheets jobs from running after token expiration
  [#1735](https://github.com/OpenFn/Lightning/issues/1735)

## [v2.0.1] - 2024-02-13

### Changed

- Renamed ImpactTracking to UsageTracking
  [#1729](https://github.com/OpenFn/lightning/issues/1729)
- Block github installation if there's a pending installation in another project
  [#1731](https://github.com/OpenFn/Lightning/issues/1731)

### Fixed

- Expand work order button balloons randomly
  [#1737](https://github.com/OpenFn/Lightning/issues/1737)
- Editing credentials doesn't work from project scope
  [#1743](https://github.com/OpenFn/Lightning/issues/1743)

## [v2.0.0] - 2024-02-10

> At the time of writing there are no more big changes planned and testing has
> gone well. Thanks to everyone who's helped to kick the tyres during the "rc"
> phase. There are still a _lot of **new features** coming_, so please:
>
> - watch our [**Public Roadmap**](https://github.com/orgs/OpenFn/projects/3) to
>   stay abreast of our core team's backlog,
> - request a feature in the
>   [**Community Forum**](https://community.openfn.org),
> - raise a
>   [**new issue**](https://github.com/OpenFn/lightning/issues/new/choose) if
>   you spot a bug,
> - and head over to the
>   [**Contributing**](https://github.com/OpenFn/lightning/?tab=readme-ov-file#contribute-to-this-project)
>   section to lend a hand.
>
> Head to [**docs.openfn.org**](https://docs.openfn.org) for product
> documentation and help with v1 to v2 migration.

### Changed

- Bump `@openfn/worker` to `v0.8.1`
- Only show GoogleSheets and Salesforce credential options if Oauth clients are
  registered with the instance via ENV
  [#1734](https://github.com/OpenFn/Lightning/issues/1734)

### Fixed

- Use standard table type for webhook auth methods
  [#1514](https://github.com/OpenFn/Lightning/issues/1514)
- Make disabled button for "Connect to GitHub" clear, add tooltip
  [#1732](https://github.com/OpenFn/Lightning/issues/1715)

## [v2.0.0-rc12] - 2024-02-09

### Added

- Add RunQueue extension to allow claim customization.
  [#1715](https://github.com/OpenFn/Lightning/issues/1715)
- Add support for Salesforce OAuth2 credentials
  [#1633](https://github.com/OpenFn/Lightning/issues/1633)

### Changed

- Use `PAYLOAD_SIZE_KB` in k6 load testing script, set thresholds on wait time,
  set default payload size to `2kb`

### Fixed

- Adds more detail to work order states on dashboard
  [#1677](https://github.com/OpenFn/lightning/issues/1677)
- Fix Output & Logs in inspector fails to show sometimes
  [#1702](https://github.com/OpenFn/lightning/issues/1702)

## [v2.0.0-rc11] - 2024-02-08

### Fixed

- Bumped Phoenix LiveView from `0.20.4` to `0.20.5` to fix canvas selection
  issue [#1724](https://github.com/OpenFn/lightning/issues/1724)

## [v2.0.0-rc10] - 2024-02-08

### Changed

- Implemented safeguards to prevent deletion of jobs with associated run history
  [#1570](https://github.com/OpenFn/Lightning/issues/1570)

### Fixed

- Fixed inspector dataclip body not getting updated after dataclip is wiped
  [#1718](https://github.com/OpenFn/Lightning/issues/1718)
- Fixed work orders getting retried despite having wiped dataclips
  [#1721](https://github.com/OpenFn/Lightning/issues/1721)

## [v2.0.0-rc9] 2024-02-05

### Added

- Persist impact tracking configuration and reports
  [#1684](https://github.com/OpenFn/Lightning/issues/1684)
- Add zero-persistence project setting
  [#1209](https://github.com/OpenFn/Lightning/issues/1209)
- Wipe dataclip after use when zero-persistence is enabled
  [#1212](https://github.com/OpenFn/Lightning/issues/1212)
- Show appropriate message when a wiped dataclip is viewed
  [#1211](https://github.com/OpenFn/Lightning/issues/1211)
- Disable selecting work orders having wiped dataclips in the history page
  [#1210](https://github.com/OpenFn/Lightning/issues/1210)
- Hide rerun button in inspector when the selected step has a wiped dataclip
  [#1639](https://github.com/OpenFn/Lightning/issues/1639)
- Add rate limiter to webhook endpoints and runtime limiter for runs.
  [#639](https://github.com/OpenFn/Lightning/issues/639)

### Fixed

- Prevented secret scrubber from over-eagerly adding \*\*\* between all
  characters if an empty string secret was provided as a credential field value
  (e.g., {"username": "come-on-in", "password": ""})
  [#1585](https://github.com/OpenFn/Lightning/issues/1585)
- Fixed permissions issue that allowed viewer/editor to modify webhook auth
  methods. These permissions only belong to project owners and admins
  [#1692](https://github.com/OpenFn/Lightning/issues/1692)
- Fixed bug that was duplicating inbound http_requests, resulting in unnecessary
  data storage [#1695](https://github.com/OpenFn/Lightning/issues/1695)
- Fixed permissions issue that allowed editors to set up new Github connections
  [#1703](https://github.com/OpenFn/Lightning/issues/1703)
- Fixed permissions issue that allowed viewers to initiate syncs to github
  [#1704](https://github.com/OpenFn/Lightning/issues/1704)
- Fixed inspector view stuck at processing when following a crashed run
  [#1711](https://github.com/OpenFn/Lightning/issues/1711)
- Fixed inspector dataclip selector not getting updated after running manual run
  [#1714](https://github.com/OpenFn/Lightning/issues/1714)

## [v2.0.0-rc8] - 2024-01-30

### Added

- Shim code to interact with the Impact Tracking service
  [#1671](https://github.com/OpenFn/Lightning/issues/1671)

### Changed

- Standardized naming of "attempts" to "runs". This had already been done in the
  front-end, but this change cleans up the backend, the database, and the
  interface with the worker. Make sure to **run migrations** and update your
  ENV/secrets to use `WORKER_RUNS_PRIVATE_KEY` rather than
  `WORKER_ATTEMPTS_PRIVATE_KEY`
  [#1657](https://github.com/OpenFn/Lightning/issues/1657)
- Required `@openfn/ws-worker@0.8.0` or above.

## [v2.0.0-rc7] - 2024-01-26

### Added

- Store webhook request headers in Dataclips for use in jobs.
  [#1638](https://github.com/OpenFn/Lightning/issues/1638)

### Changed

- Display `http_request` dataclips to the user as they will be provided to the
  worker as "input" state to avoid confusion while writing jobs.
  [1664](https://github.com/OpenFn/Lightning/issues/1664)
- Named-spaced all worker environment variables with `WORKER_` and added
  documentation for how to configure them.
  [#1672](https://github.com/OpenFn/Lightning/pull/1672)
- Bumped to `@openfn/ws-worker@0.6.0`
- Bumped to `@openfn/cli@0.4.15`

### Fixed

- Fix Run via Docker [#1653](https://github.com/OpenFn/Lightning/issues/1653)
- Fix remaining warnings, enable "warnings as errors"
  [#1642](https://github.com/OpenFn/Lightning/issues/1642)
- Fix workflow dashboard bug when viewed for newly created workflows with only
  unfinished run steps. [#1674](https://github.com/OpenFn/Lightning/issues/1674)

## [v2.0.0-rc5] - 2024-01-22

### Changed

- Made two significant backend changes that don't impact UI/UX but **require
  migrations** and should make Lightning developer lives easier by updating
  parts of the backend to match terms now used in the frontend:
  - Renamed the `Runs` model and table to `Steps`
    [#1571](https://github.com/OpenFn/Lightning/issues/1571)
  - Renamed the `AttemptRuns` model and table to `AttemptSteps`
    [#1571](https://github.com/OpenFn/Lightning/issues/1571)

## [v2.0.0-rc4] - 2024-01-19

### Added

- Scrub output dataclips in the UI to avoid unintentional secret exposure
  [#1606](https://github.com/OpenFn/Lightning/issues/1606)

### Changed

- Bump to `@openfn/cli@0.4.14`
- Do not persist the active tab setting on the job editor
  [#1504](https://github.com/OpenFn/Lightning/issues/1504)
- Make condition label optional
  [#1648](https://github.com/OpenFn/Lightning/issues/1648)

### Fixed

- Fix credential body getting leaked to sentry incase of errors
  [#1600](https://github.com/OpenFn/Lightning/issues/1600)
- Fixed validation on Javascript edge conditions
  [#1602](https://github.com/OpenFn/Lightning/issues/1602)
- Removed unused code from `run_live` directory
  [#1625](https://github.com/OpenFn/Lightning/issues/1625)
- Edge condition expressions not correctly being handled during provisioning
  [#openfn/kit#560](https://github.com/OpenFn/kit/pull/560)

## [v2.0.0-rc3] 2024-01-12

### Added

- Custom metric to track stalled attempts
  [#1559](https://github.com/OpenFn/Lightning/issues/1559)
- Dashboard with project and workflow stats
  [#755](https://github.com/OpenFn/Lightning/issues/755)
- Add search by ID on the history page
  [#1468](https://github.com/OpenFn/Lightning/issues/1468)
- Custom metric to support autoscaling
  [#1607](https://github.com/OpenFn/Lightning/issues/1607)

### Changed

- Bumped CLI version to `0.4.13`
- Bumped worker version to `0.5.0`
- Give project editors and viewers read only access to project settings instead
  [#1477](https://github.com/OpenFn/Lightning/issues/1477)

### Fixed

- Throw an error when Lightning.MetadataService.get_adaptor_path/1 returns an
  adaptor path that is nil
  [#1601](https://github.com/OpenFn/Lightning/issues/1601)
- Fix failure due to creating work order from a newly created job
  [#1572](https://github.com/OpenFn/Lightning/issues/1572)
- Fixes on the dashboard and links
  [#1610](https://github.com/OpenFn/Lightning/issues/1610) and
  [#1608](https://github.com/OpenFn/Lightning/issues/1608)

## [v2.0.0-rc2] - 2024-01-08

### Fixed

- Restored left-alignment for step list items on run detail and inspector
  [a6e4ada](https://github.com/OpenFn/Lightning/commit/a6e4adafd558269cfd690e7c4fdd8f9fe66c5f62)
- Inspector: fixed attempt/run language for "skipped" tooltip
  [fd7dd0c](https://github.com/OpenFn/Lightning/commit/fd7dd0ca8128dfba2902e5aa6a2259e2073f0f10)
- Inspector: fixed failure to save during "save & run" from inspector
  [#1596](https://github.com/OpenFn/Lightning/issues/1596)
- Inspector: fixed key bindings for save & run (retry vs. new work order)
  getting overridden when user focuses on the Monaco editor
  [#1596](https://github.com/OpenFn/Lightning/issues/1596)

## [v2.0.0-rc1] - 2024-01-05

### Why does this repo go from `v0` to `v2.0`?

Lightning is the _2nd version_ of the OpenFn platform. While much of the core
technology is the same, there are breaking changes between `v1.105` (pre-2024)
and `v2` ("OpenFn Lightning").

For customers using OpenFn `v1`, a migration guide will be provided at
[docs.openfn.org](https://docs.openfn.org)

### Added

- Link to the job inspctor for a selected run from the history interface
  [#1524](https://github.com/OpenFn/Lightning/issues/1524)
- Reprocess an existing work order from the job inspector by default (instead of
  always creating a new work order)
  [#1524](https://github.com/OpenFn/Lightning/issues/1524)
- Bumped worker to support edge conditions between trigger and first job
  `"@openfn/ws-worker": "^0.4.0"`

### Changed

- Updated naming to prepare for v2 release
  [#1248](https://github.com/OpenFn/Lightning/issues/1248); the major change is
  that each time a work order (the typical unit of business value for an
  organization, e.g. "execute workflow ABC for patient 123") is executed, it is
  called a "run". Previously, it was called an "attempt". The hierarchy is now:

  ```
  Build-Time: Projects > Workflows > Steps
  Run-Time: Work Orders > Runs > Steps
  ```

  Note the name changes here are reflected in the UI, but not all tables/models
  will be changed until [1571](https://github.com/OpenFn/Lightning/issues/1571)
  is delivered.

## [v0.12.2] - 2023-12-24

### Changed

- Bumped worker to address occasional git install issue
  `"@openfn/ws-worker": "^0.3.2"`

### Fixed

- Fix RuntimeError: found duplicate ID "google-sheets-inner-form" for
  GoogleSheetsComponent [#1578](https://github.com/OpenFn/Lightning/issues/1578)
- Extend export script to include new JS expression edge type
  [#1540](https://github.com/OpenFn/Lightning/issues/1540)
- Fix regression for attempt viewer log line highlighting
  [#1589](https://github.com/OpenFn/Lightning/issues/1589)

## [v0.12.1] - 2023-12-21

### Changed

- Hide project security setting tab from non-authorized users
  [#1477](https://github.com/OpenFn/Lightning/issues/1477)

### Fixed

- History page crashes if job is removed from workflow after it's been run
  [#1568](https://github.com/OpenFn/Lightning/issues/1568)

## [v0.12.0] - 2023-12-15

### Added

- Add ellipsis for long job names on the canvas
  [#1217](https://github.com/OpenFn/Lightning/issues/1217)
- Fix Credential Creation Page UI
  [#1064](https://github.com/OpenFn/Lightning/issues/1064)
- Custom metric to track Attempt queue delay
  [#1556](https://github.com/OpenFn/Lightning/issues/1556)
- Expand work order row when a `workorder_id` is specified in the filter
  [#1515](https://github.com/OpenFn/Lightning/issues/1515)
- Allow Javascript expressions as conditions for edges
  [#1498](https://github.com/OpenFn/Lightning/issues/1498)

### Changed

- Derive dataclip in inspector from the attempt & step
  [#1551](https://github.com/OpenFn/Lightning/issues/1551)
- Updated CLI to 0.4.10 (fixes logging)
- Changed UserBackupToken model to use UTC timestamps (6563cb77)
- Restore FK relationship between `work_orders` and `attempts` pending a
  decision re: further partitioning.
  [#1254](https://github.com/OpenFn/Lightning/issues/1254)

### Fixed

- New credential doesn't appear in inspector until refresh
  [#1531](https://github.com/OpenFn/Lightning/issues/1531)
- Metadata not refreshing when credential is updated
  [#791](https://github.com/OpenFn/Lightning/issues/791)
- Adjusted z-index for Monaco Editor's sibling element to resolve layout
  conflict [#1329](https://github.com/OpenFn/Lightning/issues/1329)
- Demo script sets up example Runs with their log lines in a consistant order.
  [#1487](https://github.com/OpenFn/Lightning/issues/1487)
- Initial credential creation `changes` show `after` as `null` rather a value
  [#1118](https://github.com/OpenFn/Lightning/issues/1118)
- AttemptViewer flashing/rerendering when Jobs are running
  [#1550](https://github.com/OpenFn/Lightning/issues/1550)
- Not able to create a new Job when clicking the Check icon on the placeholder
  [#1537](https://github.com/OpenFn/Lightning/issues/1537)
- Improve selection logic on WorkflowDiagram
  [#1220](https://github.com/OpenFn/Lightning/issues/1220)

## [v0.11.0] - 2023-12-06

### Added

- Improved UI when manually creating Attempts via the Job Editor
  [#1474](https://github.com/OpenFn/Lightning/issues/1474)
- Increased the maximum inbound webhook request size to 10MB and added
  protection against _very large_ payloads with a 100MB "max_skip_body_length"
  [#1247](https://github.com/OpenFn/Lightning/issues/1247)

### Changed

- Use the internal port of the web container for the worker configuration in
  docker-compose setup. [#1485](https://github.com/OpenFn/Lightning/pull/1485)

## [v0.10.6] - 2023-12-05

### Changed

- Limit entries count on term work orders search
  [#1461](https://github.com/OpenFn/Lightning/issues/1461)
- Scrub log lines using multiple credentials samples
  [#1519](https://github.com/OpenFn/Lightning/issues/1519)
- Remove custom telemetry plumbing.
  [1259](https://github.com/OpenFn/Lightning/issues/1259)
- Enhance UX to prevent modal closure when Monaco/Dataclip editor is focused
  [#1510](https://github.com/OpenFn/Lightning/pull/1510)

### Fixed

- Use checkbox on boolean credential fields rather than a text input field
  [#1430](https://github.com/OpenFn/Lightning/issues/1430)
- Allow users to retry work orders that failed before their first run was
  created [#1417](https://github.com/OpenFn/Lightning/issues/1417)
- Fix to ensure webhook auth modal is closed when cancel or close are selected.
  [#1508](https://github.com/OpenFn/Lightning/issues/1508)
- Enable user to reauthorize and obtain a new refresh token.
  [#1495](https://github.com/OpenFn/Lightning/issues/1495)
- Save credential body with types declared on schema
  [#1518](https://github.com/OpenFn/Lightning/issues/1518)

## [v0.10.5] - 2023-12-03

### Changed

- Only add history page filters when needed for simpler multi-select status
  interface and shorter page URLs
  [#1331](https://github.com/OpenFn/Lightning/issues/1331)
- Use dynamic Endpoint config only on prod
  [#1435](https://github.com/OpenFn/Lightning/issues/1435)
- Validate schema field with any of expected values
  [#1502](https://github.com/OpenFn/Lightning/issues/1502)

### Fixed

- Fix for liveview crash when token expires or gets deleted after mount
  [#1318](https://github.com/OpenFn/Lightning/issues/1318)
- Remove two obsolete methods related to Run: `Lightning.Invocation.delete_run`
  and `Lightning.Invocation.Run.new_from`.
  [#1254](https://github.com/OpenFn/Lightning/issues/1254)
- Remove obsolete field `previous_id` from `runs` table.
  [#1254](https://github.com/OpenFn/Lightning/issues/1254)
- Fix for missing data in 'created' audit trail events for webhook auth methods
  [#1500](https://github.com/OpenFn/Lightning/issues/1500)

## [v0.10.4] - 2023-11-30

### Changed

- Increased History search timeout to 30s
  [#1461](https://github.com/OpenFn/Lightning/issues/1461)

### Fixed

- Tooltip text clears later than the background
  [#1094](https://github.com/OpenFn/Lightning/issues/1094)
- Temporary fix to superuser UI for managing project users
  [#1145](https://github.com/OpenFn/Lightning/issues/1145)
- Fix for adding ellipses on credential info on job editor heading
  [#1428](https://github.com/OpenFn/Lightning/issues/1428)

## [v0.10.3] - 2023-11-28

### Added

- Dimmed/greyed out triggers and edges on the canvas when they are disabled
  [#1464](https://github.com/OpenFn/Lightning/issues/1464)
- Async loading on the history page to improve UX on long DB queries
  [#1279](https://github.com/OpenFn/Lightning/issues/1279)
- Audit trail events for webhook auth (deletion method) change
  [#1165](https://github.com/OpenFn/Lightning/issues/1165)

### Changed

- Sort project collaborators by first name
  [#1326](https://github.com/OpenFn/Lightning/issues/1326)
- Work orders will now be set in a "pending" state when retries are enqueued.
  [#1340](https://github.com/OpenFn/Lightning/issues/1340)
- Avoid printing 2FA codes by default
  [#1322](https://github.com/OpenFn/Lightning/issues/1322)

### Fixed

- Create new workflow button sizing regression
  [#1405](https://github.com/OpenFn/Lightning/issues/1405)
- Google credential creation and automatic closing of oAuth tab
  [#1109](https://github.com/OpenFn/Lightning/issues/1109)
- Exporting project breaks the navigation of the page
  [#1440](https://github.com/OpenFn/Lightning/issues/1440)

## [v0.10.2] - 2023-11-21

### Changed

- Added `max_frame_size` to the Cowboy websockets protocol options in an attempt
  to address [#1421](https://github.com/OpenFn/Lightning/issues/1421)

## [v0.10.1] - 2023-11-21

### Fixed

- Work Order ID was not displayed properly in history page
  [#1423](https://github.com/OpenFn/Lightning/issues/1423)

## [v0.10.0] - 2023-11-21

### 🚨 Breaking change warning! 🚨

This release will contain breaking changes as we've significantly improved both
the workflow building and execution systems.

#### Nodes and edges

Before, workflows were represented as a list of jobs and triggers. For greater
flexibility and control of complex workflows, we've moved towards a more robust
"nodes and edges" approach. Where jobs in a workflow (a node) can be connected
by edges.

Triggers still exist, but live "outside" the directed acyclic graph (DAG) and
are used to automatically create work orders and attempts.

We've provided migrations that bring `v0.9.3` workflows in line with the
`v0.10.0` requirements.

#### Scalable workers

Before, Lightning spawned child processes to execute attempts in sand-boxed
NodeVMs on the same server. This created inefficiencies and security
vulnerabilities. Now, the Lightning web server adds attempts to a queue and
multiple worker applications can pull from that queue to process work.

In dev mode, this all happens automatically and on one machine, but in most
high-availability production environments the workers will be on another server.

Attempts are now handled entirely by the workers, and they report back to
Lightning. Exit reasons, final attempt states, error types and error messages
are either entirely new or handled differently now, but we have provided
migration scripts that will work to bring _most_ `v0.9.3` runs, attempts, and
work orders up to `v0.10.0`, though the granularity of `v0.9.3` states and exits
will be less than `v0.10.0` and the final states are not guaranteed to be
accurate for workflows with multiple branches and leaf nodes with varying exit
reasons.

The migration scripts can be run with a single function call in SetupUtils from
a connect `iex` session:

```
Lightning.SetupUtils.approximate_state_for_attempts_and_workorders()
```

Note that (like lots of _other_ functionality in `SetupUtils`, calling this
function is a destructive action and you should only do it if you've backed up
your data and you know what you're doing.)

As always, we recommend backing up your data before migrating. (And thanks for
bearing with us as we move towards our first stable Lightning release.)

### Added

- Fix flaky job name input behavior on error
  [#1218](https://github.com/OpenFn/Lightning/issues/1218)
- Added a hover effect on copy and add button for adaptors examples
  [#1297](https://github.com/OpenFn/Lightning/issues/1297)
- Migration helper code to move from `v0.9.3` to `v0.10.0` added to SetupUtils
  [#1363](https://github.com/OpenFn/Lightning/issues/1363)
- Option to start with `RTM=false iex -S mix phx.server` for opting out of the
  dev-mode automatic runtime manager.
- Webhook Authentication Methods database and CRUD operations
  [#1152](https://github.com/OpenFn/Lightning/issues/1152)
- Creation and Edit of webhook webhook authentication methods UI
  [#1149](https://github.com/OpenFn/Lightning/issues/1149)
- Add webhook authentication methods overview methods in the canvas
  [#1153](https://github.com/OpenFn/Lightning/issues/1153)
- Add icon on the canvas for triggers that have authentication enabled
  [#1157](https://github.com/OpenFn/Lightning/issues/1157)
- Require password/2FA code before showing password and API Key for webhook auth
  methods [#1200](https://github.com/OpenFn/Lightning/issues/1200)
- Restrict live dashboard access to only superusers, enable DB information and
  OS information [#1170](https://github.com/OpenFn/Lightning/issues/1170) OS
  information [#1170](https://github.com/OpenFn/Lightning/issues/1170)
- Expose additional metrics to LiveDashboard
  [#1171](https://github.com/OpenFn/Lightning/issues/1171)
- Add plumbing to dump Lightning metrics during load testing
  [#1178](https://github.com/OpenFn/Lightning/issues/1178)
- Allow for heavier payloads during load testing
  [#1179](https://github.com/OpenFn/Lightning/issues/1179)
- Add dynamic delay to help mitigate flickering test
  [#1195](https://github.com/OpenFn/Lightning/issues/1195)
- Add a OpenTelemetry trace example
  [#1189](https://github.com/OpenFn/Lightning/issues/1189)
- Add plumbing to support the use of PromEx
  [#1199](https://github.com/OpenFn/Lightning/issues/1199)
- Add warning text to PromEx config
  [#1222](https://github.com/OpenFn/Lightning/issues/1222)
- Track and filter on webhook controller state in :telemetry metrics
  [#1192](https://github.com/OpenFn/Lightning/issues/1192)
- Secure PromEx metrics endpoint by default
  [#1223](https://github.com/OpenFn/Lightning/issues/1223)
- Partition `log_lines` table based on `attempt_id`
  [#1254](https://github.com/OpenFn/Lightning/issues/1254)
- Remove foreign key from `attempts` in preparation for partitioning
  `work_orders` [#1254](https://github.com/OpenFn/Lightning/issues/1254)
- Remove `Workflows.delete_workflow`. It is no longer in use and would require
  modification to not leave orphaned attempts given the removal of the foreign
  key from `attempts`. [#1254](https://github.com/OpenFn/Lightning/issues/1254)
- Show tooltip for cloned runs in history page
  [#1327](https://github.com/OpenFn/Lightning/issues/1327)
- Have user create workflow name before moving to the canvas
  [#1103](https://github.com/OpenFn/Lightning/issues/1103)
- Allow PromEx authorization to be disabled
  [#1483](https://github.com/OpenFn/Lightning/issues/1483)

### Changed

- Updated vulnerable JS libraries, `postcss` and `semver`
  [#1176](https://github.com/OpenFn/Lightning/issues/1176)
- Update "Delete" to "Delete Job" on Job panel and include javascript deletion
  confirmation [#1105](https://github.com/OpenFn/Lightning/issues/1105)
- Move "Enabled" property from "Jobs" to "Edges"
  [#895](https://github.com/OpenFn/Lightning/issues/895)
- Incorrect wording on the "Delete" tooltip
  [#1313](https://github.com/OpenFn/Lightning/issues/1313)

### Fixed

- Fixed janitor lost query calculation
  [#1400](https://github.com/OpenFn/Lightning/issues/1400)
- Adaptor icons load gracefully
  [#1140](https://github.com/OpenFn/Lightning/issues/1140)
- Selected dataclip gets lost when starting a manual work order from the
  inspector interface [#1283](https://github.com/OpenFn/Lightning/issues/1283)
- Ensure that the whole edge when selected is highlighted
  [#1160](https://github.com/OpenFn/Lightning/issues/1160)
- Fix "Reconfigure Github" button in Project Settings
  [#1386](https://github.com/OpenFn/Lightning/issues/1386)
- Make janitor also clean up runs inside an attempt
  [#1348](https://github.com/OpenFn/Lightning/issues/1348)
- Modify CompleteRun to return error changeset when run not found
  [#1393](https://github.com/OpenFn/Lightning/issues/1393)
- Drop invocation reasons from DB
  [#1412](https://github.com/OpenFn/Lightning/issues/1412)
- Fix inconsistency in ordering of child nodes in the workflow diagram
  [#1406](https://github.com/OpenFn/Lightning/issues/1406)

## [v0.9.3] - 2023-09-27

### Added

- Add ellipsis when adaptor name is longer than the container allows
  [#1095](https://github.com/OpenFn/Lightning/issues/1095)
- Webhook Authentication Methods database and CRUD operations
  [#1152](https://github.com/OpenFn/Lightning/issues/1152)

### Changed

- Prevent deletion of first job of a workflow
  [#1097](https://github.com/OpenFn/Lightning/issues/1097)

### Fixed

- Fix long name on workflow cards
  [#1102](https://github.com/OpenFn/Lightning/issues/1102)
- Fix highlighted Edge can get out of sync with selected Edge
  [#1099](https://github.com/OpenFn/Lightning/issues/1099)
- Creating a new user without a password fails and there is no user feedback
  [#731](https://github.com/OpenFn/Lightning/issues/731)
- Crash when setting up version control
  [#1112](https://github.com/OpenFn/Lightning/issues/1112)

## [v0.9.2] - 2023-09-20

### Added

- Add "esc" key binding to close job inspector modal
  [#1069](https://github.com/OpenFn/Lightning/issues/1069)

### Changed

- Save icons from the `adaptors` repo locally and load them in the job editor
  [#943](https://github.com/OpenFn/Lightning/issues/943)

## [v0.9.1] - 2023-09-19

### Changed

- Modified audit trail to handle lots of different kind of audit events
  [#271](https://github.com/OpenFn/Lightning/issues/271)/[#44](https://github.com/OpenFn/Lightning/issues/44)
- Fix randomly unresponsive job panel after job deletion
  [#1113](https://github.com/OpenFn/Lightning/issues/1113)

## [v0.9.0] - 2023-09-15

### Added

- Add favicons [#1079](https://github.com/OpenFn/Lightning/issues/1079)
- Validate job name in placeholder job node
  [#1021](https://github.com/OpenFn/Lightning/issues/1021)
- Bring credential delete in line with new GDPR interpretation
  [#802](https://github.com/OpenFn/Lightning/issues/802)
- Make job names unique per workflow
  [#1053](https://github.com/OpenFn/Lightning/issues/1053)

### Changed

- Enhanced the job editor/inspector interface
  [#1025](https://github.com/OpenFn/Lightning/issues/1025)

### Fixed

- Finished run never appears in inspector when it fails
  [#1084](https://github.com/OpenFn/Lightning/issues/1084)
- Cannot delete some credentials via web UI
  [#1072](https://github.com/OpenFn/Lightning/issues/1072)
- Stopped the History table from jumping when re-running a job
  [#1100](https://github.com/OpenFn/Lightning/issues/1100)
- Fixed the "+" button when adding a job to a workflow
  [#1093](https://github.com/OpenFn/Lightning/issues/1093)

## [v0.8.3] - 2023-09-05

### Added

- Render error when workflow diagram node is invalid
  [#956](https://github.com/OpenFn/Lightning/issues/956)

### Changed

- Restyle history table [#1029](https://github.com/OpenFn/Lightning/issues/1029)
- Moved Filter and Search controls to the top of the history page
  [#1027](https://github.com/OpenFn/Lightning/issues/1027)

### Fixed

- Output incorrectly shows "this run failed" when the run hasn't yet finished
  [#1048](https://github.com/OpenFn/Lightning/issues/1048)
- Wrong label for workflow card timestamp
  [#1022](https://github.com/OpenFn/Lightning/issues/1022)

## [v0.8.2] - 2023-08-31

### Fixed

- Lack of differentiation between top of job editor modal and top menu was
  disorienting. Added shadow.

## [v0.8.1] - 2023-08-31

### Changed

- Moved Save and Run button to bottom of the Job edit modal
  [#1026](https://github.com/OpenFn/Lightning/issues/1026)
- Allow a manual work order to save the workflow before creating the work order
  [#959](https://github.com/OpenFn/Lightning/issues/959)

## [v0.8.0] - 2023-08-31

### Added

- Introduces Github sync feature, users can now setup our github app on their
  instance and sync projects using our latest portability spec
  [#970](https://github.com/OpenFn/Lightning/issues/970)
- Support Backup Codes for Multi-Factor Authentication
  [937](https://github.com/OpenFn/Lightning/issues/937)
- Log a warning in the console when the Editor/docs component is given latest
  [#958](https://github.com/OpenFn/Lightning/issues/958)
- Improve feedback when a Workflow name is invalid
  [#961](https://github.com/OpenFn/Lightning/issues/961)
- Show that the jobs' body is invalid
  [#957](https://github.com/OpenFn/Lightning/issues/957)
- Reimplement skipped CredentialLive tests
  [#962](https://github.com/OpenFn/Lightning/issues/962)
- Reimplement skipped WorkflowLive.IndexTest test
  [#964](https://github.com/OpenFn/Lightning/issues/964)
- Show GitHub installation ID and repo link to help setup/debugging for version
  control [1059](https://github.com/OpenFn/Lightning/issues/1059)

### Fixed

- Fixed issue where job names were being incorrectly hyphenated during
  project.yaml export [#1050](https://github.com/OpenFn/Lightning/issues/1050)
- Allows the demo script to set a project id during creation to help with cli
  deploy/pull/Github integration testing.
- Fixed demo project_repo_connection failing after nightly demo resets
  [1058](https://github.com/OpenFn/Lightning/issues/1058)
- Fixed an issue where the monaco suggestion tooltip was offset from the main
  editor [1030](https://github.com/OpenFn/Lightning/issues/1030)

## [v0.7.3] - 2023-08-15

### Changed

- Version control in project settings is now named Export your project
  [#1015](https://github.com/OpenFn/Lightning/issues/1015)

### Fixed

- Tooltip for credential select in Job Edit form is cut off
  [#972](https://github.com/OpenFn/Lightning/issues/972)
- Dataclip type and state assembly notice for creating new dataclip dropped
  during refactor [#975](https://github.com/OpenFn/Lightning/issues/975)

## [v0.7.2] - 2023-08-10

### Changed

- NodeJs security patch [1009](https://github.com/OpenFn/Lightning/pull/1009)

### Fixed

## [v0.7.1] - 2023-08-04

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

### Changed

- Unless otherwise specified, only show work orders with activity in last 14
  days [#968](https://github.com/OpenFn/Lightning/issues/968)

## [v0.7.0-pre4] - 2023-07-27

### Changed

- Don't add cast fragments if the search_term is nil
  [#968](https://github.com/OpenFn/Lightning/issues/968)

## [v0.7.0-pre3] - 2023-07-26

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
  [793](https://github.com/OpenFn/Lightning/issues/793)

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

- Ability to rerun work orders from start by selecting one of more of them from
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
- Change Work Order filters to apply to the aggregate state of the work order
  and not the run directly
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

- Fixed bug that tried to execute HTML scripts in dataclips
- Fixed bug that prevented work orders from displaying in the order of their
  last run, descending.
- Remove alerts after set timeout or close

## [0.3.0] - 2022-11-21

### Added

- Add seed data for demo site
- Create adaptor credentials through a form
- Configure cron expressions through a form
- View runs grouped by work orders and attempts
- Run an existing Job with any dataclip uuid from the Job form

### Changed

- Redirect users to projects list page when they click on Admin Settings menu
- Move job, project, input and output Dataclips to Run table
- Reverse the relationship between Jobs and Triggers. Triggers now can exist on
  their own; setting the stage for branching and merging workflows
- Updated Elixir and frontend dependencies
- [BREAKING CHANGE] Pipeline now uses Work Orders, previous data is not
  compatible.
- Runs, Dataclips and Attempts now all correctly use `usec` resolution
  timestamps.
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
- Allow admin users to create or disable a user's account
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
