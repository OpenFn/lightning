# Report which tests are synchronous
# Rexbug.start("ExUnit.Server.add_sync_module/_")

Mox.defmock(Lightning.AuthProviders.OauthHTTPClient.Mock, for: Tesla.Adapter)
Mox.defmock(Lightning.MockSentry, for: Lightning.SentryBehaviour)
Mox.defmock(Lightning.Tesla.Mock, for: Tesla.Adapter)

Mox.defmock(Lightning.Adaptors.StrategyMock, for: Lightning.Adaptors.Strategy)

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

# Pin the `Lightning.Adaptors.IconCache` on-disk path to a per-OS-PID
# directory and wipe it at startup so:
#   1. Each `mix test` invocation begins with an empty icon cache —
#      `System.unique_integer/1` resets per-VM and recycles, so without
#      this, leftover files from a prior run can mask a Mox expectation
#      by short-circuiting `IconCache.cached?/4`.
#   2. Concurrent `mix test` invocations (different tmux panes, parallel
#      CI shards) use distinct directories and never collide — each BEAM
#      has its own OS PID.
icon_dir =
  Path.join([
    System.tmp_dir!(),
    "lightning_test_icons",
    System.pid()
  ])

File.rm_rf!(icon_dir)
File.mkdir_p!(icon_dir)

Application.put_env(
  :lightning,
  Lightning.Adaptors,
  Application.get_env(:lightning, Lightning.Adaptors, [])
  |> Keyword.put(:icon_path, icon_dir)
)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Lightning.Repo, :manual)
