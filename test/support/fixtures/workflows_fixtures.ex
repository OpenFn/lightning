defmodule Lightning.WorkflowsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Lightning.Workflows` context.
  """

  @doc """
  Generate a workflow.
  """
  @spec workflow_fixture(attrs :: Keyword.t()) ::
          Lightning.Workflows.Workflow.t()
  def workflow_fixture(attrs \\ []) when is_list(attrs) do
    {:ok, workflow} =
      attrs
      |> Enum.into(%{
        name: "a-test-workflow"
      })
      |> Lightning.Workflows.create_workflow()

    workflow
  end
end
