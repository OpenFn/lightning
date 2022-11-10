defmodule LightningWeb.RunLive.Index do
  @moduledoc """
  Index Liveview for Runs
  """
  use LightningWeb, :live_view

  alias Lightning.Invocation
  alias Lightning.Invocation.Run

  alias Lightning.RunSearchForm
  alias Lightning.RunSearchForm.RunStatusOption

  on_mount {LightningWeb.Hooks, :project_scope}

  @run_statuses [
    %RunStatusOption{id: :success, label: "Success", selected: true},
    %RunStatusOption{id: :failure, label: "Failure", selected: true},
    %RunStatusOption{id: :timeout, label: "Timeout", selected: true},
    %RunStatusOption{id: :crash, label: "Crash", selected: true}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       active_menu_item: :runs,
       work_orders: [],
       pagination_path:
         &Routes.project_run_index_path(
           socket,
           :index,
           socket.assigns.project,
           &1
         )
     )
     |> assign_multi_select_options(@run_statuses)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do

    socket
    |> assign(
      page_title: "Runs",
      run: %Run{},
      page:
        Invocation.list_work_orders_for_project(socket.assigns.project, status: socket.assigns.run_statuses |> to_query())
    )
  end

  @impl true
  def handle_info({:updated_options, options}, socket) do
    {:noreply,
     assign_multi_select_options(socket, options)
     |> push_patch(
       to:
         Routes.project_run_index_path(
           socket,
           :index,
           socket.assigns.project
           #status: options |> to_query()
         ), replace: true
     )}
  end

  defp to_query(options) do
    options |> Enum.filter(&(&1.selected in [true, "true"])) |> Enum.map(& &1.id)
  end

  @impl true
  def handle_event("validate", %{"run_search_form" => multi_component}, socket) do
    options = multi_component["options"]

    {:noreply, assign_multi_select_options(socket, options)}
  end

  defp assign_multi_select_options(socket, statuses) do
    socket
    |> assign(:changeset, build_changeset(statuses))
    |> assign(:run_statuses, statuses)
  end

  defp build_changeset(options) do
    %RunSearchForm{}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_embed(:options, options)
  end
end
