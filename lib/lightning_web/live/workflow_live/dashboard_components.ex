defmodule LightningWeb.WorkflowLive.DashboardComponents do
  @moduledoc false
  use LightningWeb, :component

  alias Lightning.DashboardStats.ProjectMetrics
  alias Lightning.Projects.Project
  alias Lightning.WorkOrders.SearchParams
  alias LightningWeb.Components.Common
  alias LightningWeb.WorkflowLive.Helpers
  alias Phoenix.LiveView.JS

  attr :period, :string, default: "last 30 days"
  attr :can_create_workflow, :boolean
  attr :can_delete_workflow, :boolean
  attr :workflows_stats, :list
  attr :project, :map
  attr :sort_key, :string, default: "name"
  attr :sort_direction, :string, default: "asc"
  attr :search_term, :string, default: ""

  def workflow_list(assigns) do
    ~H"""
    <div class="w-full">
      <div class="mt-14 flex justify-between mb-3">
        <.table_title count={length(@workflows_stats)} />
        <div class="flex gap-2 items-start">
          <.search_workflows_input search_term={@search_term} />
          <.create_workflow_card
            project_id={@project.id}
            can_create_workflow={@can_create_workflow}
          />
        </div>
      </div>
      <.workflows_table
        id="workflows-table"
        period={@period}
        workflows_stats={@workflows_stats}
        can_delete_workflow={@can_delete_workflow}
        project={@project}
        sort_key={@sort_key}
        sort_direction={@sort_direction}
      >
        <:empty_state>
          <div class="text-center py-8">
            <p class="text-gray-500">
              <%= if @search_term != "" do %>
                No workflows found matching "{@search_term}". Try a different search term or <.link
                  navigate={~p"/projects/#{@project.id}/w/new"}
                  class="link"
                >
                  create a new one
                </.link>.
              <% else %>
                No workflows found.
                <.link navigate={~p"/projects/#{@project.id}/w/new"} class="link">
                  Create one
                </.link>
                to start automating.
              <% end %>
            </p>
          </div>
        </:empty_state>
      </.workflows_table>
    </div>
    """
  end

  defp table_title(assigns) do
    ~H"""
    <h3 class="text-3xl font-bold">
      Workflows
      <span class="text-base font-normal">
        ({@count})
      </span>
    </h3>
    """
  end

  attr :id, :string, required: true
  attr :workflows_stats, :list, required: true
  attr :period, :string, required: true
  attr :project, :map, required: true
  attr :can_delete_workflow, :boolean, default: false
  attr :sort_key, :string, default: "name"
  attr :sort_direction, :string, default: "asc"

  slot :empty_state, doc: "the slot for showing an empty state"

  def workflows_table(%{workflows_stats: workflows_stats} = assigns) do
    assigns =
      assigns
      |> assign(
        wo_filters:
          SearchParams.to_uri_params(%{
            "wo_date_after" => Timex.now() |> Timex.shift(months: -1)
          }),
        failed_wo_filters:
          SearchParams.to_uri_params(%{
            "wo_date_after" => Timex.now() |> Timex.shift(months: -1),
            "failed" => "true",
            "crashed" => "true",
            "killed" => "true",
            "cancelled" => "true",
            "lost" => "true",
            "exception" => "true"
          }),
        workflows: Enum.map(workflows_stats, &Map.merge(&1, &1.workflow)),
        empty?: Enum.empty?(workflows_stats)
      )

    ~H"""
    <%= if @empty? do %>
      {render_slot(@empty_state)}
    <% else %>
      <div>
        <.table id={@id}>
          <:header>
            <.tr>
              <.th
                sortable={true}
                sort_by="name"
                active={@sort_key == "name"}
                sort_direction={@sort_direction}
              >
                Name
              </.th>
              <.th
                sortable={true}
                sort_by="last_workorder_updated_at"
                active={@sort_key == "last_workorder_updated_at"}
                sort_direction={@sort_direction}
              >
                Latest Work Order
              </.th>
              <.th
                sortable={true}
                sort_by="workorders_count"
                active={@sort_key == "workorders_count"}
                sort_direction={@sort_direction}
              >
                Work Orders
              </.th>
              <.th
                sortable={true}
                sort_by="failed_workorders_count"
                active={@sort_key == "failed_workorders_count"}
                sort_direction={@sort_direction}
              >
                Work Orders in a failed state
              </.th>
              <.th
                sortable={true}
                sort_by="enabled"
                active={@sort_key == "enabled"}
                sort_direction={@sort_direction}
              >
                Enabled
              </.th>
              <.th>
                <span class="sr-only">Actions</span>
              </.th>
            </.tr>
          </:header>
          <:body>
            <%= for workflow <- @workflows do %>
              <.tr
                id={"workflow-#{workflow.id}"}
                class="hover:bg-gray-100 transition-colors duration-200"
                onclick={JS.navigate(~p"/projects/#{@project.id}/w/#{workflow.id}")}
              >
                <.td class="wrap-break-word max-w-[15rem]">
                  <div
                    phx-click={
                      JS.navigate(~p"/projects/#{@project.id}/w/#{workflow.id}")
                    }
                    class="cursor-pointer"
                  >
                    <.workflow_card
                      workflow={workflow}
                      project={@project}
                      trigger_enabled={Enum.any?(workflow.triggers, & &1.enabled)}
                    />
                  </div>
                </.td>
                <.td class="wrap-break-word max-w-[15rem]">
                  <.state_card
                    state={workflow.last_workorder.state}
                    timestamp={workflow.last_workorder.updated_at}
                    period={@period}
                  />
                </.td>
                <.td class="wrap-break-word max-w-[10rem]">
                  <div>
                    <%= if workflow.workorders_count > 0 do %>
                      <div class="text-indigo-700 text-lg">
                        <.link
                          class="hover:underline"
                          navigate={
                            ~p"/projects/#{@project.id}/history?#{%{filters: Map.merge(@wo_filters, %{workflow_id: workflow.id})}}"
                          }
                          onclick="event.stopPropagation()"
                        >
                          {workflow.workorders_count}
                        </.link>
                      </div>
                      <div class="text-gray-500 text-xs">
                        ({workflow.step_count} steps, <span>{workflow.step_success_rate}% success</span>)
                      </div>
                    <% else %>
                      <div class="text-gray-400 text-lg">
                        <span>0</span>
                      </div>
                      <div class="text-xs">
                        <span>N/A</span>
                      </div>
                    <% end %>
                  </div>
                </.td>
                <.td class="wrap-break-word max-w-[15rem]">
                  <div>
                    <%= if workflow.failed_workorders_count > 0 do %>
                      <div class="text-indigo-700 text-lg">
                        <.link
                          class="hover:underline"
                          navigate={
                            ~p"/projects/#{@project.id}/history?#{%{filters: Map.merge(@failed_wo_filters, %{workflow_id: workflow.id})}}"
                          }
                          onclick="event.stopPropagation()"
                        >
                          {workflow.failed_workorders_count}
                        </.link>
                      </div>
                      <div class="text-gray-500 text-xs">
                        Latest failure
                        <Common.datetime datetime={
                          workflow.last_failed_workorder.updated_at
                        } />
                      </div>
                    <% else %>
                      <div class="text-gray-400 text-lg">
                        <span>0</span>
                      </div>
                      <div class="text-xs mt-1">
                        <span>N/A</span>
                      </div>
                    <% end %>
                  </div>
                </.td>
                <.td>
                  <.input
                    id={workflow.id}
                    type="toggle"
                    name="workflow_state"
                    value={Helpers.workflow_enabled?(workflow)}
                    tooltip={Helpers.workflow_state_tooltip(workflow)}
                    on_click="toggle_workflow_state"
                    value_key={workflow.id}
                  />
                </.td>
                <.td class="text-right">
                  <%= if @can_delete_workflow do %>
                    <.link
                      href="#"
                      class="table-action"
                      phx-click="delete_workflow"
                      phx-value-id={workflow.id}
                      data-confirm="Are you sure you'd like to delete this workflow?"
                    >
                      Delete
                    </.link>
                  <% end %>
                </.td>
              </.tr>
            <% end %>
          </:body>
        </.table>
      </div>
    <% end %>
    """
  end

  attr :current_sort_key, :string, required: true
  attr :current_sort_direction, :string, required: true
  attr :target_sort_key, :string, required: true
  slot :inner_block, required: true

  defp sortable_table_header(assigns) do
    ~H"""
    <Common.sortable_table_header
      phx-click="sort"
      phx-value-by={@target_sort_key}
      active={@current_sort_key == @target_sort_key}
      sort_direction={@current_sort_direction}
    >
      {render_slot(@inner_block)}
    </Common.sortable_table_header>
    """
  end

  attr :project, :map, required: true
  attr :workflow, :map, required: true
  attr :trigger_enabled, :boolean

  def workflow_card(assigns) do
    ~H"""
    <div class="flex flex-1 items-center truncate">
      <div class="text-sm">
        <Common.wrapper_tooltip
          id={"workflow-name-#{@workflow.id}"}
          tooltip={
            if @trigger_enabled,
              do: @workflow.name,
              else: "#{@workflow.name} (disabled)"
          }
        >
          <div class="flex items-center">
            <span
              class={[
                "flex-shrink truncate font-medium workflow-name",
                if(@trigger_enabled, do: "text-gray-900", else: "text-gray-400")
              ]}
              style="max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;"
            >
              {@workflow.name}
            </span>
          </div>
        </Common.wrapper_tooltip>
        <p class="text-gray-500 text-xs mt-1">
          Updated <Common.datetime datetime={@workflow.updated_at} />
        </p>
      </div>
    </div>
    """
  end

  attr :can_create_workflow, :boolean, required: true
  attr :project_id, :string, required: true

  def create_workflow_card(assigns) do
    assigns =
      assigns
      |> assign_new(:disabled, fn ->
        !assigns.can_create_workflow
      end)
      |> assign_new(:tooltip, fn ->
        "You are not authorized to perform this action."
      end)

    ~H"""
    <div>
      <.button
        disabled={@disabled}
        tooltip={@tooltip}
        phx-click={
          if !@disabled do
            JS.navigate(~p"/projects/#{@project_id}/w/new?method=template")
          end
        }
        class="col-span-1 w-full"
        role="button"
        id="new-workflow-button"
        theme="primary"
      >
        Create new workflow
      </.button>
    </div>
    """
  end

  attr :search_term, :string, default: ""

  def search_workflows_input(assigns) do
    ~H"""
    <div class="relative rounded-md shadow-xs flex h-full">
      <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
        <Heroicons.magnifying_glass class="h-5 w-5 text-gray-400" />
      </div>
      <.input
        type="text"
        name="search_workflows"
        value={@search_term}
        placeholder="Search"
        class="block w-full rounded-md py-1.5 pl-10 pr-20 text-gray-900 placeholder:text-gray-400 focus:ring-inset focus:ring-indigo-600 sm:text-sm sm:leading-6"
        phx-keyup="search_workflows"
        phx-debounce="300"
      />

      <div class="absolute inset-y-0 right-0 flex items-center pr-3">
        <a
          href="#"
          class={if @search_term == "", do: "hidden"}
          id="clear_search_button"
          phx-click="clear_search"
        >
          <Heroicons.x_mark class="h-5 w-5 text-gray-400" />
        </a>
      </div>
    </div>
    """
  end

  attr :state, :atom, required: true
  attr :timestamp, :any, required: true
  attr :period, :string, required: true

  def state_card(assigns) do
    ~H"""
    <div class="flex flex-col text-center">
      <%= if is_nil(@state) do %>
        <div class="flex items-center gap-x-2">
          <span class="inline-block h-2 w-2 bg-gray-200 rounded-full"></span>
          <span class="text-grey-200 italic">Nothing {@period}</span>
        </div>
      <% else %>
        <.status_card state={@state} time={@timestamp} />
      <% end %>
    </div>
    """
  end

  def status_card(assigns) do
    dot_color = %{
      pending: "bg-gray-600",
      running: "bg-blue-600",
      success: "bg-green-600",
      failed: "bg-red-600",
      crashed: "bg-orange-600",
      cancelled: "bg-gray-500",
      killed: "bg-yellow-600",
      exception: "bg-gray-300 border-solid border-2 border-gray-800",
      lost: "bg-gray-300 border-solid border-2 border-gray-800"
    }

    font_color = %{
      pending: "text-gray-500",
      running: "text-blue-500",
      success: "text-green-500",
      failed: "text-red-500",
      crashed: "text-orange-500",
      cancelled: "text-gray-500",
      killed: "text-yellow-800",
      exception: "text-gray-600",
      lost: "text-gray-600"
    }

    assigns =
      assign(assigns,
        text:
          LightningWeb.RunLive.Components.display_text_from_state(assigns.state),
        dot_color: Map.get(dot_color, assigns.state),
        font_color: Map.get(font_color, assigns.state)
      )

    ~H"""
    <div>
      <div class="flex items-center gap-x-2">
        <span class="relative inline-flex h-2 w-2">
          <%= if @state in [:pending, :running] do %>
            <span class={[
              "animate-ping absolute inline-flex h-full w-full rounded-full opacity-75",
              @dot_color
            ]}>
            </span>
          <% end %>
          <span class={["relative inline-flex rounded-full h-2 w-2", @dot_color]}>
          </span>
        </span>
        <span class={[@font_color, "font-medium"]}>{@text}</span>
      </div>
      <span class="block text-left text-gray-500 text-xs ml-4 mt-1">
        <Common.datetime datetime={@time} />
      </span>
    </div>
    """
  end

  attr :metrics, ProjectMetrics, required: true
  attr :project, Project, required: true

  def project_metrics(assigns) do
    assigns =
      assigns
      |> assign(
        failed_filters:
          SearchParams.to_uri_params(%{
            "wo_date_after" => Timex.now() |> Timex.shift(months: -1),
            "failed" => "true",
            "crashed" => "true",
            "killed" => "true",
            "cancelled" => "true",
            "lost" => "true",
            "exception" => "true"
          }),
        pending_filters:
          SearchParams.to_uri_params(%{
            "wo_date_after" => Timex.now() |> Timex.shift(months: -1),
            "pending" => "true",
            "running" => "true"
          })
      )

    ~H"""
    <div class="grid gap-12 md:grid-cols-2 lg:grid-cols-4">
      <.metric_card title="Work Orders">
        <:value>{@metrics.work_order_metrics.total}</:value>
        <:suffix>
          <.link
            navigate={
              ~p"/projects/#{@project}/history?#{%{filters: @pending_filters}}"
            }
            class="link"
          >
            ({@metrics.work_order_metrics.pending} pending)
          </.link>
        </:suffix>
      </.metric_card>
      <.metric_card title="Runs">
        <:value>{@metrics.run_metrics.total}</:value>
        <:suffix>
          ({@metrics.run_metrics.pending} pending)
        </:suffix>
      </.metric_card>
      <.metric_card title="Successful Runs">
        <:value>{@metrics.run_metrics.success}</:value>
        <:suffix>
          ({@metrics.run_metrics.success_rate}%)
        </:suffix>
      </.metric_card>
      <.metric_card title="Work Orders in failed state">
        <:value>{@metrics.work_order_metrics.failed}</:value>
        <:suffix>
          ({@metrics.work_order_metrics.failed_percentage}%)
        </:suffix>
        <:link>
          <.link
            navigate={
              ~p"/projects/#{@project}/history?#{%{filters: @failed_filters}}"
            }
            class="link"
          >
            View all
          </.link>
        </:link>
      </.metric_card>
    </div>
    """
  end

  attr :title, :string, required: true
  slot :value, required: true

  slot :suffix, required: false
  slot :link, required: false

  def metric_card(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg py-2 px-6">
      <h2
        class="text-sm text-gray-500"
        style="font-weight: 500; font-size: 13px; margin-bottom: 8px; max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;"
      >
        {@title}
      </h2>
      <div class="flex space-x-1 items-baseline text-3xl font-bold text-gray-800">
        <div>{render_slot(@value)}</div>
        <div class="text-xs font-normal grow">
          {render_slot(@suffix)}
        </div>
        <div class="text-xs font-normal">
          {render_slot(@link)}
        </div>
      </div>
    </div>
    """
  end
end
