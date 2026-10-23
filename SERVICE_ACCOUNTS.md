# Service accounts

A service account lets a program set up a Lightning instance through its API,
signing in with a key pair instead of a password. Use one when infrastructure
automation, rather than a person, creates the instance's users, including its
first superuser.

Each instance has at most one service account. It can create, change and find
users, and create, change and read projects, collections and credentials.

> #### Still under development {: .warning}
>
> Service accounts may change. The API is limited right now and will cover more
> of Lightning over time.

## Set up a service account

Generate an RSA key pair, then give Lightning the public key as
`SERVICE_ACCOUNT_PUBLIC_KEY`, base64 encoded on a single line. Set it wherever
you set Lightning's other environment variables (see
[Deployment](DEPLOYMENT.md)):

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out service-account.key
openssl pkey -in service-account.key -pubout -out service-account.pub

export SERVICE_ACCOUNT_PUBLIC_KEY=$(openssl base64 -A -in service-account.pub)
```

Keep the private key with your automation. Only the public key goes to
Lightning. It must be RSA and at least 2048 bits, and Lightning won't start if
it isn't.

While `SERVICE_ACCOUNT_PUBLIC_KEY` is set, first setup is turned off, so nobody
who finds a fresh instance can claim it before your automation does. Once your
automation has an access token, it creates the first superuser through the API,
as shown in [Manage users](#manage-users).

## Get an access token

Sign a short-lived assertion with the private key and trade it at the token
endpoint for an access token that lasts five minutes. This is OAuth 2.0's client
credentials grant with `private_key_jwt` client authentication
([RFC 7523](https://www.rfc-editor.org/rfc/rfc7523#section-2.2)), so an OAuth
client library that supports those can do it for you. The instance describes the
exchange at `/.well-known/oauth-authorization-server`.

In Node.js, with no extra packages:

```js
import {
  createHash,
  createPrivateKey,
  createPublicKey,
  randomUUID,
  sign,
} from 'node:crypto';
import { readFileSync } from 'node:fs';

const lightning = 'https://lightning.example.org';
const key = createPrivateKey(readFileSync('service-account.key'));

const { token_endpoint } = await fetch(
  `${lightning}/.well-known/oauth-authorization-server`
).then(response => response.json());

const { e, kty, n } = createPublicKey(key).export({ format: 'jwk' });
const id = createHash('sha256')
  .update(JSON.stringify({ e, kty, n }))
  .digest('base64url');

const encode = value =>
  Buffer.from(JSON.stringify(value)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const claims = {
  iss: id,
  sub: id,
  aud: token_endpoint,
  iat: now,
  exp: now + 60,
  jti: randomUUID(),
};
const unsigned = `${encode({ alg: 'RS256' })}.${encode(claims)}`;
const signature = sign('sha256', Buffer.from(unsigned), key).toString(
  'base64url'
);

const { access_token } = await fetch(token_endpoint, {
  method: 'POST',
  body: new URLSearchParams({
    grant_type: 'client_credentials',
    client_assertion_type:
      'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',
    client_assertion: `${unsigned}.${signature}`,
    scope: 'users:read users:write',
  }),
}).then(response => response.json());
```

A few things to get right in the assertion:

- `iss` and `sub` are both the service account's id. That is the public key's
  `e`, `kty` and `n` written as JSON in that order with no spaces, hashed with
  SHA-256 and base64url encoded (an
  [RFC 7638](https://www.rfc-editor.org/rfc/rfc7638) thumbprint). The example
  works it out for you.
- `aud` is the token endpoint exactly as the metadata gives it. Lightning builds
  that URL from `URL_HOST`, `URL_SCHEME` and `URL_PORT`. If those don't match
  the address your automation calls, Lightning refuses the assertion.
- `exp` can be at most 60 seconds after `iat`.
- Each assertion works once, so give every one a new `jti` and sign a new one
  for each token. There is no refresh token.

Send the token request form encoded (`application/x-www-form-urlencoded`).
Lightning refuses a JSON body.

If the token endpoint answers `invalid_client`, Lightning's logs say why. See
[Logs](#logs).

## What the token can do

Send the access token as `Authorization: Bearer <token>`. What it may do depends
on the scopes it carries:

- `users:read` finds users, and `users:write` creates and changes them.
- `projects:write` reads, creates and changes projects.
- `collections:write` reads, creates and renames collections.
- `credentials:write` reads, creates and replaces credentials.

Ask for the scopes you need with the `scope` parameter when you request the
token. Projects, collections and credentials have no read scopes: their `GET`
routes need the same `:write` scope as their `PUT` routes.

The service account acts on every project, as if it held every project role,
owner included, but only as far as its token's scopes reach. It is never a
member of a project and never shows in a project's members.

## Manage users

Creating and changing users needs the `users:write` scope, and finding them
needs `users:read`.

Create a user, here a superuser whose email is already verified. `role` is
`user` or `superuser`, and defaults to `user`:

```bash
curl -X POST https://lightning.example.org/api/users \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "ada@example.com",
    "password": "correct horse battery",
    "first_name": "Ada",
    "last_name": "Lovelace",
    "role": "superuser",
    "confirmed": true
  }'
