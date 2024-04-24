defmodule Lightning.Extensions.NewProject do
  @moduledoc """
  Runtime limiting stub for Lightning.
  """
  @behaviour Lightning.Extensions.CreateProject

  alias Lightning.Repo

  @impl true
  def create_project(attrs),
    do: Lightning.Projects.create_project(Repo, attrs)
end
