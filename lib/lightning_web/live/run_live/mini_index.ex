defmodule LightningWeb.RunLive.MiniIndex do
  @moduledoc """
  A compact history table component designed for embedding in smaller spaces
  like workflow editor sidebars, dashboard panels, or collapsible sections.

  This is a LiveComponent (not LiveView) since it's designed to be embedded
  within other LiveViews.
  """
    use LightningWeb, :live_component

  import LightningWeb.LiveHelpers, only: [display_short_uuid: 1]
  import Ecto.Query

  alias Lightning.WorkOrder
  alias Lightning.Repo
  alias LightningWeb.RunLive.Components

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      case assigns[:action] do
        :refresh ->
          socket |> load_data()
        _ ->
          socket |> load_data()
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_workorder", %{"workorder_id" => workorder_id}, socket) do
    %{expanded_workorders: expanded} = socket.assigns

    new_expanded =
      if MapSet.member?(expanded, workorder_id) do
        MapSet.delete(expanded, workorder_id)
      else
        MapSet.put(expanded, workorder_id)
      end

    {:noreply, assign(socket, expanded_workorders: new_expanded)}
  end

  @impl true
  def handle_event("select_run", %{"run_id" => run_id}, socket) do
    send(self(), {:run_selected, run_id})
    {:noreply, assign(socket, selected_run_id: run_id)}
  end

    defp load_data(socket) do
    %{workflow_id: workflow_id} = socket.assigns

    # Get last 7 days of activity, limit to 20 items
    from_date = DateTime.utc_now() |> DateTime.add(-7, :day)

    workorders_with_runs =
      from(wo in WorkOrder,
        where: wo.workflow_id == ^workflow_id
               and wo.inserted_at >= ^from_date,
        order_by: [desc: wo.inserted_at],
        limit: 20,
        preload: [runs: [:work_order]]
      )
      |> Repo.all()

    socket
    |> assign(
      workorders_with_runs: workorders_with_runs,
      expanded_workorders: socket.assigns[:expanded_workorders] || MapSet.new(),
      selected_run_id: socket.assigns[:selected_run_id],
      loading: false
    )
  end

  defp format_compact_date(datetime) do
    month_names = ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
    month_name = Enum.at(month_names, datetime.month - 1)

    "#{String.pad_leading(to_string(datetime.day), 2, "0")}-#{month_name} #{String.pad_leading(to_string(datetime.hour), 2, "0")}:#{String.pad_leading(to_string(datetime.minute), 2, "0")}"
  end

  defp format_duration(started_at, finished_at) do
    if finished_at do
      diff = DateTime.diff(finished_at, started_at, :millisecond)

      cond do
        diff < 1000 -> "#{diff}ms"
        diff < 60_000 -> "#{Float.round(diff / 1000, 1)}s"
        diff < 3_600_000 -> "#{div(diff, 60_000)}m #{div(rem(diff, 60_000), 1000)}s"
        true -> "#{div(diff, 3_600_000)}h #{div(rem(diff, 3_600_000), 60_000)}m"
      end
    else
      "-"
    end
  end


end
