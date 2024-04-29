Code.put_compiler_option(:warnings_as_errors, true)
# Report which tests are synchronous
# Rexbug.start("ExUnit.Server.add_sync_module/_")
Mox.defmock(Lightning.AuthProviders.OauthHTTPClient.Mock, for: Tesla.Adapter)
Mox.defmock(Lightning.GithubClient.Mock, for: Tesla.Adapter)
Mox.defmock(Lightning.Tesla.Mock, for: Tesla.Adapter)

:ok = Application.ensure_started(:ex_machina)

Mimic.copy(:hackney)
Mimic.copy(File)
Mimic.copy(IO)
Mimic.copy(Lightning.FailureEmail)
Mimic.copy(Lightning.WorkOrderService)
Mimic.copy(Mix.Tasks.Lightning.InstallSchemas)

# Other ExUnit configuration can be found in `config/runtime.exs`,
# for example to change the `assert_receive` timeout, configure it using the
# `ASSERT_RECEIVE_TIMEOUT` environment variable.
ExUnit.configure(
  formatters: [JUnitFormatter, ExUnit.CLIFormatter],
  exclude: [:integration]
)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Lightning.Repo, :manual)

Mox.defmock(Lightning.Extensions.MockRateLimiter,
  for: Lightning.Extensions.RateLimiting
)

Mox.defmock(Lightning.Extensions.MockUsageLimiter,
  for: Lightning.Extensions.UsageLimiting
)

Application.put_env(:lightning, Lightning.Extensions,
  rate_limiter: Lightning.Extensions.MockRateLimiter,
  usage_limiter: Lightning.Extensions.MockUsageLimiter,
  run_queue: Lightning.Extensions.FifoRunQueue
)
