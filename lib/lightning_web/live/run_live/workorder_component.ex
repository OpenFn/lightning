defmodule LightningWeb.RunLive.WorkOrderComponent do
  @moduledoc """
  Work Order component
  """
  use LightningWeb, :live_component

  import LightningWeb.RunLive.Components
  import LightningWeb.AttemptLive.Components

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
      attempts: work_order.attempts,
      last_step: last_step,
      last_step_finished_at: last_step_finished_at,
      work_order_inserted_at: work_order_inserted_at,
      workflow_name: workflow_name
    )
  end

  defp get_last_step(work_order) do
    work_order.attempts
    |> List.first()
    |> case do
      nil -> nil
      attempt -> List.last(attempt.steps)
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

  def handle_event("toggle_attempts", %{}, socket) do
    {:noreply,
     assign(
       socket,
       :show_prev_attempts,
       !socket.assigns[:show_prev_attempts]
     )}
  end

  attr :show_details, :boolean, default: false
  attr :show_prev_attempts, :boolean, default: false
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
            <%= if wo_dataclip_available?(@work_order) do %>
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
            <% else %>
              <form id={"selection-form-#{@work_order.id}"}>
                <span
                  id={"select_#{@work_order.id}_tooltip"}
                  class="cursor-pointer"
                  phx-hook="Tooltip"
                  data-placement="right"
                  data-allow-html="true"
                  aria-label={
                    rerun_zero_persistence_tooltip_message(
                      @project.id,
                      @can_edit_data_retention
                    )
                  }
                >
                  <input
                    type="checkbox"
                    id={"select_#{@work_order.id}"}
                    name="selected"
                    class="left-4 top-1/2 h-4 w-4 rounded border-gray-300 bg-gray-100 text-indigo-600 focus:ring-indigo-600"
                    disabled
                  />
                </span>
              </form>
            <% end %>
            <%= if @work_order.attempts !== [] do %>
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
                <.workorder_dataclip_link
                  work_order={@work_order}
                  project={@project}
                  can_edit_data_retention={@can_edit_data_retention}
                />
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
        <%= for {attempt, index} <- @attempts |> Enum.reverse() |> Enum.with_index(1) |> Enum.reverse() do %>
          <div
            id={"attempt_#{attempt.id}"}
            class={
              if index != Enum.count(@attempts) and !@show_prev_attempts,
                do: "hidden",
                else: ""
            }
          >
            <div>
              <div class="flex gap-1 items-center bg-gray-200 pl-28 text-xs py-2">
                <div>
                  Run
                  <.link navigate={~p"/projects/#{@project.id}/runs/#{attempt.id}"}>
                    <span
                      title={attempt.id}
                      class="font-normal text-xs whitespace-nowrap text-ellipsis
                            inline-block rounded-md font-mono
                            text-indigo-400 hover:underline underline-offset-2
                            hover:text-indigo-500"
                    >
                      <%= display_short_uuid(attempt.id) %>
                    </span>
                  </.link>
                  <%= if Enum.count(@attempts) > 1 do %>
                    (<%= index %>/<%= Enum.count(@attempts) %><%= if index !=
                                                                       Enum.count(
                                                                         @attempts
                                                                       ),
                                                                     do: ")" %>
                    <%= if index == Enum.count(@attempts) do %>
                      <span>
                        &bull; <a
                          id={"toggle_attempts_for_#{@work_order.id}"}
                          href="#"
                          class="text-indigo-400"
                          phx-click="toggle_attempts"
                          phx-target={@myself}
                        >
                        <%= if @show_prev_attempts, do: "hide", else: "show" %> previous</a>)
                      </span>
                    <% end %>
                  <% end %>
                  <%= case attempt.state do %>
                    <% :available -> %>
                      enqueued @ <.timestamp timestamp={attempt.inserted_at} />
                    <% :claimed -> %>
                      claimed @ <.timestamp timestamp={attempt.claimed_at} />
                    <% :started -> %>
                      started @ <.timestamp timestamp={attempt.started_at} />
                    <% _state -> %>
                      <%= attempt.state %> @
                      <.timestamp timestamp={attempt.finished_at} />
                  <% end %>
                </div>
              </div>
            </div>

            <.attempt_item
              can_rerun_job={@can_rerun_job}
              can_edit_data_retention={@can_edit_data_retention}
              attempt={attempt}
              project={@project}
            />
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp workorder_dataclip_link(assigns) do
    ~H"""
    <%= if wo_dataclip_available?(@work_order) do %>
      <.link
        id={"view-dataclip-#{@work_order.dataclip_id}"}
        navigate={
          ~p"/projects/#{@work_order.workflow.project_id}/dataclips/#{@work_order.dataclip_id}/show"
        }
      >
        <span
          title={@work_order.dataclip_id}
          class="font-normal text-xs whitespace-nowrap text-ellipsis
                p-1 rounded-md font-mono text-indigo-400 hover:underline
                underline-offset-2 hover:text-indigo-500"
        >
          <%= display_short_uuid(@work_order.dataclip_id) %>
        </span>
      </.link>
    <% else %>
      <span
        id={"view-dataclip-#{@work_order.dataclip_id}"}
        title={@work_order.dataclip_id}
        class="font-normal text-xs whitespace-nowrap text-ellipsis
              p-1 rounded-md font-mono text-indigo-300 cursor-pointer
              "
        phx-hook="Tooltip"
        data-placement="right"
        data-allow-html="true"
        aria-label={
          wiped_dataclip_tooltip_message(@project.id, @can_edit_data_retention)
        }
      >
        <%= display_short_uuid(@work_order.dataclip_id) %>
      </span>
    <% end %>
    """
  end

  defp wo_dataclip_available?(work_order) do
    is_nil(work_order.dataclip.wiped_at)
  end

  defp wiped_dataclip_tooltip_message(project_id, can_edit_retention) do
    """
    <span class="text-center">
    The input dataclip is unavailable and has not been stored<br>
    due to the data retention policy set in the project.<br>
    #{zero_persistence_action_message(project_id, can_edit_retention)}
    </span>
    """
  end
end
