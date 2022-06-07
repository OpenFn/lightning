# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.6] - 2022-06-03

### Added

- Register, log in and log out of an account
- Allow superusers and admin users to create projects
- Allow admin users to create or disable a user’s account 
- Allow superusers for local deployments to create users and give them access to project spaces

- Create and edit a job with a webhook, flow/fail or cron trigger
- Create and edit credentials for a job
- Copy a job’s webhook URL
- View all workflows in a project visually
- Deploy lightning locally with Docker 

- Enable a job to automatically process incoming requests
- Run a job with a webhook or flow/fail trigger
- View job runs along with their logs, exit code, start and end time
- View data clips that have initiated a job run (http requests for webhooks, run results for flow/fail jobs)

### Changed

- Sorting runs and dataclips by inserted_at, desc

### Removed

- Nothing at all!
