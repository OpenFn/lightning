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
- `RUN_GRACE_PERIOD_SECONDS` - how long _after_ the `MAX_RUN_DURATION_SECONDS`
  should the server wait for the worker to send back data on a run.
- `WORKER_MAX_RUN_DURATION_SECONDS` - the maximum duration (in seconds) that
  workflows are allowed to run (keep this plus `RUN_GRACE_PERIOD_SECONDS` below
  your termination_grace_period if using kubernetes)
- `WORKER_CAPACITY` - the number of runs a ws-worker instance will take on
  concurrently.
- `MAX_DATACLIP_SIZE_MB` - the maximum size (in MB) of a dataclip created via
  the webhook trigger URL for a job. This limits the max request size via the
  JSON plug and may (in future) limit the size of dataclips that can be stored
  as run_results via the websocket connection from a worker.
- `MAX_CREDENTIAL_SENSITIVE_VALUES` - the maximum number of sensitive values
  that can be stored in a credential. Defaults to 50.

### GitHub

Lightning enables connection to GitHub via GitHub Apps. The following GitHub
repository permissions are needed for the GitHub app:

| **Resource** | **Access**     |
| ------------ | -------------- |
| Actions      | Read and Write |
| Contents     | Read and Write |
| Metadata     | Read only      |
| Secrets      | Read and Write |
| Workflows    | Read and Write |

Ensure you set the following URLs:

- **Homepage URL:** `<app_url_here>`
- **Callback URL for authorizing users:** `<app_url_here>/oauth/github/callback`
  (Do NOT check the two checkboxes in this section requesting Device Flow and
  OAuth.)
- **Setup URL for Post installation:** `<app_url_here>/setup_vcs` (Check the box
  for **Redirect on update**)

These environment variables will need to be set in order to configure the github
app:

| **Variable**               | **Description**                                                                                                           |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `GITHUB_APP_ID`            | the github app ID.                                                                                                        |
| `GITHUB_APP_NAME`          | the github app name. This is the name used in the public link. It is the downcased name with spaces replaced with hyphens |
| `GITHUB_APP_CLIENT_ID`     | the github app Client ID                                                                                                  |
| `GITHUB_APP_CLIENT_SECRET` | the github app Client Secret                                                                                              |
| `GITHUB_CERT`              | the github app private key (Base 64 encoded)                                                                              |

You can access these from your github app settings menu. Also needed for the
configuration is:

- `REPO_CONNECTION_SIGNING_SECRET` - secret used to sign access tokens. This
  access token is used to authenticate requests made from the github actions.
  You can generate this using `mix lightning.gen_encryption_key`

### Storage

Lightning can use a storage backend to store exports.

| **Variable**      | Description                                      |
| ----------------- | ------------------------------------------------ |
| `STORAGE_BACKEND` | the storage backend to use. (default is `local`) |
| `STORAGE_PATH`    | the path to store files in. (default is `.`)     |

#### Supported backends:

- `local` - local file storage
- `gcs` - Google Cloud Storage

#### Google Cloud Storage

For Google Cloud Storage, the following environment variables are required:

| **Variable**                          | Description                                                                      |
| ------------------------------------- | -------------------------------------------------------------------------------- |
| `GCS_BUCKET`                          | the name of the bucket to store files in                                         |
| `GOOGLE_APPLICATION_CREDENTIALS_JSON` | A base64 encoded JSON keyfile for the service account with access to the bucket. |

> ℹ️ Note: The `GOOGLE_APPLICATION_CREDENTIALS_JSON` should be base64 encoded,
> currently Workload Identity is not supported.

### Mail

Lightning can send emails for various reasons, such as password resets and
alerts for failed runs.

In order to send emails, you need to set the `MAIL_PROVIDER` environment
variable to one of the following:

- `local` (the default)
- `mailgun`
- `smtp`

You will also want to set the `EMAIL_ADMIN` environment variable to the email
address that will be used as the sender for system emails.

#### Mailgun

For mailgun, the following environment variables are required:

| **Variable**      | Description              |
| ----------------- | ------------------------ |
| `MAIL_PROVIDER`   | Must be set to `mailgun` |
| `MAILGUN_API_KEY` | the mail gun api key     |
| `MAILGUN_DOMAIN`  | the mail gun domain      |

#### SMTP

For SMTP, the following environment variables are required:

