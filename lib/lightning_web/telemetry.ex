defmodule LightningWeb.Telemetry do
  @moduledoc """
  Assorted metrics to collect during runtime.

  See https://hexdocs.pm/phoenix/telemetry.html
  """
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("lightning.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("lightning.repo.query.decode_time",
        unit: {:native, :millisecond},
        description:
          "The time spent decoding the data received from the database"
      ),
      summary("lightning.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("lightning.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("lightning.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Business metrics
      summary("lightning.api.webhook",
        event_name: [:lightning, :workorder, :webhook, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        description:
          "Time taken to process a successful HTTP request to a webhook trigger URL",
        keep: &match?(%{status: :ok}, &1)
      ),
      distribution("lightning.api.webhook",
        event_name: [:lightning, :workorder, :webhook, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        description:
          "Time taken to process a successful HTTP request to a webhook trigger URL",
        keep: &match?(%{status: :ok}, &1)
      ),
      summary("lightning.ui.history",
        event_name: [:lightning, :ui, :projects, :history, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        description: "Time required for history page load"
      ),
      distribution("lightning.ui.history",
        event_name: [:lightning, :ui, :projects, :history, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        description: "Time required for history page load"
      )
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {LightningWeb, :count_users, []}
    ]
  end

  @doc """
  Convenience function that wraps `:telemetry.span/3`.

  Given a function with an arity of zero, it passes the `metadata` argument
  out with the result of the function.

  If you need to control the `metadata`, pass in a function with an arity of
  one. It will be called with the metadata provided and expects the result and
  the updated metadata to be returned in a tuple.

  Example:

      with_span([:my, span], %{project_id: 123}, fn -> get_project(456) end)

  Or when you want to extend the metadata:

      with_span([:my, :span], %{user_id: 123}, fn _metadata ->
        project = get_project(456)
        {project, %{project_id: project.id}}
      end)
  """
  @spec with_span(
          :telemetry.event_prefix(),
          :telemetry.event_metadata(),
          (:telemetry.event_metadata() -> {any, :telemetry.event_metadata()})
          | (-> any)
        ) :: any
  def with_span(prefix, metadata, func) when is_function(func) do
    :telemetry.span(
      prefix,
      metadata,
      fn ->
        if is_function(func, 1) do
          func.(metadata)
        else
          {func.(), metadata}
        end
      end
    )
  end
end
