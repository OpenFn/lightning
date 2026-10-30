# Service accounts

A service account lets a program set up a Lightning instance through its API,
signing in with a key pair instead of a password. Use one when infrastructure
automation, rather than a person, creates the instance's users, including its
first superuser, and its projects, credentials and collections.

Each instance has at most one service account. Lightning holds its RSA public
key. The program holds the private key, signs a short assertion with it, and
trades the assertion for an access token that lasts five minutes.

A service account differs from a person's personal access token:

- It is not a user. It has no email, no password and no project memberships.
- It can act on every project, and it is the only caller that can use
  `/api/users`.
- Its token carries only the token grants it asked for, and expires after five
  minutes. A personal access token carries its person's permissions and lasts
  until the person revokes it.
- It cannot own credentials, provision projects through `/api/provision`, or use
  the `/collections` API that jobs read and write.

[API](API.md) lists what the token can call.

> #### Still under development {: .warning}
>
> Service accounts and the API may change while the API is being built.

## Set up a service account

1. Generate an RSA key pair of at least 2048 bits:

   ```sh
   openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out sa_private.pem
   openssl pkey -in sa_private.pem -pubout -out sa_public.pem
   ```

   Keep `sa_private.pem` secret. Anyone who holds it can act as the service
   account.

2. Encode the public key as base64 on one line:

   ```sh
   base64 < sa_public.pem | tr -d '\n'
   ```

   The value must not contain line breaks. GNU `base64` wraps its output unless
   you remove them, as `tr` does here.

3. Set `SERVICE_ACCOUNT_PUBLIC_KEY` to that value and restart Lightning. Each
   node logs the service account's id when it starts:

   ```
   Service account enabled, id QjEJWKwLEZ-0jVeOltPT6RsMqOVUtYvdsbd7-SbQQ_0
   ```