| **Variable**    | Description                                                              |
| --------------- | ------------------------------------------------------------------------ |
| `MAIL_PROVIDER` | Must be set to `smtp`                                                    |
| `SMTP_USERNAME` | Username for your server                                                 |
| `SMTP_PASSWORD` | Password for the user                                                    |
| `SMTP_RELAY`    | IP address or hostname                                                   |
| `SMTP_TLS`      | Use TLS, defaults to `true`, options are `true`, `false`, `if_available` |
| `SMTP_PORT`     | Which port to use, defaults to `587`                                     |

### Other config

| **Variable**                                      | Description                                                                                                                                                                                                                                                     |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ADAPTORS_PATH`                                   | Where you store your locally installed adaptors                                                                                                                                                                                                                 |
| `ALLOW_SIGNUP`                                    | Set to `true` to enable user access to the registration page. Set to `false` to disable new user registrations and block access to the registration page.<br>Default is `true`.                                                                                 |
| `CORS_ORIGIN`                                     | A list of acceptable hosts for browser/cors requests (',' separated)                                                                                                                                                                                            |
| `DISABLE_DB_SSL`                                  | In production, the use of an SSL connection to Postgres is required by default.<br>Setting this to `"true"` allows unencrypted connections to the database. This is strongly discouraged in a real production environment.                                      |
| `EMAIL_ADMIN`                                     | This is used as the sender email address for system emails. It is also displayed in the menu as the support email.                                                                                                                                              |
| `EMAIL_SENDER_NAME`                               | This is displayed in the email client as the sender name for emails sent by the application.                                                                                                                                                                    |
| `ERLANG_NODE_DISCOVERY_VIA_POSTGRES_CHANNEL_NAME` | The name of the Postgresql channel that is used when Erlang node discovery via Postgres is enabled. Defaults to `lightning-cluster` if not set.                                                                                                                 |
| `ERLANG_NODE_DISCOVERY_VIA_POSTGRES_ENABLED`      | If set to `true`, Lightning will use Postgres to discover Erlang nodes. This strategy will be used in addition to other strategies that are in use. Default value is `false`                                                                                    |
| `IDLE_TIMEOUT`                                    | The number of seconds that must pass without data being received before the Lightning web server kills the connection.                                                                                                                                          |
| `IS_RESETTABLE_DEMO`                              | If set to `yes`, it allows this instance to be reset to the initial "Lightning Demo" state. Note that this will destroy _most_ of what you have in your database!                                                                                               |
| `K8S_HEADLESS_SERVICE`                            | This environment variable is automatically set if you're running on GKE and it is used to establish an Erlang node cluster. Note that if you're _not_ using Kubernetes, the "gossip" strategy is used to establish clusters.                                    |
| `LISTEN_ADDRESS`                                  | The address the web server should bind to. Defaults to `127.0.0.1` to block access from other machines.                                                                                                                                                         |
| `LOG_LEVEL`                                       | How noisy you want the logs to be (e.g., `debug`, `info`)                                                                                                                                                                                                       |
| `METRICS_RUN_PERFORMANCE_AGE_SECONDS`             | The oldest a run can be to be included in Run performance metrics.                                                                                                                                                                                              |
| `METRICS_RUN_QUEUE_AGE_SECONDS`                   | The polling period for run queue metrics.                                                                                                                                                                                                                       |
| `METRICS_STALLED_RUN_THRESHOLD_SECONDS`           | The length of time a Run must be in the `available` state before it is considered stalled.                                                                                                                                                                      |
| `METRICS_UNCLAIMED_RUN_THRESHOLD_SECONDS`         | The length of time a Run must be in the `available` state before it counts towards an impeded project.                                                                                                                                                          |
| `MIX_ENV`                                         | Your mix env, likely `prod` for deployment                                                                                                                                                                                                                      |
| `NODE_ENV`                                        | Node env, likely `production` for deployment                                                                                                                                                                                                                    |
| `ORIGINS`                                         | The allowed origins for web traffic to the backend                                                                                                                                                                                                              |
| `PER_WORKFLOW_CLAIM_LIMIT`                        | The maximum number of runs per workflow to consider during run claiming. This prevents any single workflow from dominating the processing queue while ensuring fairness across workflows.<br>Default is `50`.                                                   |
| `CLAIM_WORK_MEM`                                  | PostgreSQL `work_mem` setting for the run claim query. Helps optimize complex sorting operations. Set to a valid PostgreSQL memory value (e.g., `32MB`, `64MB`, `1GB`). Set to empty string to disable.<br>Default: disabled in dev/test, `32MB` in production. |
| `PORT`                                            | The port your Phoenix app runs on                                                                                                                                                                                                                               |
| `PROMEX_DATASOURCE_ID`                            | The datasource that PromEx will use if configured to push initial dashboards to Grafana. Defaults to an empty string.                                                                                                                                           |
| `PROMEX_ENABLED`                                  | Enables PromEx tracking and publishing of metrics if set to 'true' or 'yes'. Defaults to false.                                                                                                                                                                 |
| `PROMEX_ENDPOINT_SCHEME`                          | The scheme needed when connecting to the Promex Endpoint. Defaults to https.                                                                                                                                                                                    |
| `PROMEX_EXPENSIVE_METRICS_ENABLED`                | Certain metrics may be expensive to generate if Lightning is under load. If set to 'true', or 'yes' these metrics will be enabled. Defaults to 'false'.                                                                                                         |
| `PROMEX_GRAFANA_HOST`                             | This is used when PromEx is required to push data to a Grafana instance, e.g. when PromEx sets up initial dashboards.                                                                                                                                           |
| `PROMEX_GRAFANA_PASSWORD`                         | This is used when PromEx is required to push data to a Grafana instance, e.g. when PromEx sets up initial dashboards.                                                                                                                                           |
| `PROMEX_GRAFANA_USER`                             | This is used when PromEx is required to push data to a Grafana instance, e.g. when PromEx sets up initial dashboards.                                                                                                                                           |
| `PROMEX_METRICS_ENDPOINT_AUTHORIZATION_REQUIRED`  | If set to 'true' or 'yes', the PromEx endpoint on Lightning will require consumers to provide credentials for authorization. Defaults to 'true'.                                                                                                                |
| `PROMEX_METRICS_ENDPOINT_TOKEN`                   | A Bearer token that the consumer of the promEx endpoint must provide in the Authorization header. Defaults to a random series of bytes.                                                                                                                         |
| `PROMEX_UPLOAD_GRAFANA_DASHBOARDS_ON_START`       | Instructs PromEx to upload iniital dashboards to a Grafana instance if set to 'true' or 'yes'. Defaults to false.                                                                                                                                               |
| `PRIMARY_ENCRYPTION_KEY`                          | A base64 encoded 32 character long string.<br>See [Encryption](#encryption).                                                                                                                                                                                    |
| `QUEUE_RESULT_RETENTION_PERIOD_MINUTES`           | The number of minutes to keep completed (successful) `ObanJobs` in the queue (not to be confused with runs and/or history)                                                                                                                                      |
| `SCHEMAS_PATH`                                    | Path to the credential schemas that provide forms for different adaptors                                                                                                                                                                                        |
| `ADAPTORS_REGISTRY_JSON_PATH`                     | Path to adaptor registry file. When provided, the app will attempt to read from it then later fallback to the internet                                                                                                                                          |
| `SECRET_KEY_BASE`                                 | A secret key used as a base to generate secrets for encrypting and signing data.                                                                                                                                                                                |
| `SENTRY_DSN`                                      | If using Sentry for error monitoring, your DSN                                                                                                                                                                                                                  |
| `UI_METRICS_ENABLED`                              | Enable serverside tracking of certain metrics related to the UI. This s temporary functionality. Defaults to `false`.                                                                                                                                           |
| `URL_HOST`                                        | The host used for writing URLs (e.g., `demo.openfn.org`)                                                                                                                                                                                                        |
| `URL_PORT`                                        | The port, usually `443` for production                                                                                                                                                                                                                          |
| `URL_SCHEME`                                      | The scheme for writing URLs (e.g., `https`)                                                                                                                                                                                                                     |
| `USAGE_TRACKER_HOST`                              | The host that receives usage tracking submissions<br>(defaults to https://impact.openfn.org)                                                                                                                                                                    |
| `USAGE_TRACKING_DAILY_BATCH_SIZE`                 | The number of days that will be reported on with each run of `UsageTracking.DayWorker`. This will only have a noticeable effect in cases where there is a backlog or where reports are being generated retroactively (defaults to 10).                          |
| `USAGE_TRACKING_ENABLED`                          | Enables the submission of anonymized usage data to OpenFn (defaults to `true`)                                                                                                                                                                                  |
| `USAGE_TRACKING_RESUBMISSION_BATCH_SIZE`          | The number of failed reports that will be submitted on each resubmission run (defaults to 10)                                                                                                                                                                   |
| `USAGE_TRACKING_RUN_CHUNK_SIZE`                   | The size of each batch of runs that is streamed from the database when generating UsageTracking reports (default 100). Decreasing this may decrease memory consumption when generating reports.                                                                 |
| `USAGE_TRACKING_UUIDS`                            | Indicates whether submissions should include cleartext UUIDs or not. Options are `cleartext` or `hashed_only`, with the default being `hashed_only`.                                                                                                            |
| `REQUIRE_EMAIL_VERIFICATION`                      | Indicates whether user email addresses should be verified. Defaults to `false`.                                                                                                                                                                                 |

### AI Chat

🧪 **Experimental**

Lightning can be configured to use an AI chatbot for user interactions.

See [openfn/apollo](https://github.com/OpenFn/apollo) for more information on
the Apollo AI service.

The following environment variables are required:

- `AI_ASSISTANT_API_KEY` - API key to use the assistant. This currently requires
  an Anthropic key.
- `APOLLO_ENDPOINT` - the endpoint for the OpenFn Apollo AI service.

### Kafka Triggers

🧪 **Experimental**

Lightning workflows can be configured with a trigger that will consume messages
from a Kafka Cluster. By default this is disabled and you will not see the
option to create a Kafka trigger in the UI, nor will the Kafka consumer groups
be running.

To enable this feature set the `KAFKA_TRIGGERS_ENABLED` environment variable to
`yes` and restart Lightning. Please note that, if you enable this feature and
then create some Kafka triggers and then disable the feature, you will not be
able to edit any triggers created before the feature was disabled.

#### Performance Tuning

The number of Kafka consumers in the consumer group can be modified by setting
the `KAFKA_NUMBER_OF_CONSUMERS` environment variable. The default value is
currently 1. The optimal setting is one consumer per topic partition. NOTE: This
setting will move to KafkaConfiguration as it will be trigger-specific.

The number of messages that the Kafka consumer will forward is rate-limited by
the `KAFKA_NUMBER_OF_MESSAGES_PER_SECOND` environment variable. This can be set
to a value of less than 1 (minimum 0.1) and will converted (and rounded-down) to
an integer value of messages over a 10-second interval (e.g. 0.15 becomes 1
message every 10 seconds). The default value is 1.

Processing concurrency within the Kafka Broadway pipeline is controlled by the
`KAFKA_NUMBER_OF_PROCESSORS` environment variable. Modifying this, modifies the
number of processors that are downstream of the Kafka consumer, so an increase
in this value should increase throughput (when factoring in the rate limit set
by `KAFKA_NUMBER_OF_MESSAGES_PER_SECOND`). The default value is 1.

#### Deduplication

Each Kafka trigger maintains record of the topic, partition and offset for each
message received. This to protect against the ingestion of duplicate messages
from the cluster. These records are periodically cleaned out. The duration for
which they are retained is controlled by
`KAFKA_DUPLICATE_TRACKING_RETENTION_SECONDS`. The default value is 3600.

#### Disabling Kafka Triggers

After a Kafka consumer group connects to a Kafka cluster, the cluster will track
the last committed offset for a given consumer group ,to ensure that the
consumer group receives the correct messages.

This data is retained for a finite period. If an enabled Kafka trigger is
disabled for longer than the offset retention period the consumer group offset
data will be cleared.

If the Kafka trigger is re-enabled after the offset data has been cleared, this
will result in the consumer group reverting to what has been configured as the
'Initial offset reset policy' for the trigger. This may result in the
duplication of messages or even data loss.

It is recommended that you check the value of the `offsets.retention.minutes`
for the Kafka cluster to determine what the cluster's retention period is, and
consider this when disabling a Kafka trigger for an extended period.

#### Failure notifications

Under certain failure conditions, a Kafka trigger will send an email to certain
users that are associated with a project. After each email an embargo is applied
to ensure that Lightning does not flood the recipients with email. The length of
the embargo is controlled by the `KAFKA_NOTIFICATION_EMBARGO_SECONDS` ENV
variable.

#### Persisting Failed Messages

**PLEASE NOTE: If alternate file storage is not enabled, messages that fail to
be persisted will not be retained by Lightning and this can result in data loss,
if the Kafka cluster can not make these messages available again.**

If a Kafka message fails to be persisted as a WorkOrder, Run and Dataclip, the
option exists to write the failed message to a location on the local file
system. If this option is enabled by setting `KAFKA_ALTERNATE_STORAGE_ENABLED`,
then the `KAFKA_ALTERNATE_STORAGE_PATH` ENV variable must be set to the path
that exists and is writable by Lightning. The location should also be suitably
protected to prevent data exposure as Lightning **will not encrypt** the message
contents when writing it.

If the option is enabled and a message fails to be persisted, Lightning will
create a subdirectory named with the id if the affected trigger's workflow in
the location specified by `KAFKA_ALTERNATE_STORAGE_PATH` (assuming such a
subdirectory does not already exist). Lightning will serialise the message
headers and data as received by the Kafka pipeline and write this to a file
within the subdirectory. The file will be named based on the pattern
`<trigger_id>_<message_topic>_<message_partition>_<message_offset>.json`.

To recover the persisted messages, it is suggested that the affected triggers be
disabled before commencing. Once this is done, the following code needs to be
run from an IEx console on each node that is running Lightning:

```elixir
Lightning.KafkaTriggers.MessageRecovery.recover_messages(
  Lightning.Config.kafka_alternate_storage_file_path()
)
```

Further details regarding the behaviour of `MessageRecovery.recover_messages/1`
can be found in the module documentation of `MessageRecovery`. Recovered
messages will have the `.json` extension modified to `.json.recovered` but they
will be left in place. Future recovery runs will not process files that have
been marked as recovered.

Once all files have either been recovered or discarded, the triggers can be
enabled once more.

### Google Oauth2

Using your Google Cloud account, provision a new OAuth 2.0 Client with the 'Web
application' type.

Set the callback url to: `https://<ENDPOINT DOMAIN>/authenticate/callback`.
Replacing `ENDPOINT DOMAIN` with the host name of your instance.

