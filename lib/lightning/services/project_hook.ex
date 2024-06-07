defmodule Lightning.Services.ProjectHook do
  @moduledoc """
  Allows handling project creation atomically without relying on async events.
  """
  @behaviour Lightning.Extensions.ProjectHooking

  import Lightning.Services.AdapterHelper

  alias Ecto.Changeset
  alias Lightning.Projects.Project

  @spec handle_create_project(map()) ::
          {:ok, Project.t()} | {:error, Changeset.t()}
  def handle_create_project(attrs) do
    adapter().handle_create_project(attrs)
  end

  defp adapter, do: adapter(:project_hook)
end
