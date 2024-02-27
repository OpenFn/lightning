# Deployment

Head to the [Deploy](https://docs.openfn.org/documentation/deploy/options)
section of our docs site to get started.

See below for technical considerations and instructions.

## Encryption

Lightning enforces encryption at rest for credentials, TOTP backup codes, and
webhook trigger authentication methods, for which an encryption key must be
provided when running in production.

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

## Workers

Lightning uses external worker processes for executing Runs. There are three
settings required to configure worker authentication.

- `WORKER_RUNS_PRIVATE_KEY`
- `WORKER_LIGHTNING_PUBLIC_KEY`
- `WORKER_SECRET`

You can use the `mix lightning.gen_worker_keys` task to generate these for
convenience.

For more information see the [Workers](WORKERS.md) documentation.

## Environment Variables

Note that for secure deployments, it's recommended to use a combination of
`secrets` and `configMaps` to generate secure environment variables.

### Limits

- `WORKER_MAX_RUN_MEMORY_MB` - how much memory (in MB) can a single run use?
- `WORKER_MAX_RUN_DURATION_SECONDS` - the maximum duration (in seconds) that
  workflows are allowed to run (keep this below your termination_grace_period if
  using kubernetes)
- `WORKER_CAPACITY` - the number of runs a ws-worker instance will take on
  concurrently.
- `MAX_DATACLIP_SIZE_MB` - the maximum size (in MB) of a dataclip created via
  the webhook trigger URL for a job. This limits the max request size via the
  JSON plug and may (in future) limit the size of dataclips that can be stored
  as run_results via the websocket connection from a worker.

### Other config

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
- `USAGE_TRACKER_HOST` - the host that receives usage tracking submissions
  (defaults to https://impact.openfn.org)
- `USAGE_TRACKING_ENABLED` - enables the submission of anonymised usage data to
  OpenFn (defaults to `true`).
- `USAGE_TRACKING_UUIDS` - indicates whether submissions should include
  cleartext uuids or not. Options are `cleartext` or `hashed_only`, with the
  default being `hashed_only`.
- `QUEUE_RESULT_RETENTION_PERIOD_SECONDS` - the number of seconds to keep
  completed (successful) `ObanJobs` in the queue (not to be confused with runs
  and/or history)
- `IS_RESETTABLE_DEMO` - If set to `yes` it allows this instance to be reset to
  the initial "Lightning Demo" state. Note that this will destroy _most_ of what
  you have in your database!

### Google

Using your Google Cloud account, provision a new OAuth 2.0 Client with the 'Web
application' type.

Set the callback url to: `https://<ENDPOINT DOMAIN>/authenticate/callback`.
Replacing `ENDPOINT DOMAIN` with the host name of your instance.

Once the client has been created, get/download the OAuth client JSON and set the
following environment variables:

- `GOOGLE_CLIENT_ID` - Which is `client_id` from the client details.
- `GOOGLE_CLIENT_SECRET` - `client_secret` from the client details.