Once the client has been created, get/download the OAuth client JSON and set the
following environment variables:

| **Variable**           | Description                                   |
| ---------------------- | --------------------------------------------- |
| `GOOGLE_CLIENT_ID`     | Which is `client_id` from the client details. |
| `GOOGLE_CLIENT_SECRET` | `client_secret` from the client details.      |

### Salesforce Oauth2

Using your Salesforce developer account, create a new Oauth 2.0 connected
application.

Set the callback url to: `https://<ENDPOINT DOMAIN>/authenticate/callback`.
Replacing `ENDPOINT DOMAIN` with the host name of your instance.

Grant permissions as desired.

Once the client has been created set the following environment variables:

| **Variable**               | Description                                                           |
| -------------------------- | --------------------------------------------------------------------- |
| `SALESFORCE_CLIENT_ID`     | Which is `Consumer Key` from the "Manage Consumer Details" screen.    |
| `SALESFORCE_CLIENT_SECRET` | Which is `Consumer Secret` from the "Manage Consumer Details" screen. |

### Webhook Retry Configuration

Lightning automatically retries webhook processing on **transient database
connection errors** using exponential backoff. This helps prevent data loss
during brief database outages.

The following environment variables control webhook retry behavior:

| **Variable**                     | **Description**                                                                                  | **Default** |
| -------------------------------- | ------------------------------------------------------------------------------------------------ | ----------: |
| `WEBHOOK_RETRY_MAX_ATTEMPTS`     | Maximum number of attempts (the first attempt runs immediately; backoffs occur between retries). |         `5` |
| `WEBHOOK_RETRY_INITIAL_DELAY_MS` | Initial backoff delay in milliseconds.                                                           |       `100` |
| `WEBHOOK_RETRY_MAX_DELAY_MS`     | Maximum backoff delay in milliseconds.                                                           |     `10000` |
| `WEBHOOK_RETRY_BACKOFF_FACTOR`   | Multiplier for exponential backoff (each delay × this factor, up to the max delay).              |         `2` |
| `WEBHOOK_RETRY_TIMEOUT_MS`       | Total time budget for all attempts (including sleeps) in milliseconds.                           |     `60000` |
| `WEBHOOK_RETRY_JITTER`           | Whether to add \~0–25% randomization to each delay to avoid thundering herd (`true`/`false`).    |      `true` |

**How backoff works (defaults, jitter off):** attempt 1 runs immediately; on
failure we sleep and retry up to `WEBHOOK_RETRY_MAX_ATTEMPTS - 1` times with
exponential delays starting at `WEBHOOK_RETRY_INITIAL_DELAY_MS` and multiplying
by `WEBHOOK_RETRY_BACKOFF_FACTOR`, capped by `WEBHOOK_RETRY_MAX_DELAY_MS`.
Example sequence: `100ms → 200ms → 400ms → 800ms` (four sleeps for five total
attempts), stopping sooner if `WEBHOOK_RETRY_TIMEOUT_MS` elapses.

**Server timeout alignment:** Set your Phoenix `IDLE_TIMEOUT` to be **at least**
`WEBHOOK_RETRY_TIMEOUT_MS + 15000` (in milliseconds) so long retries finish
before the connection is closed.
