defmodule LightningWeb.Hooks do
  @moduledoc """
  LiveView Hooks
  """
  import Phoenix.LiveView

  @doc """
  Finds and assigns a project to the socket
  """
  def on_mount(:project_scope, %{"project_id" => project_id}, _session, socket) do
    {:cont,
     socket |> assign(project: Lightning.Projects.get_project(project_id))}
  end
end