```

Lightning answers 201 with the new user. Its `id` is what you use to change the
user later:

```json
{
  "data": {
    "type": "users",
    "id": "604f0cd2-37fb-4833-a5e1-821555b5b314",
    "attributes": {
      "email": "ada@example.com",
      "first_name": "Ada",
      "last_name": "Lovelace",
      "role": "superuser"
    },
    "links": {
      "self": "https://lightning.example.org/api/users/604f0cd2-37fb-4833-a5e1-821555b5b314"
    }
  }
}
```

Lightning doesn't email the users it creates, so whoever runs the automation has
to tell them their account exists.

If a user already has the email, in any case, Lightning answers 409 `taken` and
leaves that user alone, so automation can run the same request again safely. The
answer carries the existing user's id in `existing`, and nothing else about
them:

```json
{
  "type": "about:blank",
  "title": "Conflict",
  "status": 409,
  "code": "taken",
  "detail": "A value that must be unique is already in use. See errors.",
  "errors": [
    {
      "pointer": "#/email",
      "code": "taken",
      "detail": "has already been taken"
    }
  ],
  "existing": { "id": "604f0cd2-37fb-4833-a5e1-821555b5b314" }
}
```

If another field is wrong as well, Lightning answers 422 `invalid` instead, with
the email's `taken` entry among the others and no `existing`.

Find a user by email:

```bash
curl "https://lightning.example.org/api/users?email=ada@example.com" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

The list pages 10 users at a time by default, and at most 100 with `page_size`.
An `email` that isn't a single string, such as `email[]=...`, answers 400
`invalid_parameter` with an entry whose `parameter` is `email`.

Change a user's role or password:

```bash
curl -X PATCH https://lightning.example.org/api/users/$USER_ID \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"role": "user", "password": "a brand new password"}'
```

A new role or password signs the user out of every browser session. The email
can't be changed: a `PATCH` ignores it, as it ignores any key it doesn't take.
The API can't delete or disable a user.

## Manage projects

`GET /api/projects/:id` shows a project. `PUT /api/projects/:id` creates the
project under that id, or, if a project already has it, replaces its name and
description. Both need `projects:write`.

To create a project, send its `name` and `description`, its `members` as
`{email, role}` pairs, and `notify`. Each member must already be a user.
`notify` is `true` by default, and decides whether Lightning emails the members
it adds. `members` and `notify` only count when the project is created:

```bash
curl -X PUT https://lightning.example.org/api/projects/$PROJECT_ID \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "malaria-programme",
    "description": "Malaria case reporting",
    "members": [
      {"email": "ada@example.com", "role": "owner"},
      {"email": "grace@example.com", "role": "editor"}
    ],
    "notify": false
  }'
```

