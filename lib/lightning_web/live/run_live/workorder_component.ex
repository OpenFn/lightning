defmodule LightningWeb.RunLive.WorkOrderComponent do
  @moduledoc """
  Work Order component
  """
  use LightningWeb, :live_component

  import LightningWeb.RunLive.Components
  alias Phoenix.LiveView.JS

  @impl true
  def update(
        %{
          work_order: work_order,
          project: project,
          can_run_workflow: can_run_workflow
        } =
          assigns,
        socket
      ) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(project: project, can_run_workflow: can_run_workflow)
     |> set_details(work_order)}
  end

  def update(%{work_order: work_order} = assigns, socket) do
    {:ok, socket |> assign(assigns) |> set_details(work_order)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  defp set_details(socket, work_order) do
    last_run = get_last_run(work_order)

    work_order_inserted_at =
      Lightning.Helpers.format_date(work_order.inserted_at)

    workflow_name =
      cond do
        work_order.snapshot ->
          work_order.snapshot.name

        work_order.workflow ->
          work_order.workflow.name

        true ->
          "Untitled"
      end

    socket
    |> assign(
      work_order: work_order,
      runs: work_order.runs,
      last_run: last_run,
      work_order_inserted_at: work_order_inserted_at,
      workflow_name: workflow_name
    )
  end

  defp get_last_run(work_order) do
    work_order.runs
    |> List.first()
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

  attr :show_details, :boolean, default: false
  attr :show_prev_runs, :boolean, default: false
  attr :entry_selected, :boolean, default: false

  @impl true
  def render(assigns) do
    ~H"""
    <tbody id={"workorder-#{@work_order.id}"}>
      <.tr
        class={
          cond do
            @entry_selected -> "bg-gray-50"
            true -> "bg-white"
          end
        }
        id={"toggle_details_for_#{@work_order.id}"}
        onclick={
          if @work_order.runs !== [] do
            JS.push("toggle_details", target: @myself)
          end
        }
      >
        <.td>
          <%= if wo_dataclip_available?(@work_order) do %>
            <form
              phx-change="toggle_selection"
              phx-click={JS.exec("event.stopPropagation()")}
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
                phx-click={JS.exec("event.stopPropagation()")}
                {if @entry_selected, do: [checked: "checked"], else: []}
              />
            </form>
          <% else %>
            <form
              phx-click={JS.exec("event.stopPropagation()")}
              id={"selection-form-#{@work_order.id}"}
            >
              <span
                id={"select_#{@work_order.id}_tooltip"}
                class="cursor-pointer"
                phx-hook="Tooltip"
                data-placement="top"
                data-allow-html="true"
                data-interactive={@can_edit_data_retention && "true"}
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
        </.td>
        <.td>
          <span class="mt-2 text-gray-700">
            <.link navigate={
              ~p"/projects/#{@work_order.workflow.project_id}/history?filters[workorder_id]=#{@work_order.id}"
            }>
              <span class="link-uuid" title={@work_order.id}>
                {display_short_uuid(@work_order.id)}
              </span>
            </.link>
          </span>
        </.td>
        <.td>
          <%= if @last_run do %>
            <.link
              navigate={
                ~p"/projects/#{@project}/w/#{@work_order.workflow.id}?a=#{@last_run.id}&v=#{@work_order.snapshot.lock_version}"
              }
              class="inline-block"
            >
              <Common.wrapper_tooltip
                id={"workflow-name-#{@work_order.id}"}
                tooltip={"#{@workflow_name}<br/><span class=\"text-xs text-gray-500\">Click to view</span>"}
              >
                <span
                  class="truncate text-gray-900 workflow-name hover:text-primary-600 cursor-pointer"
                  style="max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; display: block;"
                >
                  {@workflow_name}
                </span>
              </Common.wrapper_tooltip>
            </.link>
          <% else %>
            <Common.wrapper_tooltip
              id={"workflow-name-#{@work_order.id}"}
              tooltip={@workflow_name}
            >
              <span
                class="truncate text-gray-900 workflow-name"
                style="max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; display: block;"
              >
                {@workflow_name}
              </span>
            </Common.wrapper_tooltip>
          <% end %>
        </.td>
        <.td>
          <.workorder_dataclip_link
            work_order={@work_order}
            project={@project}
            can_edit_data_retention={@can_edit_data_retention}
          />
        </.td>
        <.td>
          <Common.datetime datetime={@work_order.inserted_at} />
        </.td>
        <.td>
          <Common.datetime datetime={@work_order.last_activity} />
        </.td>
        <.td class="text-right w-28">
          <LightningWeb.RunLive.Components.elapsed_indicator
            :if={@last_run}
            item={@last_run}
            context="table"
          />
          <span :if={is_nil(@last_run)}>Not started</span>
        </.td>
        <.td class="text-right w-32">
          <div class="flex items-center justify-end gap-2">
            <.state_pill state={@work_order.state} />
          </div>
        </.td>
        <.td class="text-right w-20">
          <%= if @work_order.runs !== [] do %>
            <div class="flex items-center justify-end gap-2 pr-2 -mr-3">
              <%= if wo_dataclip_available?(@work_order) and @can_run_workflow do %>
                <button
                  type="button"
                  id={"retry-workorder-#{@work_order.id}"}
                  phx-click={
                    JS.push("bulk-rerun",
                      value: %{type: "single", workorder_id: @work_order.id}
                    )
                    |> JS.push("toggle_details", target: @myself)
                    |> JS.exec("event.stopPropagation()")
                  }
                  class="inline-flex items-center p-1 text-xs font-medium text-gray-600 hover:text-primary-400 cursor-pointer rounded"
                  phx-hook="Tooltip"
                  aria-label="Retry (run from the start)"
                >
                  <.icon name="hero-arrow-path-mini" class="h-4 w-4" />
                </button>
              <% else %>
                <span
                  id={"retry-disabled-#{@work_order.id}"}
                  class="inline-flex items-center p-1 text-xs font-medium text-gray-400 cursor-not-allowed rounded"
                  phx-hook="Tooltip"
                  data-allow-html="true"
                  data-placement="top"
                  data-interactive={@can_edit_data_retention && "true"}
                  aria-label={
                    cond do
                      not @can_run_workflow ->
                        "You are not authorized to start runs for this project."

                      not wo_dataclip_available?(@work_order) ->
                        rerun_zero_persistence_tooltip_message(
                          @project.id,
                          @can_edit_data_retention
                        )
                    end
                  }
                >
                  <.icon name="hero-arrow-path-mini" class="h-4 w-4" />
                </span>
              <% end %>
              <%!-- <%= if Enum.count(@work_order.runs) > 1 do %> --%>
              <span class="inline-flex items-center rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600">
                {Enum.count(@work_order.runs)}
              </span>
              <%!-- <% end %> --%>
              <.icon
                name={
                  if @show_details, do: "hero-chevron-up", else: "hero-chevron-down"
                }
                class="size-4 text-gray-400"
              />
            </div>
          <% end %>
        </.td>
      </.tr>
      <%= if @show_details do %>
        <.tr>
          <.td colspan={9} class="!p-0">
            <div class="bg-gray-100 p-3 flex flex-col gap-3">
              <%= for {run, index} <- @runs |> Enum.reverse() |> Enum.with_index(1) |> Enum.reverse() do %>
                <%= if index == Enum.count(@runs) or @show_prev_runs do %>
                  <div
                    id={"run_#{run.id}"}
                    class="w-full bg-white border border-gray-300 rounded-lg overflow-hidden"
                  >
                    <div class="bg-gray-200 text-xs flex items-center w-full">
                      <div class="flex-1 py-2 text-left">
                        <div class="pl-4">
                          Run
                          <.link navigate={
                            ~p"/projects/#{@project.id}/runs/#{run.id}"
                          }>
                            <span title={run.id} class="link font-mono">
                              {display_short_uuid(run.id)}
                            </span>
                          </.link>
                          <%= if Enum.count(@runs) > 1 do %>
                            ({index}/{Enum.count(@runs)}{if index !=
                                                              Enum.count(@runs),
                                                            do: ")"}
                            <%= if index == Enum.count(@runs) do %>
                              <span>
                                &bull; <a
                                  id={"toggle_runs_for_#{@work_order.id}"}
                                  href="#"
                                  class="link"
                                  phx-click="toggle_runs"
                                  phx-target={@myself}
                                >
                            <%= if @show_prev_runs, do: "hide", else: "show" %> previous</a>)
                              </span>
                            <% end %>
                          <% end %>
                          &bull;
                          <%= case run.state do %>
                            <% :available -> %>
                              enqueued
                              <Common.datetime
                                datetime={run.inserted_at}
                                format={:relative_detailed}
                              />
                            <% :claimed -> %>
                              claimed
                              <Common.datetime
                                datetime={run.claimed_at}
                                format={:relative_detailed}
                              />
                            <% :started -> %>
                              started
                              <Common.datetime
                                datetime={run.started_at}
                                format={:relative_detailed}
                              />
                            <% _state -> %>
                              finished
                              <Common.datetime
                                datetime={run.finished_at}
                                format={:relative_detailed}
                              />
                          <% end %>
                        </div>
                      </div>
                      <div class="flex-shrink-0 py-2 px-4 text-right min-w-[240px]">
                        <div class="flex items-center justify-end gap-3">
                          <div class="w-16 text-right">
                            <.elapsed_indicator item={run} context="details" />
                          </div>
                          <span class="font-mono w-24 text-right">{run.state}</span>
                        </div>
                      </div>
                    </div>
                    <.run_item
                      can_edit_data_retention={@can_edit_data_retention}
                      can_run_workflow={@can_run_workflow}
                      run={run}
                      workflow_version={@work_order.workflow.lock_version}
                      project={@project}
                    />
                  </div>
                <% end %>
              <% end %>
            </div>
          </.td>
        </.tr>
      <% end %>
    </tbody>
    """
  end

  defp workorder_dataclip_link(assigns) do
    ~H"""
    <%= if wo_dataclip_available?(@work_order) do %>
      <.link
        id={"view-dataclip-#{@work_order.dataclip_id}-for-#{@work_order.id}"}
        navigate={
          ~p"/projects/#{@work_order.workflow.project_id}/dataclips/#{@work_order.dataclip_id}/show"
        }
        class="link-uuid"
      >
        <span title={@work_order.dataclip_id}>
          {display_short_uuid(@work_order.dataclip_id)}
        </span>
      </.link>
    <% else %>
      <span
        id={"view-dataclip-#{@work_order.dataclip_id}-for-#{@work_order.id}"}
        title={@work_order.dataclip_id}
        class="link-uuid cursor-not-allowed"
        phx-hook="Tooltip"
        data-placement="right"
        data-interactive="true"
        data-allow-html="true"
        aria-label={
          wiped_dataclip_tooltip_message(@project.id, @can_edit_data_retention)
        }
      >
        {display_short_uuid(@work_order.dataclip_id)}
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
    The input dataclip is unavailable due to this project's data retention policy.
    <br>
    #{zero_persistence_action_message(project_id, can_edit_retention)}
    </span>
    """
  end
end
