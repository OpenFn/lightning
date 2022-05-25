defmodule LightningWeb.RunLive.Index do
  @moduledoc """
  Index Liveview for Runs
  """
  use LightningWeb, :live_view

  alias Lightning.Invocation
  alias Lightning.Invocation.Run

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(active_menu_item: :runs)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(
      runs: Invocation.list_runs_for_project(socket.assigns.project),
      page_title: "Runs",
      run: %Run{}
    )
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    socket
    |> assign(:page_title, "Run")
    |> assign(:run, Invocation.get_run!(id))
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    run = Invocation.get_run!(id)
    {:ok, _} = Invocation.delete_run(run)

    {:noreply,
     socket
     |> assign(runs: Invocation.list_runs_for_project(socket.assigns.project))}
  end

  def show_run(assigns) do
    ~H"""
    <ul>
      <li>
        <strong>Log:</strong>
        <%= @run.log %>
      </li>

      <li>
        <strong>Exit code:</strong>
        <%= @run.exit_code %>
      </li>

      <li>
        <strong>Started at:</strong>
        <%= @run.started_at %>
      </li>

      <li>
        <strong>Finished at:</strong>
        <%= @run.finished_at %>
      </li>
    </ul>

    <span>
      <%= live_redirect("Back",
        to: Routes.project_run_index_path(@socket, :index, @project.id)
      ) %>
    </span>
    """
  end
end
