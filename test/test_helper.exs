Code.put_compiler_option(:warnings_as_errors, false)
# Report which tests are synchronous
# Rexbug.start("ExUnit.Server.add_sync_module/_")

:ok = Application.ensure_started(:ex_machina)

Mimic.copy(:hackney)
Mimic.copy(File)
Mimic.copy(IO)
Mimic.copy(Lightning.FailureEmail)
Mimic.copy(Lightning.WorkOrderService)
Mimic.copy(Mix.Tasks.Lightning.InstallSchemas)

assert_receive_timeout =
  System.get_env("ASSERT_RECEIVE_TIMEOUT", "100") |> String.to_integer()

ExUnit.configure(
  formatters: [JUnitFormatter, ExUnit.CLIFormatter],
  assert_receive_timeout: assert_receive_timeout
)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Lightning.Repo, :manual)