Lightning answers 201 with the project and its members when it creates one, and
200 when it replaces one.

## Manage collections

`GET` and `PUT /api/projects/:project_id/collections/:id` read and write a
project's collection. They need `collections:write`. `PUT` creates the
collection under that id, or renames the one that has it and keeps its items:

```bash
curl -X PUT https://lightning.example.org/api/projects/$PROJECT_ID/collections/$COLLECTION_ID \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "patients"}'
```

Lightning answers `{"data": {"id", "project_id", "name"}}`, with 201 for a new
collection and 200 for a rename. The items inside a collection are not part of
this API.

## Manage credentials

`GET` and `PUT /api/credentials/:id` read and write a credential. They need
`credentials:write`. `PUT` creates the credential under that id, or replaces the
name, schema and `main` body of the one that has it.

A `PUT` must name the credential's `owner` by email, and the owner must be an
existing user:

```bash
curl -X PUT https://lightning.example.org/api/credentials/$CREDENTIAL_ID \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Acme DHIS2",
    "schema": "raw",
    "owner": "ada@example.com",
    "credential_bodies": [
      {"name": "main", "body": {"username": "admin", "password": "district"}}
    ],
    "project_credentials": [{"project_id": "'"$PROJECT_ID"'"}]
  }'
```

- `credential_bodies` must be exactly one body, named `main`, holding an object.
  Replacing a credential leaves any other body it has alone.
- `project_credentials` is optional. A `PUT` only adds links, and never removes
  one the credential already has. Linking a project needs `credentials:write`
  only. Naming a project that doesn't exist answers 422 `invalid`, with a
  `not_found` entry at that link, as in `#/project_credentials/0/project_id`.
  Naming a project the owner isn't a member of answers the same way, with a
  `no_access` entry.
- The response never includes the credential's body. It lists every project the
  credential is linked to, but names a linked project only if the token also
  holds `projects:write`.
- A service account can write credentials but never delete one. Listing,
  creating with `POST` and deleting are for people: a service account's token
  gets a 401 `invalid_token` from those routes.

## When Lightning refuses

