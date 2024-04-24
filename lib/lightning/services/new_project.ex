defmodule Lightning.Services.NewProject do
  @moduledoc """
  Adapter to call the extension when a project is initialized for new user.
  """
  @behaviour Lightning.Extensions.CreateProject

  import Lightning.Services.AdapterHelper

  @impl true
  def create_project(attrs) do
    adapter().create_project(attrs)
  end

  defp adapter, do: adapter(:new_project)
end
