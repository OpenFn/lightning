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

[Set up a new instance](#set-up-a-new-instance) is for the operator who sets up
the key. [Get an access token](#get-an-access-token) is for whoever writes the
program that uses it. [API](API.md) lists what the token can call.

> #### Still under development {: .warning}
>
> Service accounts and the API may change while the API is being built.

## Set up a new instance

These steps take a new instance from no service account to a first superuser and
a first project. Each step shows what you see when it worked. Replace
`https://lightning.example.org` with your instance's URL. On a local development
server it is `http://localhost:4000`.

1. Make an RSA key pair:

   ```sh
   openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out sa_private.pem
   openssl pkey -in sa_private.pem -pubout -out sa_public.pem
   chmod 600 sa_private.pem
   ```

   The key must be RSA, at least 2048 bits. Lightning refuses EC and Ed25519
   keys at boot. The client signs with RS256. `sa_public.pem` starts with
   `-----BEGIN PUBLIC KEY-----`.

   Keep `sa_private.pem` secret. Anyone who holds it can act as the service
   account, including making superusers.

2. Give Lightning the public key. `SERVICE_ACCOUNT_PUBLIC_KEY` holds the public
   key, `sa_public.pem`, with its BEGIN and END lines. Lightning never needs the
   private key.

   Set the variable to the contents of the PEM file. If your tooling keeps one
   variable per line, base64-encode the file on one line instead.

   In Kubernetes, put the file in a Secret and read the variable from it:

   ```sh
   kubectl create secret generic lightning-service-account \
     --from-file=SERVICE_ACCOUNT_PUBLIC_KEY=sa_public.pem
   ```

   ```yaml
   env:
     - name: SERVICE_ACCOUNT_PUBLIC_KEY
       valueFrom:
         secretKeyRef:
           name: lightning-service-account
           key: SERVICE_ACCOUNT_PUBLIC_KEY
   ```

   With `docker run` on the command line, pass the file's contents with your
   other options:

   ```sh
   docker run -e SERVICE_ACCOUNT_PUBLIC_KEY="$(cat sa_public.pem)" ...
   ```

   A `docker run --env-file` file holds one variable per line, so put the key in
   it as one line of base64, with no quotes around it. Docker keeps quotes as
   part of the value.

   ```sh
   echo "SERVICE_ACCOUNT_PUBLIC_KEY=$(openssl base64 -A -in sa_public.pem)" >> lightning.env
   ```

   In Docker Compose's `environment:`, use a YAML block:

   ```yaml
   services:
     web:
       environment:
         SERVICE_ACCOUNT_PUBLIC_KEY: |
           -----BEGIN PUBLIC KEY-----
           MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...
           -----END PUBLIC KEY-----
   ```

   In a file named by Compose's `env_file:`, and in Lightning's own `.env` file,
   put the key in double quotes across lines:

   ```
   SERVICE_ACCOUNT_PUBLIC_KEY="-----BEGIN PUBLIC KEY-----
   MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...
   -----END PUBLIC KEY-----"
   ```

   With systemd, put one line of base64 in the `EnvironmentFile=`:

   ```
   SERVICE_ACCOUNT_PUBLIC_KEY=<output of: openssl base64 -A -in sa_public.pem>
   ```

   Never put the raw PEM in a `docker run --env-file` file, quoted or not, nor
   unquoted in any other file that holds one variable per line. Docker, Compose
   and Lightning's `.env` loader each refuse the whole file, and
   [PEM keys in environment variables](DEPLOYMENT.md#pem-keys-in-environment-variables)
   quotes what they print. Keep the base64 on one line, too. If base64 wrapped
   over several lines goes into such a file, the tool keeps only the first line
   without saying so, and Lightning stops at boot because the key has a BEGIN
   line but no END line.

3. Restart every node. Each node reads the key only at boot.

   Each node logs the service account's id at `info` level:

   ```
   Service account enabled, id QjEJWKwLEZ-0jVeOltPT6RsMqOVUtYvdsbd7-SbQQ_0
   ```

   If `LOG_LEVEL` is `warning` or `error`, this line doesn't appear.
   [Find the service account id](#find-the-service-account-id) shows how to
   compute it from the public key.

   To check that it worked, fetch the metadata document:

   ```sh
   curl -s https://lightning.example.org/.well-known/oauth-authorization-server
   ```

   It answers the document that [Sign an assertion](#sign-an-assertion) shows,
   and `https://lightning.example.org/first_setup` answers 404.

   While `SERVICE_ACCOUNT_PUBLIC_KEY` is set, first setup is turned off. The
   first superuser comes from the API instead, so nobody who reaches a fresh
   instance's web page can claim it first.

   If the value is wrong, Lightning stops at boot with `** (RuntimeError)` and
   one of these messages. Find yours and do what the second column says:

   | If the boot error says                                                                                                                                                                                                                                                                  | Do this                                                                                                                                                                                                        |
   | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
   | `SERVICE_ACCOUNT_PUBLIC_KEY is empty. Set it to the service account's public key, or unset it to run without a service account.`                                                                                                                                                        | Set it, or unset it. An empty value usually means a Secret or `${VAR}` didn't resolve.                                                                                                                         |
   | `SERVICE_ACCOUNT_PUBLIC_KEY starts and ends with a quote character. docker run --env-file and Compose's env_file with format: raw keep quotes as part of the value; remove them.`                                                                                                       | Remove the quotes around the base64 in that file.                                                                                                                                                              |
   | `SERVICE_ACCOUNT_PUBLIC_KEY is not a PEM key. Set it to the contents of the public key file, BEGIN and END lines included, or to that file base64-encoded.`                                                                                                                             | Set it to the contents of `sa_public.pem`, or to `openssl base64 -A -in sa_public.pem`.                                                                                                                        |
   | `SERVICE_ACCOUNT_PUBLIC_KEY has a BEGIN PUBLIC KEY line but no END line, so only part of the key arrived. A file that holds one variable per line keeps only the first line of a multi-line value; base64-encode the PEM file on one line instead: openssl base64 -A -in sa_public.pem` | Base64 wrapped over several lines went into a file that holds one variable per line, and the tool kept only the first line. Use the one-line base64 form from step 2. This is the message operators meet most. |
   | `SERVICE_ACCOUNT_PUBLIC_KEY holds a PEM block whose body is not valid base64. Copy the public key file again.`                                                                                                                                                                          | Copy `sa_public.pem` again.                                                                                                                                                                                    |
   | `SERVICE_ACCOUNT_PUBLIC_KEY has a BEGIN line that names no key type Lightning reads. Copy the public key file again, BEGIN and END lines included.`                                                                                                                                     | Copy `sa_public.pem` again, so the first line reads `-----BEGIN PUBLIC KEY-----` with all its dashes. An OpenSSH key gives this message too. Make the key pair with `openssl`, as in step 1.                   |
   | `SERVICE_ACCOUNT_PUBLIC_KEY holds more than one PEM block. Set it to the public key alone.`                                                                                                                                                                                             | Set it to `sa_public.pem` alone.                                                                                                                                                                               |
   | `SERVICE_ACCOUNT_PUBLIC_KEY holds a private key. Set it to the public key instead: openssl pkey -in sa_private.pem -pubout`                                                                                                                                                             | Set it to `sa_public.pem`, not `sa_private.pem`.                                                                                                                                                               |
   | `SERVICE_ACCOUNT_PUBLIC_KEY is not an RSA key. It must be an RSA public key of at least 2048 bits.`                                                                                                                                                                                     | Make an RSA key pair, as in step 1. Lightning refuses EC and Ed25519 keys.                                                                                                                                     |
   | `SERVICE_ACCOUNT_PUBLIC_KEY is a 1024-bit RSA key. Generate an RSA key pair of at least 2048 bits.`                                                                                                                                                                                     | Make a new key pair, as in step 1. The number in the message is your key's size.                                                                                                                               |
   | `SERVICE_ACCOUNT_PUBLIC_KEY holds a PEM block that is not a key Lightning can read. It must be an RSA public key of at least 2048 bits.`                                                                                                                                                | Make a key pair as in step 1, and set the variable to its public key.                                                                                                                                          |

   If a private key arrives cut short, the fourth message reads
   `BEGIN PRIVATE KEY` instead of `BEGIN PUBLIC KEY`.

   If Docker, Compose or Lightning's `.env` loader refuses the file before
   Lightning starts, see
   [PEM keys in environment variables](DEPLOYMENT.md#pem-keys-in-environment-variables).

   When `SERVICE_ACCOUNT_PUBLIC_KEY` is not set, the instance has no service
   account and the token endpoint refuses every request.

4. Get an access token with the grants that setup needs. First save the script
   in [Sign an assertion](#sign-an-assertion) as `make_assertion.mjs` next to
   `sa_private.pem`. It needs Node 18 or later and nothing else.

   ```sh
   ASSERTION=$(node make_assertion.mjs sa_private.pem https://lightning.example.org/api/oauth/token)

   TOKEN=$(curl -s https://lightning.example.org/api/oauth/token \
     --data-urlencode grant_type=client_credentials \
     --data-urlencode client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer \
     --data-urlencode "client_assertion=$ASSERTION" \
     --data-urlencode "scope=users:read users:write projects:write" \
     | sed -E 's/.*"access_token":"([^"]+)".*/\1/')
   ```

   When it worked, `echo $TOKEN` prints a long string that starts with `eyJ`. If
   it prints a JSON object with `"error"` instead, Lightning refused the
   exchange. See [When the exchange is refused](#when-the-exchange-is-refused).
   The `sed` command passes a body without a token through unchanged, which is
   why the error shows.

   The token lasts five minutes. Run steps 5 and 6 within that time, or repeat
   this step.

5. Create the first superuser:

   ```sh
   curl -s https://lightning.example.org/api/users \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"email":"admin@example.org","password":"<12 to 72 characters>","first_name":"Ada","last_name":"Admin","role":"superuser","confirmed":true}'
   ```

   Lightning answers 201 with the new user:

   ```json
   {
     "data": {
       "type": "users",
       "id": "6ff95e10-6502-4e3f-a513-6c59f326a975",
       "attributes": {
         "email": "admin@example.org",
         "first_name": "Ada",
         "last_name": "Admin",
         "role": "superuser"
       },
       "links": {
         "self": "https://lightning.example.org/api/users/6ff95e10-6502-4e3f-a513-6c59f326a975"
       }
     }
   }
   ```

   - The password must be 12 to 72 characters.
   - `"confirmed": true` marks the email address as confirmed, so the person can
     sign in straight away at `https://lightning.example.org/users/log_in`. The
     answer doesn't echo it.
   - Leave out `role` and `confirmed` to create an ordinary user.
   - Lightning doesn't check for an existing superuser, so this works whatever
     users the instance has.
   - The same email again, in any letter case, answers 422 with a `taken` entry
     at `#/email`. Automation that runs more than once looks first with
     `GET /api/users?email=admin@example.org`. That request needs `users:read`
     and matches the email without regard to case.
   - `LightningWeb.API.UserController` lists the other keys, and
     `PATCH /api/users/:id`.

6. Create a project:

   ```sh
   PROJECT_ID=$(uuidgen | tr A-Z a-z)

   curl -s -X PUT https://lightning.example.org/api/projects/$PROJECT_ID \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"name":"intake","members":[{"email":"admin@example.org","role":"owner"}]}'
   ```

   Lightning answers 201 the first time and 200 when you send it again, with:

   ```json
   {
     "data": {
       "type": "projects",
       "id": "866c4b32-c41a-4eb5-b470-2585df8f755f",
       "attributes": {
         "name": "intake",
         "description": null,
         "members": [{ "email": "admin@example.org", "role": "owner" }]
       },
       "relationships": {},
       "links": {
         "self": "https://lightning.example.org/api/projects/866c4b32-c41a-4eb5-b470-2585df8f755f"
       }
     },
     "links": {
       "self": "https://lightning.example.org/api/projects/866c4b32-c41a-4eb5-b470-2585df8f755f"
     },
     "included": []
   }
   ```

   - A project needs exactly one owner, who must already be a user. That is why
     step 5 comes first.
   - `uuidgen` ships with macOS and with most Linux desktops. Where it is
     missing, `cat /proc/sys/kernel/random/uuid` gives one.
   - `members` and `notify` count only when the `PUT` creates the project. A
     later `PUT` changes only `name` and `description`.
   - Lightning emails each member it adds unless the body has `"notify": false`.
   - Read the project back with `GET /api/projects/$PROJECT_ID`. That request
     needs `projects:write`, since there is no read-only grant for projects.
   - `LightningWeb.API.ProjectController` lists the body's keys.
     [API](API.md#conventions) says how to choose the id and when Lightning
     answers 201 or 200.

## Get an access token

The token endpoint is `POST /api/oauth/token`. It follows OAuth 2.0's client
credentials grant, with the client proving itself by a signed JWT
(`private_key_jwt`, RFC 7523).

### What a client needs

A client needs four things:

- the private key, `sa_private.pem`;
- the service account id, from the boot log or computed as below;
- the token endpoint's URL, from `token_endpoint` in
  `/.well-known/oauth-authorization-server`;
- the token grants its job needs, from [Token grants](#token-grants).

### Find the service account id

The id is the RFC 7638 SHA-256 thumbprint of the public key, base64url-encoded
without padding. A JOSE library's "JWK thumbprint" function computes it.

The thumbprint is the SHA-256 of `{"e":"...","kty":"RSA","n":"..."}`, with the
members in that order and no spaces. `e` and `n` are the key's exponent and
modulus in base64url.

This script prints the id from the public or the private PEM:

```js
// service_account_id.mjs: node service_account_id.mjs sa_public.pem
import { createPublicKey, createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

const { e, n } = createPublicKey(readFileSync(process.argv[2])).export({
  format: 'jwk',
});
const id = createHash('sha256')
  .update(JSON.stringify({ e, kty: 'RSA', n }))
  .digest('base64url');
console.log(id);
```

The audit log shows the same id for the service account.

### Sign an assertion

The assertion is a JWT signed with the private key using RS256. The header's
`alg` must be `RS256`. `typ` is optional. The claims are:

| Claim        | Value                                                                                                                                                                                                                                           |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `iss`, `sub` | The service account id. See [Find the service account id](#find-the-service-account-id).                                                                                                                                                        |
| `aud`        | The token endpoint's URL, as `token_endpoint` gives it (see below).                                                                                                                                                                             |
| `iat`, `exp` | Issue and expiry times, as integers in Unix seconds. `exp` is at most 60 seconds after `iat`. Lightning accepts an `iat` up to five seconds ahead of its own clock.                                                                             |
| `jti`        | A string of 1 to 255 bytes with no NUL character. Use a new random value, such as a UUID, for every assertion. Once Lightning issues a token for a `jti`, it refuses that `jti` again. An assertion Lightning refuses doesn't use up its `jti`. |

Read `aud` from the server's metadata rather than building it from the address
you connect to. Lightning compares it with its own configured URL, which can
differ from the one in your request. Behind a proxy, or when you connect to
`127.0.0.1` while Lightning's URL is `https://lightning.example.org`, an `aud`
built from the address you connect to is refused.

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
    "collections:write",
    "audit:read"
  ],
  "grant_types_supported": ["client_credentials"],
  "token_endpoint_auth_methods_supported": ["private_key_jwt"],
  "token_endpoint_auth_signing_alg_values_supported": ["RS256"],
  "response_types_supported": []
}
```

Any JWT library that signs RS256 can make the assertion. This Node script uses
only Node's built-in modules, and needs Node 18 or later:

```js
// make_assertion.mjs: node make_assertion.mjs sa_private.pem <token_endpoint>
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

`curl --data-urlencode` sends `Content-Type: application/x-www-form-urlencoded`.
Another HTTP client must set it. A JSON body is refused with 400
`invalid_request`.

`scope` is required. List the grants separated by spaces, each one from
`scopes_supported`. A missing, empty or unknown one is refused with 400
`invalid_scope`. A token can't gain grants later, so ask for every grant the job
needs.

`client_id` is optional. If you send it, it must be the service account's id.

### Keep a token fresh

- Send the token as `Authorization: Bearer <access_token>`.
- It lasts `expires_in` seconds, 300 today. There is no refresh token.
- Before it runs out, sign a new assertion and exchange it again. Get a new
  token when fewer than 30 seconds remain. When a request answers 401, get a new
  token and retry once.
- An expired token answers 401 `invalid_token` with
  `WWW-Authenticate: Bearer error="invalid_token", error_description="The access token expired"`.
  Any other bad token gets `Bearer error="invalid_token"` with no description.
  Either way, sign a new assertion and get a new token.
- Tokens are not stored, so a client can ask for as many as it needs. Each one
  records a `token_issued` event in the audit log.

### When the exchange is refused

The token endpoint answers with OAuth's error format,
`{"error": "<code>", "error_description": "<why>"}`, rather than the problem
documents the rest of the API uses. `error_description` says what to fix.

| Status | `error`                  | `error_description`                                                                                                                 | Reason in the log         |
| ------ | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| 400    | `invalid_request`        | `The request could not be parsed. Send the parameters form-encoded, as application/x-www-form-urlencoded, in the body.`             |                           |
| 413    | `invalid_request`        | `The body is larger than this server accepts.`                                                                                      |                           |
| 400    | `invalid_request`        | `The body must be form-encoded, as application/x-www-form-urlencoded.`                                                              |                           |
| 400    | `invalid_request`        | `The body has no single grant_type value. Send grant_type=client_credentials in the form-encoded body, not the query string.`       |                           |
| 400    | `unsupported_grant_type` | `grant_type must be client_credentials.`                                                                                            |                           |
| 400    | `invalid_request`        | `Send client_assertion_type urn:ietf:params:oauth:client-assertion-type:jwt-bearer and the signed JWT in client_assertion.`         |                           |
| 400    | `invalid_request`        | `scope must be one value, with token grants separated by spaces.`                                                                   |                           |
| 400    | `invalid_scope`          | `scope is missing or empty. Name the token grants you need, separated by spaces.`                                                   |                           |
| 400    | `invalid_scope`          | `scope names something that is not a token grant. scopes_supported in /.well-known/oauth-authorization-server lists them.`          |                           |
| 401    | `invalid_client`         | `client_assertion is not a JWT with an iss claim.`                                                                                  | `malformed`               |
| 401    | `invalid_client`         | `The assertion's iss is not this server's service account id.`                                                                      | `unknown_service_account` |
| 401    | `invalid_client`         | `The assertion's signature does not verify with the service account's public key. Sign it with RS256 and the matching private key.` | `bad_signature`           |
| 401    | `invalid_client`         | `The assertion's sub must be the service account id, the same as its iss.`                                                          | `wrong_subject`           |
| 401    | `invalid_client`         | `The assertion's aud must be exactly the token_endpoint URL in /.well-known/oauth-authorization-server.`                            | `wrong_audience`          |
| 401    | `invalid_client`         | `The assertion needs integer exp and iat claims, and a jti of 1 to 255 bytes with no NUL character.`                                | `missing_claims`          |
| 401    | `invalid_client`         | `The assertion's exp has passed. Check the client's clock.`                                                                         | `expired`                 |
| 401    | `invalid_client`         | `The assertion's exp is more than 60 seconds after its iat.`                                                                        | `lives_too_long`          |
| 401    | `invalid_client`         | `The assertion's iat is more than 5 seconds ahead of the server's clock. Check the client's clock.`                                 | `issued_in_future`        |
| 401    | `invalid_client`         | `client_id must be the service account id, the same as the assertion's iss, or be left out.`                                        | `wrong_client_id`         |
| 401    | `invalid_client`         | `This assertion's jti has been used before. Sign a new assertion with a new jti for each token request.`                            | `replayed`                |

Every refusal of a token request, including these and a body the token endpoint
can't read or that is too large, is JSON in OAuth's error format, whatever
`Accept` says. A 401 from the token endpoint has no `WWW-Authenticate` header.
The client authenticates in the body, not in a header.

The common causes are an `aud` that doesn't match `token_endpoint` exactly, a
`jti` used before, an assertion that lives longer than 60 seconds, and a client
clock that is off. A clock more than five seconds ahead of the server's and a
clock 60 or more seconds behind are both refused, and the description says
which.

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
| `audit:read`        | Reads the instance's audit events.                                                          |

To set up a new instance, ask for `users:write` and `projects:write`, and
`users:read` if the automation looks users up before creating them.

There is no read-only grant for projects, credentials or collections. Reading a
project, its workflows or its runs needs `projects:write`.

A token without the grant a route needs gets 403 `insufficient_scope`. The
body's `scope` and the `WWW-Authenticate` header both name the grant. Lightning
checks the grant before it looks for the record, so the answer is the same
whether or not the record exists. [API](API.md#routes) lists the grant each
route needs.

## Change or remove the key

To change the key, generate a new key pair, set `SERVICE_ACCOUNT_PUBLIC_KEY` to
the new public key, and restart Lightning.

The service account's id comes from its key, so a new key makes a new service
account with a new id. Lightning reads the key only at boot. After the restart,
it refuses tokens issued to the old key at once, rather than when they expire. A
restart with the same key keeps the same id, so issued tokens keep working until
they expire. Lightning signs access tokens with `WORKER_RUNS_PRIVATE_KEY`, so
changing that key also cuts them off. The audit log shows the old and new keys
as separate service accounts.

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

The client gets the same refusal as `error_description`. The reason is the one
in the Reason in the log column of
[When the exchange is refused](#when-the-exchange-is-refused). A refusal you
didn't cause in the log, or many of them in telemetry, can mean someone is
probing the token endpoint.

### Telemetry

Lightning emits two [`:telemetry`](https://hexdocs.pm/telemetry) events you can
attach a handler to:

| Event                                                | Measurements | Metadata                                                                                      |
| ---------------------------------------------------- | ------------ | --------------------------------------------------------------------------------------------- |
| `[:lightning, :service_account, :assertion_refused]` | `count: 1`   | `reason`, the same as in the log                                                              |
| `[:lightning, :accounts, :superuser_changed]`        | `count: 1`   | `change` (`:created`, `:granted` or `:password_changed`), `user_id`, `actor_type`, `actor_id` |

`assertion_refused` fires for every refusal, unlike the log line, so count it to
alert on someone guessing at the token endpoint. `superuser_changed` fires
whoever makes the change, including a superuser on the users page, where
`actor_type` is `:user`.
