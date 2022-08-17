defmodule Lightning.ProjectsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Lightning.Projects` context.
  """

  @doc """
  Generate a project.
  """
  @spec project_fixture(attrs :: Keyword.t()) :: Lightning.Projects.Project.t()
  def project_fixture(attrs \\ []) when is_list(attrs) do
    {:ok, project} =
      attrs
      |> Enum.into(%{
        name: "a-test-project",
        project_users: []
      })
      |> Lightning.Projects.create_project()

    project
  end
end
