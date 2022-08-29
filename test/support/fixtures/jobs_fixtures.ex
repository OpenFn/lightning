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
  @spec job_fixture(attrs :: []) :: Lightning.Jobs.Job.t()
  def job_fixture(attrs \\ []) when is_list(attrs) do
    {:ok, job} =
      attrs
      |> Keyword.put_new_lazy(:project_id, fn -> project_fixture().id end)
      |> Enum.into(%{
        body: "fn(state => state)",
        enabled: true,
        name: "some name",
        adaptor: "@openfn/language-common",
        trigger: %{},
        workflow_id: workflow_fixture().id
      })
      |> Lightning.Jobs.create_job()

    job
  end
end
