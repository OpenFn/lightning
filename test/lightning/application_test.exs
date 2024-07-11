defmodule Lightning.ApplicationTest do
  use Lightning.DataCase, async: true

  alias Lightning.Config

  import Lightning.ApplicationHelpers, only: [put_temporary_env: 3]

  describe ".oban_opts/0" do
    test "returns the Oban configuration with usage tracking cron options" do
      put_temporary_env(
        :lightning,
        :usage_tracking,
        enabled: true,
        daily_batch_size: 100,
        resubmission_batch_size: 100
      )

      before_config = Application.get_env(:lightning, Oban)
      plugins = before_config |> Keyword.fetch!(:plugins)
      before_cron_plugin = plugins |> Keyword.fetch!(Oban.Plugins.Cron)
      before_crontab = before_cron_plugin |> Keyword.fetch!(:crontab)

      expected_crontab = before_crontab ++ Config.usage_tracking_cron_opts()

      expected_plugins =
        Keyword.put(
          plugins,
          Oban.Plugins.Cron,
          crontab: expected_crontab
        )

      after_config = Lightning.Application.oban_opts()
      after_plugins = after_config |> Keyword.fetch!(:plugins)

      assert after_plugins == expected_plugins
    end
  end
end