Every refusal is an [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457) problem
document with `type`, `title`, `status`, `code` and `detail`, as in the 409
example in [Manage users](#manage-users). It is sent as `application/json`, or
as `application/problem+json` when the request's `Accept` names that. Branch on
`status` and `code`, not on `detail`.

When the problem lies in particular parts of the request, the document also has
`errors`, a list of entries. Each entry has a `code` and a `detail`, and says
where the problem is: a `pointer` into the body, as in `#/members/0/email`, or
the name of a query `parameter`. Entries never quote a value from the request.

- 400 `malformed`: the body isn't a JSON object.
- 400 `invalid_parameter`: a query parameter isn't valid. `errors` names it.
- 400 `invalid_request`, with
  `WWW-Authenticate: Bearer error="invalid_request"`: the `Authorization` header
  has no token after `Bearer`, has whitespace inside the token, or was sent
  twice.
- 401 `invalid_token`, with `WWW-Authenticate: Bearer error="invalid_token"`:
  the access token is expired or bad, or isn't one this route accepts.
- 401 `unauthenticated`, with `WWW-Authenticate: Bearer`: the request sent no
  `Authorization` header.
- 402 `exceeds_limit`: creating a collection would go over the instance's limit,
  or the plan has no seat for a member a project `PUT` adds. For a member,
  `errors` has an entry at `#/members`.
- 403 `insufficient_scope`, with
  `WWW-Authenticate: Bearer error="insufficient_scope"` naming the one scope the
  request needed, as in `scope="credentials:write"`: the token lacks that scope.
  Lightning checks this first, so it comes before any 404 or 422, whether the
  project is missing or the body is wrong.
- 404 `not_found`: the project, collection, credential or user doesn't exist, or
  the id in the path isn't a UUID.
- 409 `scheduled_for_deletion`: the project (on the projects and collections
  routes) or the credential (on a credential `PUT`) is scheduled for deletion.
  Lightning refuses changes until the deletion is cancelled or completes.
- 409 `id_taken`: the id already belongs to a collection in another project, or
  to a credential with a different owner. Lightning never moves either.
- 409 `taken`: the value at the entry's pointer must be unique and is already in
  use. That is a user's email, a collection's name within its project, or a
  credential's name among its owner's credentials.
- 415 `unsupported_media_type`: the body isn't sent as JSON.
- 422 `invalid`: the body doesn't fit. `errors` has an entry for each field that
  is wrong. On the projects, collections and credentials routes it also has one
  for each key the route doesn't accept. The users routes ignore keys they don't
  take.
- 503 `not_ready`, with `Retry-After`: Lightning can't check a credential's
  schema yet. Try again after the number of seconds it gives.

## Change or remove the key

Generate a new key pair, set `SERVICE_ACCOUNT_PUBLIC_KEY` to the new public key,
and restart Lightning.

A service account's id is its key's thumbprint, so a new key is a new service
account. Access tokens issued to the old key stop working at once, and Lightning
refuses assertions signed with the old private key. The audit log names the old
and new keys separately.

To remove the service account, unset `SERVICE_ACCOUNT_PUBLIC_KEY` and restart.
Its tokens stop working, and first setup is turned back on. First setup still
only runs while the instance has no superuser.

## Monitor the service account

### Audit log

Superusers can see the audit log at `/settings/audit`. The service account shows
there as "Service account", named by its key's thumbprint. It records:

- `token_issued` for each access token, with the scopes it was given.
- `created` for each user it creates.
- `updated` for each user it changes, with the before and after of the email,
  names, role and confirmation. A new password shows only as `password_changed`.
  A change that changes nothing isn't recorded.
- `created` for each project it creates, with `collaborator_added` for each
  member it adds, and `name_updated` or `description_updated` when it changes
  one.
- `created` and `updated` for each collection it creates or renames.
- `created` and `updated` for each credential it writes, and `added_to_project`
  for each project it links.

### Logs

Lightning logs a warning when it refuses an assertion, at most once a minute for
each reason on each node:

```
Refused a service account assertion: <reason>
```

The reasons are:

- `malformed`: not a JWT, or it has no `iss`.
- `unknown_service_account`: `iss` isn't the thumbprint of the key that is set.
- `bad_signature`: not signed with RS256 by the matching private key.
- `wrong_subject`: `sub` isn't the same as `iss`.
- `wrong_audience`: `aud` isn't the token endpoint's URL.
- `missing_claims`: `exp`, `iat` or `jti` is missing, or `jti` is empty, too
  long or holds a NUL.
- `expired`: `exp` has passed.
- `lives_too_long`: `exp` is more than 60 seconds after `iat`.
- `issued_in_future`: `iat` is more than five seconds ahead of Lightning's
  clock.
- `replayed`: the `jti` has been used before.
- `wrong_client_id`: the `client_id` parameter doesn't match `iss`.

### Telemetry

Lightning emits two [`:telemetry`](https://hexdocs.pm/telemetry) events you can
attach a handler to:

| Event                                                | Measurements | Metadata                                                                                                                                        |
| ---------------------------------------------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `[:lightning, :service_account, :assertion_refused]` | `count: 1`   | `reason`, one of the reasons above                                                                                                              |
| `[:lightning, :accounts, :superuser_changed]`        | `count: 1`   | `change` (`:created`, `:granted` or `:password_changed`), `user_id`, `actor_type` and `actor_id` (both `nil` when no one is named as the actor) |

Unlike the log line, `assertion_refused` fires for every refusal, so it is the
one to count if you want to alert on someone guessing at the token endpoint.
`superuser_changed` fires whoever makes the change, so it also counts superusers
created or changed from the users page, where `actor_type` is `:user`.
