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

### Changed

### Fixed

- Removes stacked viewer after switching tabs and steps.
  [#2064](https://github.com/OpenFn/lightning/issues/2064)

## [v2.4.13] - 2024-05-16

### Fixed

- Fixed issue where updating an existing Salesforce credential to use a
  `sandbox` endpoint would not properly re-authenticate.
  [#1842](https://github.com/OpenFn/lightning/issues/1842)
- Navigate directly to settings from url hash and renders default panel 
  when there is no hash. 
  [#1971](https://github.com/OpenFn/lightning/issues/1971)

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

## [2.0.0-rc2] - 2024-01-08

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

## [2.0.0-rc1] - 2024-01-05

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