4. [Get an access token](#get-an-access-token) with the `users:write` grant and
   [create the first superuser](API.md#create-the-first-superuser) through the
   API.

While `SERVICE_ACCOUNT_PUBLIC_KEY` is set, first setup is turned off and
`/first_setup` answers 404. The first superuser comes from the API instead, so
nobody who reaches a fresh instance's web page can claim it first.

If the value is wrong, Lightning stops at boot with one of these errors:

- `SERVICE_ACCOUNT_PUBLIC_KEY must be the PEM public key, base64-encoded on one line`:
  the value has line breaks, or it is a PEM that was not encoded.
- `SERVICE_ACCOUNT_PUBLIC_KEY holds a private key, not a public one`: you
  encoded `sa_private.pem`.
- `SERVICE_ACCOUNT_PUBLIC_KEY is a 1024-bit RSA key; it must be at least 2048 bits`
- `SERVICE_ACCOUNT_PUBLIC_KEY is not an RSA public key`: the key is another
  type, such as an EC key, or the PEM is damaged.

When `SERVICE_ACCOUNT_PUBLIC_KEY` is not set, the instance has no service
account and the token endpoint refuses every request.

## Get an access token

The token endpoint is `POST /api/oauth/token`. It follows OAuth 2.0's client
credentials grant, with the client proving itself by a signed JWT
(`private_key_jwt`, RFC 7523).

### Sign an assertion

The assertion is a JWT signed with the private key using RS256. Its claims are:

| Claim        | Value                                                                                                         |
| ------------ | ------------------------------------------------------------------------------------------------------------- |
| `iss`, `sub` | The service account's id, from the boot log.                                                                  |
| `aud`        | The token endpoint's URL, as `token_endpoint` gives it (see below).                                           |
| `iat`, `exp` | Issue and expiry times in Unix seconds. `exp` is at most 60 seconds after `iat`.                              |
| `jti`        | A unique string of at most 255 bytes. Once Lightning issues a token for a `jti`, it refuses that `jti` again. |

The service account's id is the RFC 7638 SHA-256 thumbprint of the public key,
so you can also compute it, as the script below does.

Read `aud` from the server's metadata rather than building it from the address
you connect to. Lightning compares it with its own configured URL, which can
differ from the one in your request:

```sh
curl -s https://lightning.example.org/.well-known/oauth-authorization-server
```

```json
{
  "issuer": "https://lightning.example.org",
  "token_endpoint": "https://lightning.example.org/api/oauth/token",
  "scopes_supported": [
    "users:read",
    "users:write",
    "projects:write",
    "credentials:write",
    "collections:write"
  ],
  "grant_types_supported": ["client_credentials"],
  "token_endpoint_auth_methods_supported": ["private_key_jwt"],
  "token_endpoint_auth_signing_alg_values_supported": ["RS256"],
  "response_types_supported": []
}
```

Any JWT library that signs RS256 can make the assertion. This Node script uses
only Node's built-in modules:

```js
// node make_assertion.mjs sa_private.pem https://lightning.example.org/api/oauth/token
import {
  createPrivateKey,
  createPublicKey,
  createHash,
  sign,
  randomUUID,
} from 'node:crypto';
import { readFileSync } from 'node:fs';

const [keyFile, aud] = process.argv.slice(2);
const key = createPrivateKey(readFileSync(keyFile));
const { e, n } = createPublicKey(key).export({ format: 'jwk' });
const id = createHash('sha256')
  .update(JSON.stringify({ e, kty: 'RSA', n }))
  .digest('base64url');

const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const claims = {
  iss: id,
  sub: id,
  aud,
  iat: now,
  exp: now + 60,
  jti: randomUUID(),
};
const input = `${b64({ alg: 'RS256', typ: 'JWT' })}.${b64(claims)}`;
const signature = sign('sha256', Buffer.from(input), key).toString('base64url');
process.stdout.write(`${input}.${signature}`);
```

### Exchange it for a token

Send a form-encoded body, not JSON. Name the token grants you need in `scope`,
separated by spaces:

```sh
ASSERTION=$(node make_assertion.mjs sa_private.pem https://lightning.example.org/api/oauth/token)

curl -s https://lightning.example.org/api/oauth/token \
  --data-urlencode grant_type=client_credentials \
  --data-urlencode client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer \
  --data-urlencode "client_assertion=$ASSERTION" \
  --data-urlencode "scope=users:write projects:write"
```

```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6ImF0K2p3dCJ9…",
  "token_type": "Bearer",
  "expires_in": 300,
  "scope": "users:write projects:write"
}
```

`client_id` is optional. If you send it, it must be the service account's id.

Send the token as `Authorization: Bearer <access_token>`. It lasts 300 seconds
and can't be refreshed. Sign a new assertion and exchange it again before
`expires_in` runs out, or when a request answers 401 `invalid_token`.

### When the exchange is refused

The token endpoint answers with OAuth's error format, `{"error": "<code>"}`,
rather than the problem documents the rest of the API uses.

| Status | `error`                  | Cause                                                                                   |
| ------ | ------------------------ | --------------------------------------------------------------------------------------- |
| 400    | `invalid_request`        | The body isn't form-encoded, the parameters are in the query string, or one is missing. |
| 400    | `unsupported_grant_type` | `grant_type` isn't `client_credentials`.                                                |
| 400    | `invalid_scope`          | `scope` is missing, empty, or names something that isn't a token grant.                 |
| 401    | `invalid_client`         | The assertion was refused, or `client_id` doesn't match.                                |

Lightning gives the same `invalid_client` for every refused assertion. Its log
has the reason, as described in [Logs](#logs). The common causes are an `aud`
that doesn't match `token_endpoint` exactly, a `jti` used before, and a clock
more than five seconds ahead of the server's.

## Token grants

A request to the token endpoint names the token grants it needs in `scope`, and
the access token carries only those. Ask for the fewest that do the job.

| Token grant         | What it allows                                                                              |
| ------------------- | ------------------------------------------------------------------------------------------- |
| `users:read`        | Finds and reads users.                                                                      |
| `users:write`       | Creates and changes users, including superusers. It does not include `users:read`.          |
| `projects:write`    | Reads and changes projects and what's in them: workflows, jobs, work orders, runs and logs. |
| `credentials:write` | Reads and changes credentials, and which projects they are linked to.                       |
| `collections:write` | Reads, creates and renames a project's collections.                                         |

Apart from users, a grant that changes a resource also reads it. There is no
separate read grant for projects, credentials or collections.

A token without the grant a route needs gets 403 with the code
`insufficient_scope`, and its `WWW-Authenticate` header names the grant.
Lightning checks the grant before it looks for the record, so the answer is the
same whether or not the record exists. [API](API.md#routes) lists the grant each
route needs.

## Change or remove the key

To change the key, generate a new key pair, set `SERVICE_ACCOUNT_PUBLIC_KEY` to
the new public key, and restart Lightning.

The service account's id comes from its key, so a new key makes a new service
account with a new id. Lightning reads the key only at boot. After the restart,
it refuses tokens issued to the old key at once, rather than when they expire.
The audit log shows the old and new keys as separate service accounts.

To remove the service account, unset `SERVICE_ACCOUNT_PUBLIC_KEY` and restart
Lightning. Its tokens stop working, and first setup is turned back on. First
setup still runs only while the instance has no superuser.

## Monitor the service account

### Audit log

Superusers can see the audit log at `/settings/audit`. The service account
appears there as "Service account", named by its id. Lightning records a
`token_issued` event for each access token, with the token grants it carries.
The changes the service account makes to users, projects, credentials and
collections appear with it as the actor, as a person's changes do.

### Logs

Lightning logs a warning when it refuses an assertion, at most once a minute for
each reason on each node:

```
Refused a service account assertion: <reason>
```

| Reason                    | Cause                                                                         |
| ------------------------- | ----------------------------------------------------------------------------- |
| `malformed`               | The assertion isn't a JWT, or it has no `iss`.                                |
| `unknown_service_account` | `iss` isn't the service account's id, or no key is set.                       |
| `bad_signature`           | It isn't signed with RS256 by the matching private key.                       |
| `wrong_subject`           | `sub` isn't the service account's id.                                         |
| `wrong_audience`          | `aud` isn't the token endpoint's URL.                                         |
| `missing_claims`          | `exp`, `iat` or `jti` is missing, or `jti` is empty or longer than 255 bytes. |
| `expired`                 | `exp` has passed.                                                             |
| `lives_too_long`          | `exp` is more than 60 seconds after `iat`.                                    |
| `issued_in_future`        | `iat` is more than five seconds ahead of Lightning's clock.                   |
| `replayed`                | The `jti` has been used before.                                               |
| `wrong_client_id`         | The `client_id` parameter isn't the service account's id.                     |

### Telemetry

Lightning emits two [`:telemetry`](https://hexdocs.pm/telemetry) events you can
attach a handler to:

| Event                                                | Measurements | Metadata                                                                                      |
| ---------------------------------------------------- | ------------ | --------------------------------------------------------------------------------------------- |
| `[:lightning, :service_account, :assertion_refused]` | `count: 1`   | `reason`, one of the reasons above                                                            |
| `[:lightning, :accounts, :superuser_changed]`        | `count: 1`   | `change` (`:created`, `:granted` or `:password_changed`), `user_id`, `actor_type`, `actor_id` |

`assertion_refused` fires for every refusal, unlike the log line, so count it to
alert on someone guessing at the token endpoint. `superuser_changed` fires
whoever makes the change, including a superuser on the users page, where
`actor_type` is `:user`.
