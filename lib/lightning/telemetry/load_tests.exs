# - move this load test to `benchmarks`
# - for metrics.ex either:
#   - make it do live dashboard things
#   - delete it
# - write a line o the csv with 'more or less' the raw data
#   - lightning.create_dataclip.stop   sum: duration


defmodule TelemetryCSVLogger do
  require Logger

  def handle_event(
        [:lightning, :create_dataclip, :start],
        _measurements,
        _metadata,
        file: file
      ) do
    File.write(file, )
    Logger.info("Received [:lightning, :create_dataclip, :start] event.")
  end

  def handle_event(
        [:lightning, :create_dataclip, :stop],
        %{duration: duration} = _measurements,
        _metadata,
        _config
      ) do
    Logger.info(
      "Received [:lightning, :create_dataclip, :stop] event. Duration: #{duration}"
    )
  end

  def handle_event(
        [:lightning, :create_dataclip, :exception],
        _measurements,
        _metadata,
        _config
      ) do
    Logger.info("Received [:lightning, :create_dataclip, :exception] event.")
  end

  def handle_event(
        [:lightning, :create_webhook_workorder, :start],
        _measurements,
        _metadata,
        _config
      ) do
    Logger.info(
      "Received [:lightning, :create_webhook_workorder, :start] event."
    )
  end

  def handle_event(
        [:lightning, :create_webhook_workorder, :stop],
        %{duration: duration} = _measurements,
        _metadata,
        _config
      ) do
    Logger.info(
      "Received [:lightning, :create_webhook_workorder, :stop] event. Duration: #{duration}"
    )
  end

  def handle_event(
        [:lightning, :create_webhook_workorder, :exception],
        _measurements,
        _metadata,
        _config
      ) do
    Logger.info(
      "Received [:lightning, :create_webhook_workorder, :exception] event."
    )
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

file = File.open("out.csv")

:ok =
  :telemetry.attach_many(
    "lightning-telemetry-metrics",
    telemetry_events,
    &TelemetryLogger.handle_event/4,
    file: file
  )

# Time to persist a dataclip

{:ok, project} =
  Lightning.Projects.create_project(%{
    name: "a-test-project",
    project_users: []
  })

:telemetry.span(
  [:lightning, :create_dataclip],
  %{project: project, binary_size: 12345},
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
  %{project: job, dataclip: dataclip},
  fn ->
    Lightning.WorkOrderService.subscribe(job.workflow.project_id)

    result =
      Lightning.WorkOrderService.create_webhook_workorder(job, dataclip.body)

    {result, %{}}
  end
)
