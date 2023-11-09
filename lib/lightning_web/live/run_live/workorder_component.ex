defmodule LightningWeb.RunLive.WorkOrderComponent do
  @moduledoc """
  Workorder component
  """
  use LightningWeb, :live_component

  import LightningWeb.RunLive.Components

  @impl true
  def update(
        %{work_order: work_order, project: project, can_rerun_job: can_rerun_job} =
          assigns,
        socket
      ) do
    {:ok,
     socket
     |> assign(project: project, can_rerun_job: can_rerun_job)
     |> set_entry_selection(assigns)
     |> set_work_order_details(work_order)}
  end

  def update(%{work_order: work_order} = assigns, socket) do
    {:ok,
     socket |> set_work_order_details(work_order) |> set_entry_selection(assigns)}
  end

  def update(%{event: :selection_toggled, entry_selected: selection}, socket) do
    {:ok, assign(socket, entry_selected: selection)}
  end

  defp set_entry_selection(socket, assigns) do
    assign(socket, entry_selected: assigns[:entry_selected] || false)
  end

  defp set_work_order_details(socket, work_order) do
    last_run = List.last(List.first(work_order.attempts).runs)

    last_run_finished_at =
      case last_run do
        %{finished_at: %_{} = finished_at} ->
          Calendar.strftime(finished_at, "%c %Z")

        _ ->
          nil
      end

    work_order_inserted_at = Calendar.strftime(work_order.inserted_at, "%c %Z")

    socket
    |> assign(
      work_order: work_order,
      attempts: work_order.attempts,
      last_run: last_run,
      last_run_finished_at: last_run_finished_at,
      work_order_inserted_at: work_order_inserted_at,
      workflow_name: work_order.workflow.name || "Untitled"
    )
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

  def handle_event("toggle_selection", %{}, %{assigns: assigns} = socket) do
    send(
      self(),
      {:selection_toggled, {assigns.work_order, !assigns[:entry_selected]}}
    )

    {:noreply, assign(socket, :entry_selected, !assigns[:entry_selected])}
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
            <.form
              :let={f}
              for={selection_params(@work_order, @entry_selected)}
              phx-change="toggle_selection"
              phx-target={@myself}
              id={"selection-form-#{@work_order.id}"}
            >
              <%= Phoenix.HTML.Form.checkbox(f, :selected,
                id: "select_#{@work_order.id}",
                class:
                  "left-4 top-1/2 h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-600"
              ) %>
            </.form>
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

            <div class="ml-3 py-2">
              <h1 class={"text-sm mb-1 #{unless @show_details, do: "truncate"}"}>
                <%= @workflow_name %>
              </h1>
              <span class="mt-2 text-gray-700">
                <%= display_short_uuid(@work_order.id) %> .
                <.link navigate={
                  ~p"/projects/#{@work_order.workflow.project_id}/dataclips/#{@work_order.dataclip_id}/edit"
                }>
                  <span
                    title={@work_order.dataclip_id}
                    class="font-normal text-xs whitespace-nowrap text-ellipsis
                            bg-gray-200 p-1 rounded-md font-mono text-indigo-400 hover:underline
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
          <%= case @work_order.state do %>
            <% :success -> %>
              <.success_pill>Success</.success_pill>
            <% :failed -> %>
              <.failure_pill>Failed</.failure_pill>
            <% :killed -> %>
              <.killed_pill>Killed</.killed_pill>
            <% :pending -> %>
              <.pending_pill>Pending</.pending_pill>
            <% state -> %>
              <.other_state_pill>
                <%= state |> Atom.to_string() |> String.capitalize() %>
              </.other_state_pill>
          <% end %>
        </div>
      </div>
      <%= if @show_details do %>
        <%= if length(@attempts) == 1 do %>
          <.attempt_item
            can_rerun_job={@can_rerun_job}
            attempt={hd(@attempts)}
            project={@project}
          />
        <% else %>
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
                <div class="flex gap-2 items-center bg-gray-300 pl-28 ">
                  <p class="text-sm py-2 text-gray-800">
                    Attempt <%= index %> of <%= Enum.count(@attempts) %>
                  </p>
                  <div class="text-sm">
                    <%= attempt.state %>
                    <%= if attempt.finished_at do %>
                      <.timestamp timestamp={attempt.finished_at} />
                    <% end %>
                  </div>
                  <a
                    :if={index == Enum.count(@attempts)}
                    id={"toggle_attempts_for_#{@work_order.id}"}
                    href="#"
                    class="text-sm ml-4 text-blue-600"
                    phx-click="toggle_attempts"
                    phx-target={@myself}
                  >
                    <%= if @show_prev_attempts, do: "Hide", else: "Show" %> previous attempts
                  </a>
                </div>
              </div>

              <.attempt_item
                can_rerun_job={@can_rerun_job}
                attempt={attempt}
                project={@project}
              />
            </div>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp selection_params(work_order, selected) do
    %{"id" => work_order.id, "selected" => selected}
  end
end
