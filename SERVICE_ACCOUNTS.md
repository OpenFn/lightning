# Service accounts

A service account lets a program set up a Lightning instance through its API,
signing in with a key pair instead of a password. Use one when infrastructure
automation, rather than a person, creates the instance's users, including its
first superuser.

Each instance has at most one service account. For now it can only create,
change and find users.

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

## Manage users

Send the access token as `Authorization: Bearer <token>`. Creating and changing
users needs the `users:write` scope, and finding them needs `users:read`. A
token gets both unless you ask for fewer with a `scope` parameter.

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

If the email is already taken, Lightning answers 409 with the existing user and
leaves it alone, so automation can run the same request again safely.

Find a user by email:

```bash
curl "https://lightning.example.org/api/users?email=ada@example.com" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

Change a user's role or password:

```bash
curl -X PATCH https://lightning.example.org/api/users/$USER_ID \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"role": "user", "password": "a brand new password"}'
```

A new role or password signs the user out of every browser session. The email
can't be changed, and the API can't delete or disable a user.

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

### Logs

Lightning logs a warning whenever the service account gives someone superuser
rights or changes a superuser's password:

```
Service account <thumbprint> created superuser <user id>
Service account <thumbprint> made user <user id> a superuser
Service account <thumbprint> changed the password of superuser <user id>
```

It also logs a warning when it refuses an assertion, at most once a minute for
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

| Event                                                | Measurements | Metadata                                                                                  |
| ---------------------------------------------------- | ------------ | ----------------------------------------------------------------------------------------- |
| `[:lightning, :service_account, :assertion_refused]` | `count: 1`   | `reason`, one of the reasons above                                                        |
| `[:lightning, :service_account, :superuser_changed]` | `count: 1`   | `change` (`:created`, `:granted` or `:password_changed`), `user_id`, `service_account_id` |

Unlike the log line, `assertion_refused` fires for every refusal, so it is the
one to count if you want to alert on someone guessing at the token endpoint.
