# Script that tests out specific code paths and leveraging Telemetry writes
# the events out to a CSV file.
#
# Run using: `mix run benchmarking/load_tests.exs`

defmodule TelemetryCSVLogger do
  require Logger

  def handle_event(
        [:lightning, :create_dataclip, :stop] = event,
        %{duration: duration} = measurements,
        _metadata,
        output_file: file
      ) do
    log_received(event, measurements)

    IO.binwrite(file, "lightning.create_dataclip.stop, #{duration}\n")
  end

  def handle_event(
        [:lightning, :create_webhook_workorder, :stop] = event,
        %{duration: duration} = measurements,
        _metadata,
        output_file: file
      ) do
    log_received(event, measurements)

    IO.binwrite(file, "lightning.create_webhook_workorder.stop, #{duration}\n")
  end

  def handle_event(event, _measurements, _metadata, _config) do
    log_received(event)
  end

  defp native_to_microsecond(duration) do
    System.convert_time_unit(duration, :native, :microsecond)
  end

  defp log_received(event, %{duration: duration}) do
    duration = native_to_microsecond(duration)

    Logger.info(
      "Received #{event |> Enum.join(".")} event. Duration: #{duration}µs"
    )
  end

  defp log_received(event) do
    Logger.info("Received #{event |> Enum.join(".")} event.")
  end
end

telemetry_events = [
  [:lightning, :create_dataclip, :start],
  [:lightning, :create_dataclip, :stop],
  [:lightning, :create_dataclip, :exception],
  [:lightning, :create_webhook_workorder, :start],
  [:lightning, :create_webhook_workorder, :stop],
  [:lightning, :create_webhook_workorder, :exception]
]

filepath = Path.join(Path.dirname(__ENV__.file), "load_test_data.csv")
output_file = File.open!(filepath, [:append])

:ok =
  :telemetry.attach_many(
    "lightning-telemetry-metrics",
    telemetry_events,
    &TelemetryCSVLogger.handle_event/4,
    output_file: output_file
  )

# Time to persist a dataclip

{:ok, project} =
  Lightning.Projects.create_project(%{
    name: "a-test-project",
    project_users: []
  })

:telemetry.span(
  [:lightning, :create_dataclip],
  %{project: project},
  fn ->
    result =
      Lightning.Invocation.create_dataclip(%{
        body: %{},
        type: :http_request,
        project_id: project.id
      })

    {result, %{}}
  end
)

# Time from dataclip created to start of job (per workflow).

{:ok, project} =
  Lightning.Projects.create_project(%{
    name: "a-test-project",
    project_users: []
  })

{:ok, workflow} =
  Lightning.Workflows.create_workflow(%{
    name:
      Enum.take_random(
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ ',
        10
      )
      |> to_string(),
    project_id: project.id
  })

{:ok, job} =
  Lightning.Jobs.create_job(%{
    workflow_id: workflow.id,
    body: "fn(state => state)",
    enabled: true,
    name: "some name",
    adaptor: "@openfn/language-common",
    trigger: %{type: "webhook"}
  })

job = job |> Lightning.Repo.preload(:workflow)

{:ok, dataclip} =
  Lightning.Invocation.create_dataclip(%{
    body: %{},
    type: :http_request,
    project_id: project.id
  })

:telemetry.span(
  [:lightning, :create_webhook_workorder],
  %{job: job, dataclip: dataclip},
  fn ->
    result =
      Lightning.WorkOrderService.create_webhook_workorder(job, dataclip.body)
  end
)

File.close(output_file)
