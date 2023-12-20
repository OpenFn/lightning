defmodule LightningWeb.WorkflowLive.DashboardComponents do
  @moduledoc false
  use LightningWeb, :component

  alias Lightning.DashboardStats.ProjectMetrics
  alias Lightning.Projects.Project
  alias Lightning.WorkOrders.SearchParams

  def workflow_list(assigns) do
    ~H"""
    <div class="w-full">
      <div class="mt-14 flex justify-between mb-3">
        <h3 class="text-3xl font-bold">
          Workflows
          <span class="text-base font-normal">
            (<%= length(assigns.workflows_stats) %>)
          </span>
        </h3>
        <.create_workflow_card
          project={@project}
          can_create_workflow={@can_create_workflow}
        />
      </div>
      <.workflows_table
        workflows_stats={@workflows_stats}
        can_create_workflow={@can_create_workflow}
        can_delete_workflow={@can_delete_workflow}
        project={@project}
      />
    </div>
    """
  end

  def workflows_table(%{workflows_stats: workflows_stats} = assigns) do
    assigns =
      assigns
      |> assign(
        filters:
          SearchParams.to_uri_params(%{
            "date_after" => Timex.now() |> Timex.shift(months: -1),
            "date_before" => DateTime.utc_now(),
            "failed" => "true",
            "crashed" => "true",
            "killed" => "true",
            "cancelled" => "true",
            "lost" => "true",
            "exception" => "true"
          }),
        workflows: Enum.map(workflows_stats, &Map.merge(&1, &1.workflow))
      )

    ~H"""
    <.new_table
      id="workflows"
      rows={@workflows}
      row_class="group hover:bg-indigo-50 hover:border-l-indigo-500"
    >
      <:col :let={workflow} label_class="ml-3 text-gray-700" label="Name">
        <.workflow_card
          workflow={workflow}
          project={@project}
          trigger_enabled={Enum.any?(workflow.triggers, & &1.enabled)}
        />
      </:col>
      <:col
        :let={workflow}
        label_class="text-gray-700 font-medium"
        label="Latest Work Order"
      >
        <.state_card
          state={workflow.last_workorder.state}
          timestamp={workflow.last_workorder.updated_at}
        />
      </:col>
      <:col
        :let={workflow}
        label_class="text-gray-700 font-medium"
        label="Work Orders"
      >
        <div class="ml-2">
          <%= if workflow.workorders_count > 0 do %>
            <div class="text-indigo-700 text-lg">
              <.link
                class="hover:underline"
                navigate={
                  ~p"/projects/#{@project.id}/runs?#{%{filters: %{workflow_id: workflow.id}}}"
                }
              >
                <%= workflow.workorders_count %>
              </.link>
            </div>
            <div class="text-gray-500 text-xs mt-1">
              (<%= workflow.runs_count %> runs,
              <span>
                <%= workflow.runs_success_percentage %>% success
              </span>
              )
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
      </:col>
      <:col
        :let={workflow}
        label_class="text-gray-700 font-medium"
        label="Work Orders in a failed state"
      >
        <div class="flex justify-between">
          <div class="ml-2">
            <%= if workflow.failed_workorders_count > 0 do %>
              <div class="text-indigo-700 text-lg">
                <.link
                  class="hover:underline"
                  navigate={
                    ~p"/projects/#{@project.id}/runs?#{%{filters: Map.merge(@filters, %{workflow_id: workflow.id})}}"
                  }
                >
                  <%= workflow.failed_workorders_count %>
                </.link>
              </div>
              <div class="text-gray-500 text-xs">
                Latest failure <%= workflow.last_failed_workorder.updated_at
                |> Timex.Format.DateTime.Formatters.Relative.format!("{relative}") %>
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
          <div class="mr-2 invisible group-hover:visible group-hover:text-red-600 pt-2">
            <div :if={@can_delete_workflow}>
              <.link
                href="#"
                phx-click="delete_workflow"
                phx-value-id={workflow.id}
                data-confirm="Are you sure you'd like to delete this workflow?"
              >
                Delete
              </.link>
            </div>
          </div>
        </div>
      </:col>
    </.new_table>
    """
  end

  attr :project, :map, required: true
  attr :workflow, :map, required: true
  attr :trigger_enabled, :boolean

  def workflow_card(assigns) do
    assigns =
      assigns
      |> assign(
        relative_updated_at:
          Timex.Format.DateTime.Formatters.Relative.format!(
            assigns.workflow.updated_at,
            "{relative}"
          )
      )

    ~H"""
    <div class="flex flex-1 items-center truncate">
      <.link
        id={"workflow-card-#{@workflow.id}"}
        navigate={~p"/projects/#{@project.id}/w/#{@workflow.id}"}
        role="button"
      >
        <div class="text-sm">
          <div class="flex items-center">
            <span
              class="flex-shrink truncate text-gray-900 hover:text-gray-600 font-medium ml-3"
              style="max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;"
            >
              <%= @workflow.name %>
            </span>
          </div>
          <%= if @trigger_enabled do %>
            <p class="text-gray-500 text-xs ml-3">
              Updated <%= @relative_updated_at %>
            </p>
          <% else %>
            <div class="flex items-center ml-3 mt-1">
              <div style="background: #8b5f0d" class="w-2 h-2 rounded-full"></div>
              <div>
                <p class="text-[#8b5f0d] text-xs">
                  &nbsp; Disabled
                </p>
              </div>
            </div>
          <% end %>
        </div>
      </.link>
    </div>
    """
  end

  def create_workflow_card(assigns) do
    ~H"""
    <div>
      <button
        phx-click={show_modal("workflow_modal")}
        class="col-span-1 w-full rounded-md"
        role={@can_create_workflow && "button"}
        id="open-modal-button"
      >
        <div class={"flex flex-1 items-center justify-between truncate rounded-md border border-gray-200 text-white " <> (if @can_create_workflow, do: "bg-primary-600 hover:bg-primary-700", else: "bg-gray-400")}>
          <div class="flex-1 truncate px-4 py-2 text-sm text-left">
            <span class="font-medium">
              Create new workflow
            </span>
          </div>
        </div>
      </button>
    </div>
    """
  end

  attr :metrics, ProjectMetrics, required: true
  attr :project, Project, required: true

  def project_metrics(assigns) do
    assigns =
      assigns
      |> assign(
        filters:
          SearchParams.to_uri_params(%{
            "date_after" => Timex.now() |> Timex.shift(months: -1),
            "date_before" => DateTime.utc_now(),
            "failed" => "true",
            "crashed" => "true",
            "killed" => "true",
            "cancelled" => "true",
            "lost" => "true",
            "exception" => "true"
          })
      )

    ~H"""
    <div class="grid gap-12 md:grid-cols-2 lg:grid-cols-4">
      <.metric_card title="Work Orders">
        <:value><%= @metrics.work_order_metrics.total %></:value>
      </.metric_card>
      <.metric_card title="Runs">
        <:value><%= @metrics.run_metrics.total %></:value>
        <:suffix>
          (<%= @metrics.run_metrics.pending %> pending)
        </:suffix>
      </.metric_card>
      <.metric_card title="Successful Runs">
        <:value><%= @metrics.run_metrics.completed %></:value>
        <:suffix>
          (<%= @metrics.run_metrics.success_percentage %>%)
        </:suffix>
      </.metric_card>
      <.metric_card title="Work Orders in failed state">
        <:value><%= @metrics.work_order_metrics.failed %></:value>
        <:suffix>
          <span class="mr-10">
            (<%= @metrics.work_order_metrics.failure_percentage %>%)
          </span>
          <.link
            navigate={~p"/projects/#{@project}/runs?#{%{filters: @filters}}"}
            class="text-indigo-700"
          >
            View all
          </.link>
        </:suffix>
      </.metric_card>
    </div>
    """
  end

  attr :title, :string, required: true
  slot :value, required: true

  slot :suffix, required: false

  def metric_card(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg py-2 px-6">
      <h2
        class="text-sm text-gray-500"
        style="font-weight: 500; font-size: 13px; margin-bottom: 8px; max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;"
      >
        <%= @title %>
      </h2>
      <p class="text-3xl font-bold text-gray-800">
        <%= render_slot(@value) %>
        <span class="text-xs font-normal">
          <%= render_slot(@suffix) %>
        </span>
      </p>
    </div>
    """
  end

  def state_card(assigns) do
    assigns =
      assigns
      |> assign(
        time:
          if !is_nil(assigns.state) do
            DateTime.to_naive(assigns.timestamp)
            |> Timex.Format.DateTime.Formatters.Relative.format!("{relative}")
          end
      )

    ~H"""
    <div class="flex flex-col text-center">
      <%= if @state in [:success,:failed] do %>
        <.status_card state={@state} time={@time} />
      <% else %>
        <div class="flex items-center gap-x-2">
          <span class="inline-block h-2 w-2 bg-gray-200 rounded-full"></span>
          <span class="text-grey-200 italic">No work orders created yet</span>
        </div>
      <% end %>
    </div>
    """
  end

  def status_card(assigns) do
    ~H"""
    <div>
      <%= if @state == :success do %>
        <div class="flex items-center gap-x-2">
          <span class="inline-block h-2 w-2 bg-green-600 rounded-full"></span>
          <span class="text-green-500 font-medium">Success</span>
        </div>
        <span class="block text-left text-gray-500 text-xs ml-4 mt-1">
          <%= @time %>
        </span>
      <% else %>
        <div class="flex items-center gap-x-2">
          <span class="inline-block h-2 w-2 bg-red-600 rounded-full"></span>
          <span class="text-red-500 font-medium">Failure</span>
        </div>
        <span class="block text-left text-gray-500 text-xs ml-4 mt-1">
          <%= @time %>
        </span>
      <% end %>
    </div>
    """
  end
end
