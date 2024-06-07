defmodule Lightning.Extensions.ProjectHooking do
  @moduledoc """
  Allows handling project creation atomically without relying on async events.
  """
  alias Ecto.Changeset
  alias Lightning.Projects.Project

  @callback handle_create_project(attrs :: map()) ::
              {:ok, Project.t()} | {:error, Changeset.t()}

  @callback handle_delete_project(Project.t()) ::
              {:ok, Project.t()} | {:error, Changeset.t()}
end
