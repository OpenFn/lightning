# Reporting of Security Vulnerabilities

If you discover a security vulnerability in OpenFn software or services, we'd
appreciate a non-public disclosure.

The OpenFn team can be contacted privately by creating a new
**[Security Advisory on GitHub](https://github.com/OpenFn/lightning/security/advisories/new)**
(preferred) or via [security@openfn.org](mailto:security@openfn.org).

If the issue affects a repository other than Lightning (e.g. an adaptor or the
CLI), please open the Security Advisory on that repository, or use the email
address above if you're unsure where it belongs.

Disclosure will be coordinated with affected users and, where relevant, with
organizations running their own OpenFn deployments.

(The [issue tracker](https://github.com/OpenFn/lightning/issues) and
[community forum](https://community.openfn.org) are fully public. Please do not
report security vulnerabilities there.)

# Scope

Reports are welcome for:

- **OpenFn Lightning** and other open source repositories under the
  [OpenFn GitHub organization](https://github.com/OpenFn), including adaptors
  and developer tooling.
- **The hosted OpenFn platform** at app.openfn.org. Please limit any testing of
  the hosted service to accounts and data you own, and never attempt to access,
  modify, or exfiltrate other users' data.

# Requirements for a Valid Report

- Please ensure the issue is reproducible on `main` or on the latest public tag.
- Please provide a fully working, end-to-end proof of concept.
- Please ensure the proof of concept is real-world and not simulated or
  abstracted.
- Please ensure the proof of concept demonstrably violates a security boundary.
- Please understand that the team maintaining this digital public good is small
  and manages a broad portfolio of repositories and services. While we will try
  to triage and fix issues in a timely manner, we cannot guarantee a fixed
  timeline for resolution.
- We are an open source project and gain little from stonewalling researchers,
  so we kindly ask that reporters do not publicly disclose issues they have
  reported to us before an agreed-to disclosure date.
