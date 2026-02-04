defmodule Lightning.PromEx do
  @moduledoc """
  Be sure to add the following to finish setting up PromEx:

  1. Update your configuration (config.exs, dev.exs, prod.exs, releases.exs, etc) to
     configure the necessary bit of PromEx. Be sure to check out `PromEx.Config` for
     more details regarding configuring PromEx:
     ```
     config :lightning, Lightning.PromEx,
       disabled: false,
       manual_metrics_start_delay: :no_delay,
       drop_metrics_groups: [],
       grafana: :disabled,
       metrics_server: :disabled
     ```

  2. Add this module to your application supervision tree. It should be one of the first
     things that is started so that no Telemetry events are missed. For example, if PromEx
     is started after your Repo module, you will miss Ecto's init events and the dashboards
     will be missing some data points:
     ```
     def start(_type, _args) do
       children = [
         Lightning.PromEx,

         ...
       ]

       ...
     end
     ```

  3. Update your `endpoint.ex` file to expose your metrics (or configure a standalone
     server using the `:metrics_server` config options). Be sure to put this plug before
     your `Plug.Telemetry` entry so that you can avoid having calls to your `/metrics`
     endpoint create their own metrics and logs which can pollute your logs/metrics given
     that Prometheus will scrape at a regular interval and that can get noisy:
     ```
     defmodule LightningWeb.Endpoint do
       use Phoenix.Endpoint, otp_app: :lightning

       ...

       plug PromEx.Plug, prom_ex_module: Lightning.PromEx

       ...
     end
     ```

  4. Update the list of plugins in the `plugins/0` function return list to reflect your
     application's dependencies. Also update the list of dashboards that are to be uploaded
     to Grafana in the `dashboards/0` function.
  """

  use PromEx, otp_app: :lightning

  alias Lightning.Config
  alias PromEx.Plugins

  @impl true
  def plugins do
    external_plugins = Lightning.Config.external_metrics_module().plugins()

    [
      # PromEx built in plugins
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix,
       router: LightningWeb.Router, endpoint: LightningWeb.Endpoint},
      Plugins.Ecto,
      {Plugins.Oban, oban_supervisors: [Lightning.Oban]},
      Plugins.PhoenixLiveView,
      # Add your own PromEx metrics plugins
      {
        Lightning.Runs.PromExPlugin,
        run_queue_metrics_period_seconds:
          Config.metrics_run_queue_metrics_period_seconds(),
        run_performance_age_seconds: Config.metrics_run_performance_age_seconds(),
        stalled_run_threshold_seconds:
          Config.metrics_stalled_run_threshold_seconds(),
        unclaimed_run_threshold_seconds:
          Config.metrics_unclaimed_run_threshold_seconds()
      },
      Lightning.PromExTestPlugin,
      Lightning.Projects.SandboxPromExPlugin
    ] ++ external_plugins
  end

  def seed_event_metrics do
    Lightning.Config.external_metrics_module().seed_event_metrics()
    Lightning.PromExTestPlugin.seed_event_metrics()
    Lightning.Runs.PromExPlugin.seed_event_metrics()
    Lightning.Projects.SandboxPromExPlugin.seed_event_metrics()
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id:
        Application.get_env(:lightning, Lightning.PromEx)[:datasource_id],
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      # PromEx built in Grafana dashboards
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"},
      {:prom_ex, "phoenix_live_view.json"}
      # {:prom_ex, "absinthe.json"},
      # {:prom_ex, "broadway.json"},

      # Add your dashboard definitions here with the format: {:otp_app, "path_in_priv"}
      # {:lightning, "/grafana_dashboards/user_metrics.json"}
    ]
  end
end
