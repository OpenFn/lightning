defmodule LightningWeb.RunLive.WorkOrderComponent do
  @moduledoc """
  Work Order component
  """
  use LightningWeb, :live_component

  import LightningWeb.RunLive.Components
  import LightningWeb.RunLive.Components

  @impl true
  def update(
        %{work_order: work_order, project: project, can_rerun_job: can_rerun_job} =
          assigns,
        socket
      ) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(project: project, can_rerun_job: can_rerun_job)
     |> set_details(work_order)}
  end

  def update(%{work_order: work_order} = assigns, socket) do
    {:ok, socket |> assign(assigns) |> set_details(work_order)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  defp set_details(socket, work_order) do
    last_step = get_last_step(work_order)
    last_step_finished_at = format_finished_at(last_step)
    work_order_inserted_at = Calendar.strftime(work_order.inserted_at, "%c %Z")
    workflow_name = work_order.workflow.name || "Untitled"

    socket
    |> assign(
      work_order: work_order,
      runs: work_order.runs,
      last_step: last_step,
      last_step_finished_at: last_step_finished_at,
      work_order_inserted_at: work_order_inserted_at,
      workflow_name: workflow_name
    )
  end

  defp get_last_step(work_order) do
    work_order.runs
    |> List.first()
    |> case do
      nil -> nil
      run -> List.last(run.steps)
    end
  end

  defp format_finished_at(last_step) do
    case last_step do
      %{finished_at: %_{} = finished_at} ->
        Calendar.strftime(finished_at, "%c %Z")

      _ ->
        nil
    end
  end

  @impl true
  def handle_event("toggle_details", %{}, socket) do
    {:noreply,
     assign(
       socket,
       :show_details,
       !socket.assigns[:show_details]
     )}
  end

  def handle_event("toggle_runs", %{}, socket) do
    {:noreply,
     assign(
       socket,
       :show_prev_runs,
       !socket.assigns[:show_prev_runs]
     )}
  end

  def handle_event("toggle_selection", %{}, %{assigns: assigns} = socket) do
    send(
      self(),
      {:selection_toggled, {assigns.work_order, !assigns[:entry_selected]}}
    )

    {:noreply, assign(socket, :entry_selected, !assigns[:entry_selected])}
  end

  attr :show_details, :boolean, default: false
  attr :show_prev_runs, :boolean, default: false
  attr :entry_selected, :boolean, default: false

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={"workorder-#{@work_order.id}"}
      data-entity="work_order"
      role="rowgroup"
      class={if @entry_selected, do: "bg-gray-50", else: "bg-white"}
    >
      <div role="row" class="grid grid-cols-8 items-center">
        <div
          role="cell"
          class="col-span-3 py-1 px-4 text-sm font-normal text-left rtl:text-right text-gray-500"
        >
          <div class="flex gap-4 items-center">
            <form
              phx-change="toggle_selection"
              id={"selection-form-#{@work_order.id}"}
            >
              <input
                type="hidden"
                id={"id_#{@work_order.id}"}
                name="workorder_id"
                value={@work_order.id}
              />

              <input
                type="hidden"
                id={"unselect_#{@work_order.id}"}
                name="selected"
                value="false"
              />

              <input
                type="checkbox"
                id={"select_#{@work_order.id}"}
                name="selected"
                class="left-4 top-1/2 h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-600"
                value="true"
                {if @entry_selected, do: [checked: "checked"], else: []}
              />
            </form>
            <%= if @work_order.runs !== [] do %>
              <button
                id={"toggle_details_for_#{@work_order.id}"}
                class="w-auto rounded-full p-3 hover:bg-gray-100"
                phx-click="toggle_details"
                phx-target={@myself}
              >
                <%= if @show_details do %>
                  <Heroicons.chevron_up outline class="h-4 w-4 rounded-lg" />
                <% else %>
                  <Heroicons.chevron_down outline class="h-4 w-4 rounded-lg" />
                <% end %>
              </button>
            <% else %>
              <span class="w-auto p-3">
                <Heroicons.minus outline class="h-4 w-4 rounded-lg" />
              </span>
            <% end %>

            <div class="ml-3 py-2">
              <h1 class={"text-sm mb-1 #{unless @show_details, do: "truncate"}"}>
                <%= @workflow_name %>
              </h1>
              <span class="mt-2 text-gray-700">
                <span
                  title={@work_order.id}
                  class="font-normal text-xs whitespace-nowrap text-ellipsis
                    rounded-md font-mono inline-block"
                >
                  <%= display_short_uuid(@work_order.id) %>
                </span>
                &bull;
                <.link navigate={
                  ~p"/projects/#{@work_order.workflow.project_id}/dataclips/#{@work_order.dataclip_id}/show"
                }>
                  <span
                    title={@work_order.dataclip_id}
                    class="font-normal text-xs whitespace-nowrap text-ellipsis
                            p-1 rounded-md font-mono text-indigo-400 hover:underline
                            underline-offset-2 hover:text-indigo-500"
                  >
                    <%= display_short_uuid(@work_order.dataclip_id) %>
                  </span>
                </.link>
              </span>
            </div>
          </div>
        </div>
        <div
          class="py-1 px-4 text-sm font-normal text-left rtl:text-right text-gray-500"
          role="cell"
        >
          <.timestamp timestamp={@work_order.inserted_at} style={:wrapped} />
        </div>
        <div
          class="py-1 px-4 text-sm font-normal text-left rtl:text-right text-gray-500"
          role="cell"
        >
          <.timestamp timestamp={@work_order.last_activity} style={:wrapped} />
        </div>
        <div
          class="py-1 px-4 text-sm font-normal text-left rtl:text-right text-gray-500"
          role="cell"
        >
          --
        </div>
        <div
          class="py-1 px-4 text-sm font-normal text-left rtl:text-right text-gray-500"
          role="cell"
        >
          --
        </div>
        <div
          class="py-1 px-4 text-sm font-normal text-left rtl:text-right text-gray-500"
          role="cell"
        >
          <.state_pill state={@work_order.state} />
        </div>
      </div>
      <%= if @show_details do %>
        <%= for {run, index} <- @runs |> Enum.reverse() |> Enum.with_index(1) |> Enum.reverse() do %>
          <div
            id={"run_#{run.id}"}
            class={
              if index != Enum.count(@runs) and !@show_prev_runs,
                do: "hidden",
                else: ""
            }
          >
            <div>
              <div class="flex gap-1 items-center bg-gray-200 pl-28 text-xs py-2">
                <div>
                  Run
                  <.link navigate={~p"/projects/#{@project.id}/runs/#{run.id}"}>
                    <span
                      title={run.id}
                      class="font-normal text-xs whitespace-nowrap text-ellipsis
                            inline-block rounded-md font-mono
                            text-indigo-400 hover:underline underline-offset-2
                            hover:text-indigo-500"
                    >
                      <%= display_short_uuid(run.id) %>
                    </span>
                  </.link>
                  <%= if Enum.count(@runs) > 1 do %>
                    (<%= index %>/<%= Enum.count(@runs) %><%= if index !=
                                                                       Enum.count(
                                                                         @runs
                                                                       ),
                                                                     do: ")" %>
                    <%= if index == Enum.count(@runs) do %>
                      <span>
                        &bull; <a
                          id={"toggle_runs_for_#{@work_order.id}"}
                          href="#"
                          class="text-indigo-400"
                          phx-click="toggle_runs"
                          phx-target={@myself}
                        >
                        <%= if @show_prev_runs, do: "hide", else: "show" %> previous</a>)
                      </span>
                    <% end %>
                  <% end %>
                  <%= case run.state do %>
                    <% :available -> %>
                      enqueued @ <.timestamp timestamp={run.inserted_at} />
                    <% :claimed -> %>
                      claimed @ <.timestamp timestamp={run.claimed_at} />
                    <% :started -> %>
                      started @ <.timestamp timestamp={run.started_at} />
                    <% _state -> %>
                      <%= run.state %> @
                      <.timestamp timestamp={run.finished_at} />
                  <% end %>
                </div>
              </div>
            </div>

            <.run_item
              can_rerun_job={@can_rerun_job}
              run={run}
              project={@project}
            />
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
