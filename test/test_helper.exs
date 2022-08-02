# Report which tests are syncronous
# Rexbug.start("ExUnit.Server.add_sync_module/_")
Mimic.copy(:hackney)
Mimic.copy(Lightning.Pipeline.Runner)

ExUnit.configure(formatters: [JUnitFormatter, ExUnit.CLIFormatter])

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Lightning.Repo, :manual)
