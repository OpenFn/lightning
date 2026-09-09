defmodule Lightning.ApplicationTest do
  # Not async: these tests swap :lightning, :apollo and Oban's config, which
  # every other test reads, and capture_log takes the whole Logger rather than
  # just what this process emits.
  use Lightning.DataCase, async: false

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

  describe ".apollo_pools/0" do
    test "gives Apollo's endpoint a pool carrying the connect timeout" do
      put_temporary_env(:lightning, :apollo,
        endpoint: "http://apollo.test:3000",
        connect_timeout: 1234,
        idle_timeout: 30_000,
        request_timeout: 300_000
      )

      pools = Lightning.Application.apollo_pools()

      assert %{conn_opts: [transport_opts: [timeout: 1234]]} =
               Map.new(pools["http://apollo.test:3000"])
    end

    # Finch raises on a key it cannot parse, which would take the node down at
    # boot over a setting the rest of the app treats as the assistant simply
    # being off.
    for {name, endpoint} <- [
          {"nothing configured", nil},
          {"not a url at all", "how did this get here"},
          {"a scheme Finch cannot pool", "ftp://apollo.test"},
          {"no host", "http://"}
        ] do
      test "adds no pool when the endpoint is #{name}" do
        put_temporary_env(:lightning, :apollo,
          endpoint: unquote(endpoint),
          connect_timeout: 5_000,
          idle_timeout: 30_000,
          request_timeout: 300_000
        )

        assert Map.keys(Lightning.Application.apollo_pools()) == [:default]
      end
    end
  end

  describe "boot warnings" do
    test "says so when APOLLO_TIMEOUT is still set" do
      put_temporary_env(:lightning, :apollo_timeout_env_still_set, true)

      logs =
        ExUnit.CaptureLog.capture_log(fn ->
          Lightning.Application.warn_if_apollo_timeout_still_set()
        end)

      assert logs =~
               "[AI Assistant] APOLLO_TIMEOUT is no longer read and the value you set is being ignored."
    end

    test "stays quiet when it is not" do
      put_temporary_env(:lightning, :apollo_timeout_env_still_set, false)

      logs =
        ExUnit.CaptureLog.capture_log(fn ->
          Lightning.Application.warn_if_apollo_timeout_still_set()
        end)

      refute logs =~ "[AI Assistant] APOLLO_TIMEOUT is no longer read"
    end

    test "says so when the connect timeout is above the idle timeout" do
      put_temporary_env(:lightning, :apollo,
        endpoint: "http://apollo.test:3000",
        connect_timeout: 60_000,
        idle_timeout: 30_000,
        request_timeout: 300_000
      )

      logs =
        ExUnit.CaptureLog.capture_log(fn ->
          Lightning.Application.warn_if_connect_timeout_is_unreachable()
        end)

      assert logs =~
               "[AI Assistant] APOLLO_CONNECT_TIMEOUT_MS is 60000ms but APOLLO_IDLE_TIMEOUT_MS is 30000ms"
    end

    test "stays quiet when the connect timeout fits inside the idle one" do
      put_temporary_env(:lightning, :apollo,
        endpoint: "http://apollo.test:3000",
        connect_timeout: 5_000,
        idle_timeout: 30_000,
        request_timeout: 300_000
      )

      logs =
        ExUnit.CaptureLog.capture_log(fn ->
          Lightning.Application.warn_if_connect_timeout_is_unreachable()
        end)

      refute logs =~ "APOLLO_CONNECT_TIMEOUT_MS"
    end

    # No env fiddling on purpose: this reads the shipped defaults, so raising
    # one of them past the drain window fails here rather than warning on every
    # production boot. The margin is 345s against 360s.
    test "stays quiet on the defaults we ship" do
      logs =
        ExUnit.CaptureLog.capture_log(fn ->
          Lightning.Application.warn_if_ai_jobs_outlive_the_drain_window()
          Lightning.Application.warn_if_connect_timeout_is_unreachable()
        end)

      refute logs =~ "[AI Assistant] An AI job may run for"
      refute logs =~ "[AI Assistant] APOLLO_CONNECT_TIMEOUT_MS is"
    end

    test "says so when an AI job can outlive Oban's drain window" do
      put_temporary_env(:lightning, :apollo,
        endpoint: "http://apollo.test:3000",
        connect_timeout: 5_000,
        idle_timeout: 30_000,
        request_timeout: :timer.minutes(10)
      )

      logs =
        ExUnit.CaptureLog.capture_log(fn ->
          Lightning.Application.warn_if_ai_jobs_outlive_the_drain_window()
        end)

      assert logs =~
               "[AI Assistant] An AI job may run for 645000ms but Oban stops draining"
    end
  end
end
