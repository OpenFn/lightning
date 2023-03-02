# Deployment

## Encryption

Lightning enforces encryption at rest for Credentials, for which an encryption
key must be provided when running in production.

The key is expected to be a randomized set of bytes, 32 long; and Base64 encoded
when setting the environment variable.

There is a mix task that can generate keys in the correct shape for use as an
environment variable:

```sh
mix lightning.gen_encryption_key
0bJ9w+hn4ebQrsCaWXuA9JY49fP9kbHmywGd5K7k+/s=
```

Copy your key _(NOT THIS ONE)_ and set it as `PRIMARY_ENCRYPTION_KEY` in your
environment.

## Environment Variables

Note that for secure deployments, it's recommended to use a combination of
`secrets` and `configMaps` to generate secure environment variables.

- `ADAPTORS_PATH` - where you store your locally installed adaptors
- `DISABLE_DB_SSL` - in production the use of an SSL conntection to Postgres is
  required by default, setting this to `"true"` allows unencrypted connections
  to the database. This is strongly discouraged in real production environment.
- `K8S_HEADLESS_SERVICE` - this environment variable is automatically set if
  you're running on GKE and it is used to establish an Erlang node cluster. Note
  that if you're _not_ using Kubernetes, the "gossip" strategy is used for
  establish clusters.
- `LISTEN_ADDRESS`" - the address the web server should bind to, defaults to
  `127.0.0.1` to block access from other machines.
- `LOG_LEVEL` - how noisy you want the logs to be (e.g. `debug`, `info`)
- `MAX_RUN_DURATION` - the maximum time (in milliseconds) that jobs are allowed
  to run (keep this below your termination_grace_period if using kubernetes)
- `MIX_ENV` - your mix env, likely `prod` for deployment
- `NODE_ENV` - node env, likely `production` for deployment
- `ORIGINS` - the allowed origins for web traffic to the backend
- `PORT` - the port your Phoenix app runs on
- `PRIMARY_ENCRYPTION_KEY` - a base64 encoded 32 character long string. See
  [Encryption](#encryption).
- `SCHEMAS_PATH` - path to the credential schemas that provide forms for
  different adaptors
- `SECRET_KEY_BASE` - a secret key used as a base to generate secrets for
  encrypting and signing data.
- `SENTRY_DSN` - if using Sentry for error monitoring, your DSN
- `URL_HOST` - the host, used for writing urls (e.g., `demo.openfn.org`)
- `URL_PORT` - the port, usually `443` for production
- `URL_SCHEME` - the scheme for writing urls, (e.g., `https`)

### Google

Using your Google Cloud account, provision a new OAuth 2.0 Client with the 'Web
application' type.

Set the callback url to: `https://<ENDPOINT DOMAIN>/authenticate/callback`.
Replacing `ENDPOINT DOMAIN` with the host name of your instance.

Once the client has been created, get/download the OAuth client JSON and set the
following environment variables:

- `GOOGLE_CLIENT_ID` - Which is `client_id` from the client details.
- `GOOGLE_CLIENT_SECRET` - `client_secret` from the client details.
