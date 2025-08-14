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

  describe "add_additional_libcluster_topology/3" do
    setup do
      topologies =
        [
          dns: [
            strategy: Cluster.Strategy.Kubernetes.DNS,
            config: [
              service: System.get_env("K8S_HEADLESS_SERVICE"),
              application_name: "lightning",
              polling_interval: 5_000
            ]
          ]
        ]

      %{topologies: topologies}
    end

    test "adds libcluster_postgres if discovery via postgres is required", %{
      topologies: input_topologies
    } do
      discovery_via_postgres_enabled = true
      channel_name = "my-lightning-channel"

      expected_topologies = [
        dns: [
          strategy: Cluster.Strategy.Kubernetes.DNS,
          config: [
            service: System.get_env("K8S_HEADLESS_SERVICE"),
            application_name: "lightning",
            polling_interval: 5_000
          ]
        ],
        postgres: [
          strategy: LibclusterPostgres.Strategy,
          config:
            Keyword.merge(
              Lightning.Repo.config(),
              channel_name: channel_name
            )
        ]
      ]

      actual_topologies =
        Lightning.Application.add_additional_libcluster_topology(
          input_topologies,
          discovery_via_postgres_enabled,
          channel_name
        )

      assert actual_topologies == expected_topologies
    end

    test "does not add libcluster_postgres if not required", %{
      topologies: input_topologies
    } do
      discovery_via_postgres_enabled = false
      channel_name = "my-lightning-channel"

      actual_topologies =
        Lightning.Application.add_additional_libcluster_topology(
          input_topologies,
          discovery_via_postgres_enabled,
          channel_name
        )

      assert actual_topologies == input_topologies
    end
  end
end
