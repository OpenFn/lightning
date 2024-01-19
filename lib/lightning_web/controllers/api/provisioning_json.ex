defmodule LightningWeb.API.ProvisioningJSON do
  @moduledoc false

  alias Lightning.Projects.Project
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow

  def render("create.json", %{project: project, conn: _conn}) do
    %{"data" => as_json(project)}
  end

  def as_json(%Project{} = project) do
    Ecto.embedded_dump(project, :json)
    |> Map.put(
      "workflows",
      project.workflows
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(&as_json/1)
    )
  end

  def as_json(%Workflow{} = workflow) do
    Ecto.embedded_dump(workflow, :json)
    |> Map.put(
      "jobs",
      workflow.jobs
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(&as_json/1)
    )
    |> Map.put(
      "triggers",
      workflow.triggers
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(&as_json/1)
    )
    |> Map.put(
      "edges",
      workflow.edges
      |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)
      |> Enum.map(&as_json/1)
    )
  end

  def as_json(%Job{} = job) do
    Ecto.embedded_dump(job, :json)
    |> Map.take(~w(id adaptor body name)a)
  end

  def as_json(%Trigger{} = trigger) do
    Ecto.embedded_dump(trigger, :json)
    |> Map.take(~w(id type cron_expression enabled)a)
    |> drop_keys_with_nil_value()
  end

  def as_json(%Edge{} = edge) do
    Ecto.embedded_dump(edge, :json)
    |> Map.take(~w(
      id enabled source_job_id source_trigger_id
      condition_type condition_label condition_expression target_job_id
    )a)
    |> drop_keys_with_nil_value()
  end

  defp drop_keys_with_nil_value(map) do
    Map.reject(map, fn {_, v} -> is_nil(v) end)
  end
end
