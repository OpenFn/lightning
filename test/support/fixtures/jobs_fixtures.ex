defmodule Lightning.JobsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Lightning.Jobs` context.
  """

  import Lightning.ProjectsFixtures
  import Lightning.WorkflowsFixtures

  @doc """
  Generate a job.
  """
  @spec job_fixture(attrs :: Keyword.t()) :: Lightning.Jobs.Job.t()
  def job_fixture(attrs \\ []) when is_list(attrs) do
    attrs =
      attrs
      |> Keyword.put_new_lazy(:project_id, fn -> project_fixture().id end)

    attrs =
      attrs
      |> Keyword.put_new_lazy(:workflow_id, fn ->
        workflow_fixture(project_id: attrs[:project_id]).id
      end)

    {:ok, job} =
      attrs
      |> Enum.into(%{
        body: "fn(state => state)",
        enabled: true,
        name: "some name",
        adaptor: "@openfn/language-common",
        trigger: %{type: "webhook"}
      })
      |> Lightning.Jobs.create_job()

    job
  end

  def workflow_job_fixture(attrs \\ []) do
    workflow =
      Ecto.Changeset.cast(
        %Lightning.Workflows.Workflow{},
        %{
          "name" => attrs[:workflow_name],
          "project_id" => attrs[:project_id] || project_fixture().id,
          "id" => Ecto.UUID.generate()
        },
        [:project_id, :id, :name]
      )

    attrs =
      attrs
      |> Enum.into(%{
        body: "fn(state => state)",
        enabled: true,
        name: "some name",
        adaptor: "@openfn/language-common",
        trigger: %{type: "webhook"}
      })

    %Lightning.Jobs.Job{}
    |> Ecto.Changeset.change()
    |> Lightning.Jobs.Job.put_workflow(workflow)
    |> Lightning.Jobs.Job.changeset(attrs)
    |> Lightning.Repo.insert!()
  end
end
