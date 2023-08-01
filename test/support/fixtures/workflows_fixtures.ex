defmodule Lightning.WorkflowsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Lightning.Workflows` context.
  """

  import Lightning.ProjectsFixtures

  @doc """
  Generate a workflow.
  """
  @spec workflow_fixture(attrs :: Keyword.t()) ::
          Lightning.Workflows.Workflow.t()
  def workflow_fixture(attrs \\ []) when is_list(attrs) do
    {:ok, workflow} =
      attrs
      |> Keyword.put_new_lazy(:project_id, fn -> project_fixture().id end)
      |> Enum.into(%{
        name:
          Enum.take_random(
            ~c"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ ",
            10
          )
          |> to_string()
      })
      |> Lightning.Workflows.create_workflow()

    workflow
  end

  def build_workflow(attrs \\ []) do
    Ecto.Changeset.cast(
      %Lightning.Workflows.Workflow{},
      %{
        "project_id" => attrs[:project_id] || project_fixture().id,
        "id" => Ecto.UUID.generate()
      },
      [:project_id, :id]
    )
  end
end
