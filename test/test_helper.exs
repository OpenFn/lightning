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

# Other ExUnit configuration can be found in `config/runtime.exs`,
# for example to change the `assert_receive` timeout, configure it using the
# `ASSERT_RECEIVE_TIMEOUT` environment variable.
ExUnit.configure(formatters: [JUnitFormatter, ExUnit.CLIFormatter])

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Lightning.Repo, :manual)
