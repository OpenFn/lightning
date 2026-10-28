---
paths:
  - "lib/lightning/policies/**"
  - "lib/lightning/scope.ex"
  - "lib/lightning/actor.ex"
---

# Policies, Scope and Actor

Statuses and controllers follow `.claude/rules/api.md`.

## The Scope and the Actor

- `Lightning.Scope` describes the caller: its actor, token grants, instance role, MFA status and whether it may own credentials, plus, once a project is named, its role there, support access and whether the project is scheduled for deletion.
- A Scope neither authenticates the caller nor decides what it may do, with two exceptions in `Scope.fetch/2`. It refuses a repo connection any project but its own with `{:error, :no_standing}`, before reading any other fact. And an id that names no project is `{:error, :no_such_project}` only to a caller with instance-wide project access (`Scope.operator?/1` or the `:superuser` instance role); to anyone else it is `{:error, :no_standing}`, the same answer as a project they can't see. `LightningWeb.API.FallbackController` answers its errors. A fetched project is not permission; the policy judges the facts.
- Only `actor` is required. `grants`, `mfa_satisfied?` and `can_own_credentials?` default to refusing, so a Scope built by hand rather than through `Scope.new/1` fails closed.
- `Lightning.Actor` is a user or the service account, whoever a write records in the audit trail. A Scope's `actor` can also be a repo connection, which is not a `Lightning.Actor`.

## Who the callers are

- A person holds every token grant; a superuser has the `:superuser` instance role. A repo connection holds only `projects:provision`. The service account holds the grants its token carries, with the `:operator` instance role.
- `:operator` counts as holding every project role, so the service account passes `Scope.holds_role?/2` and `Scope.has_standing?/1`. An action for people only must refuse it in the rule, as `Lightning.Policies.Credentials` refuses `:delete_credential`.

## What a policy supplies

- Per action, a policy supplies the token grant it needs (for a resource, its write grant, such as `projects:write`) and a rule over Scope facts. `Lightning.Policies.Decision` owns the rest, so a rule doesn't check MFA, project deletion or token grants.
- `Decision.project/4` decides actions on a project in this order: the token grant; `false` for a subject the Scope doesn't describe (`Scope.describes?/2`); `{:error, :no_standing}` when the rule refuses and the caller has no standing; MFA; the rule; scheduled deletion. `Decision.instance/4`, for actions with no project, checks only the token grant, then the rule.
- A rule refuses a caller who may not learn that a record exists with `{:error, :no_standing}`, as `:see_credential` does, and one who sees it but may not act with `false`. The API answers the first with 403 `forbidden` whether or not the record exists, so an action on a record that isn't on a project route needs a see action like this.
- A `:before_target` subject, which `AuthorizeAction` sends, stops after the grant check, so `true` for it is not permission.
- `Lightning.Policies.Provisioning` can't name one grant up front: creating needs `projects:write` and provisioning an existing project needs `projects:provision`, so its `:before_target` check accepts either, and `Decision` checks the one that applies once the body is read.

## Moving a `%User{}` policy onto `%Scope{}`

- Three steps; `Lightning.Policies.Collections` shows the result:
  1. Add one `%Scope{}` clause calling `Decision.project/4` (or `Decision.instance/4`) with the token grant and the rule's answer.
  2. Turn the old clauses into a private rule reading only Scope facts, such as `Scope.has_standing?/1`, and drop its MFA, deletion and grant checks.
  3. Keep a catch-all clause through `Permissions.for_actor/3`, so callers handing in a user still get a yes or no.
- For tests, copy the `ProjectUsers` permission tests and the `Decision` tests.
