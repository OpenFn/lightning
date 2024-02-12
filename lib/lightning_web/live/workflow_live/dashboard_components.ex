defmodule LightningWeb.WorkflowLive.DashboardComponents do
  @moduledoc false
  use LightningWeb, :component

  alias Lightning.DashboardStats.ProjectMetrics
  alias Lightning.Projects.Project
  alias Lightning.WorkOrders.SearchParams
  alias Timex.Format.DateTime.Formatters.Relative

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
        period={@period}
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
          period={@period}
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
                  ~p"/projects/#{@project.id}/history?#{%{filters: Map.merge(@wo_filters, %{workflow_id: workflow.id})}}"
                }
              >
                <%= workflow.workorders_count %>
              </.link>
            </div>
            <div class="text-gray-500 text-xs">
              (<%= workflow.step_count %> steps,
              <span>
                <%= workflow.step_success_rate %>% success
              </span>
              )
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
                    ~p"/projects/#{@project.id}/history?#{%{filters: Map.merge(@failed_wo_filters, %{workflow_id: workflow.id})}}"
                  }
                >
                  <%= workflow.failed_workorders_count %>
                </.link>
              </div>
              <div class="text-gray-500 text-xs">
                Latest failure <%= workflow.last_failed_workorder.updated_at
                |> Relative.format!("{relative}") %>
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
          Relative.format!(
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
            <p class="text-gray-500 text-xs ml-3 mt-1">
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
        <:value><%= @metrics.work_order_metrics.total %></:value>
        <:suffix>
          <.link
            navigate={
              ~p"/projects/#{@project}/history?#{%{filters: @pending_filters}}"
            }
            class="text-indigo-700 hover:underline"
          >
            (<%= @metrics.work_order_metrics.pending %> pending)
          </.link>
        </:suffix>
      </.metric_card>
      <.metric_card title="Runs">
        <:value><%= @metrics.run_metrics.total %></:value>
        <:suffix>
          (<%= @metrics.run_metrics.pending %> pending)
        </:suffix>
      </.metric_card>
      <.metric_card title="Successful Runs">
        <:value><%= @metrics.run_metrics.success %></:value>
        <:suffix>
          (<%= @metrics.run_metrics.success_rate %>%)
        </:suffix>
      </.metric_card>
      <.metric_card title="Work Orders in failed state">
        <:value><%= @metrics.work_order_metrics.failed %></:value>
        <:suffix>
          (<%= @metrics.work_order_metrics.failed_percentage %>%)
        </:suffix>
        <:link>
          <.link
            navigate={
              ~p"/projects/#{@project}/history?#{%{filters: @failed_filters}}"
            }
            class="text-indigo-700 hover:underline"
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
        <%= @title %>
      </h2>
      <div class="flex space-x-1 items-baseline text-3xl font-bold text-gray-800">
        <div><%= render_slot(@value) %></div>
        <div class="text-xs font-normal grow">
          <%= render_slot(@suffix) %>
        </div>
        <div class="text-xs font-normal">
          <%= render_slot(@link) %>
        </div>
      </div>
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
            |> Relative.format!("{relative}")
          end
      )

    ~H"""
    <div class="flex flex-col text-center">
      <%= if is_nil(@state) do %>
        <div class="flex items-center gap-x-2">
          <span class="inline-block h-2 w-2 bg-gray-200 rounded-full"></span>
          <span class="text-grey-200 italic">Nothing <%= @period %></span>
        </div>
      <% else %>
        <.status_card state={@state} time={@time} />
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
        <span class="inline-block relative flex h-2 w-2">
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
        <span class={[@font_color, "font-medium"]}><%= @text %></span>
      </div>
      <span class="block text-left text-gray-500 text-xs ml-4 mt-1">
        <%= @time %>
      </span>
    </div>
    """
  end
end
