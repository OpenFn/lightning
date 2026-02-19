# Report which tests are synchronous
# Rexbug.start("ExUnit.Server.add_sync_module/_")

Mox.defmock(Lightning.AuthProviders.OauthHTTPClient.Mock, for: Tesla.Adapter)
Mox.defmock(Lightning.MockSentry, for: Lightning.SentryBehaviour)
Mox.defmock(Lightning.Tesla.Mock, for: Tesla.Adapter)

:ok = Application.ensure_started(:ex_machina)

Mimic.copy(:hackney)
Mimic.copy(File)
Mimic.copy(IO)
Mimic.copy(Lightning.FailureEmail)
Mimic.copy(Mix.Tasks.Lightning.InstallSchemas)

# Other ExUnit configuration can be found in `config/runtime.exs`,
# for example to change the `assert_receive` timeout, configure it using the
# `ASSERT_RECEIVE_TIMEOUT` environment variable.
ExUnit.configure(
  formatters: [JUnitFormatter, ExUnit.CLIFormatter],
  capture_log: true
)

Mox.defmock(Lightning.Extensions.MockRateLimiter,
  for: Lightning.Extensions.RateLimiting
)

Mox.defmock(Lightning.Extensions.MockUsageLimiter,
  for: Lightning.Extensions.UsageLimiting
)

Mox.defmock(Lightning.Extensions.MockAccountHook,
  for: Lightning.Extensions.AccountHooking
)

Mox.defmock(Lightning.Extensions.MockCollectionHook,
  for: Lightning.Extensions.CollectionHooking
)

Mox.defmock(Lightning.Extensions.MockProjectHook,
  for: Lightning.Extensions.ProjectHooking
)

Mox.defmock(Lightning.MockConfig, for: Lightning.Config)
Application.put_env(:lightning, Lightning.Config, Lightning.MockConfig)

Mox.defmock(LightningMock, for: Lightning)
Application.put_env(:lightning, Lightning, LightningMock)

Application.put_env(:lightning, Lightning.Extensions,
  rate_limiter: Lightning.Extensions.MockRateLimiter,
  usage_limiter: Lightning.Extensions.MockUsageLimiter,
  run_queue: Lightning.Extensions.FifoRunQueue,
  account_hook: Lightning.Extensions.MockAccountHook,
  collection_hook: Lightning.Extensions.MockCollectionHook,
  project_hook: Lightning.Extensions.MockProjectHook,
  external_metrics: Lightning.Extensions.ExternalMetrics
)

Bureaucrat.start(
  writer: Bureaucrat.PostmanWriter,
  prefix: "Elixir.LightningWeb",
  default_path: "priv/static/postman.json"
)

ExUnit.start(formatters: [ExUnit.CLIFormatter, Bureaucrat.Formatter])
Ecto.Adapters.SQL.Sandbox.mode(Lightning.Repo, :manual)
