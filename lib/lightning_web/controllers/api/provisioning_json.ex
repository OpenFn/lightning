defmodule LightningWeb.API.ProvisioningJSON do
  @moduledoc false

  alias Lightning.Projects.Project
  alias Lightning.Workflows.{Workflow, Edge}
  alias Lightning.Jobs.{Job, Trigger}

  def render("create.json", %{project: project, conn: _conn}) do
    %{"data" => as_json(project)}
  end

  def as_json(%Project{} = project) do
    Ecto.embedded_dump(project, :json)
    |> Map.put("workflows", Enum.map(project.workflows, &as_json/1))
  end

  def as_json(%Workflow{} = workflow) do
    Ecto.embedded_dump(workflow, :json)
    |> Map.put("jobs", Enum.map(workflow.jobs, &as_json/1))
    |> Map.put("triggers", Enum.map(workflow.triggers, &as_json/1))
    |> Map.put("edges", Enum.map(workflow.edges, &as_json/1))
  end

  def as_json(%Job{} = job) do
    Ecto.embedded_dump(job, :json)
    |> Map.take(~w(id adaptor enabled body name)a)
  end

  def as_json(%Trigger{} = trigger) do
    Ecto.embedded_dump(trigger, :json)
    |> Map.take(~w(id type cron_expression)a)
    |> drop_keys_with_nil_value()
  end

  def as_json(%Edge{} = edge) do
    Ecto.embedded_dump(edge, :json)
    |> Map.take(~w(id source_job_id source_trigger_id condition target_job_id)a)
    |> drop_keys_with_nil_value()
  end

  defp drop_keys_with_nil_value(map) do
    Map.reject(map, fn {_, v} -> is_nil(v) end)
  end
end
