Code.put_compiler_option(:warnings_as_errors, true)
# Report which tests are synchronous
# Rexbug.start("ExUnit.Server.add_sync_module/_")

:ok = Application.ensure_started(:ex_machina)

Mimic.copy(:hackney)
Mimic.copy(File)
Mimic.copy(IO)
Mimic.copy(Lightning.Pipeline.Runner)
Mimic.copy(Lightning.FailureEmail)
Mimic.copy(Lightning.WorkOrderService)
Mimic.copy(Mix.Tasks.Lightning.InstallSchemas)

ExUnit.configure(formatters: [JUnitFormatter, ExUnit.CLIFormatter])

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Lightning.Repo, :manual)
