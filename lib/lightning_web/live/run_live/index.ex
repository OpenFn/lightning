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

  @impl true
  def mount(_params, _session, socket) do
    run_statuses = [
      %RunStatusOption{id: :success, label: "Success", selected: true},
      %RunStatusOption{id: :failure, label: "Failure", selected: true},
      %RunStatusOption{id: :timeout, label: "Timeout", selected: true},
      %RunStatusOption{id: :crash, label: "Crash", selected: true},
      %RunStatusOption{id: :pending, label: "Pending", selected: true}
    ]

    workflows =
      Lightning.Workflows.get_workflows_for(socket.assigns.project)
      |> Enum.map(&{&1.name, &1.id})

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
     |> init_search_form(statuses: run_statuses, workflows: workflows)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(
       page_title: "Runs",
       run: %Run{}
     )
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    changeset = socket.assigns.changeset

    socket
    |> assign(
      options: Ecto.Changeset.fetch_field!(changeset, :options),
      page:
        Invocation.list_work_orders_for_project(
          socket.assigns.project,
          build_filter(changeset),
          params
        )
    )
  end

  @impl true
  def handle_info({:selected_statuses, statuses}, socket) do
    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.put_embed(:options, statuses)

    socket =
      socket
      |> assign(:changeset, changeset)
      |> assign(:options, statuses)

    {:noreply,
     socket
     |> push_patch(
       to:
         Routes.project_run_index_path(
           socket,
           :index,
           socket.assigns.project
           #  build_filter(changeset)
           #  |> Enum.into(%{})
         )
     )}
  end

  @impl true
  def handle_event(
        "validate",
        %{
          "run_search_form" => %{
            "workflow_id" => workflow_id,
            "date_after" => date_after,
            "date_before" => date_before
          }
        },
        socket
      ) do
    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.put_change(:workflow_id, workflow_id)
      |> Ecto.Changeset.put_change(:date_after, date_after)
      |> Ecto.Changeset.put_change(:date_before, date_before)

    socket =
      socket
      |> assign(:changeset, changeset)

    {:noreply,
     socket
     |> push_patch(
       to:
         Routes.project_run_index_path(
           socket,
           :index,
           socket.assigns.project
           # build_filter(changeset) |> Enum.into(%{})
         )
     )}
  end

  defp init_search_form(socket, statuses: statuses, workflows: workflows) do
    changeset =
      %RunSearchForm{}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(:options, statuses)

    socket
    |> assign(:changeset, changeset)
    |> assign(:workflows, workflows)
  end

  # return a keyword  list of criteria:value
  defp build_filter(changeset) do
    # fields = changeset |> Ecto.Changeset.apply_changes()

    status =
      Ecto.Changeset.fetch_field!(changeset, :options)
      |> Enum.filter(&(&1.selected in [true, "true"]))
      |> Enum.map(& &1.id)

    [
      status: status,
      workflow_id: Ecto.Changeset.fetch_field!(changeset, :workflow_id),
      date_after: Ecto.Changeset.fetch_field!(changeset, :date_after),
      date_before: Ecto.Changeset.fetch_field!(changeset, :date_before)
    ]
  end
end
