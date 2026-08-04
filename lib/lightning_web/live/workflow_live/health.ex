defmodule LightningWeb.WorkflowLive.Health do
  @moduledoc """
  Monitoring screen for a single workflow.

  LiveView owns the route, the breadcrumbs and the time window; the panels
  themselves are a React island so the charts can use Recharts. All panels are
  loaded in one pass and reloaded when the window changes.
  """
  use LightningWeb, :live_view

  import React

  alias Lightning.Workflows
  alias Lightning.Workflows.Health

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :ensure_workflow_belongs_to_project}
  on_mount {LightningWeb.Hooks, :check_limits}

  # {key, label, hours}. The first entry is the default.
  @windows [
    {"24h", "Last 24 hours", 24},
    {"7d", "Last 7 days", 24 * 7},
    {"30d", "Last 30 days", 24 * 30}
  ]

  attr :outcomes, :map, required: true
  attr :failure_breakdown, :map, required: true
  attr :steps_with_failures, :map, required: true
  attr :volume_over_time, :map, required: true
  attr :response_time, :map, required: true
  attr :triage, :list, required: true

  jsx("assets/js/react/components/WorkflowHealth.tsx")

  @impl true
  def mount(%{"id" => workflow_id}, _session, socket) do
    workflow = Workflows.get_workflow!(workflow_id, include: [:jobs])

    {:ok,
     socket
     |> assign(
       active_menu_item: :overview,
       workflow: workflow,
       page_title: workflow.name,
       job_count: length(workflow.jobs)
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {key, label, hours} = window(params["window"])

    {:noreply,
     socket
     |> assign(window: key, window_label: label, window_hours: hours)
     |> load_metrics()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:banner>
        <Common.dynamic_component
          :if={assigns[:banner]}
          function={@banner.function}
          args={@banner.attrs}
        />
      </:banner>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:breadcrumbs>
            <LayoutComponents.breadcrumbs>
              <LayoutComponents.breadcrumb_project_picker
                project={@project}
                label={@project_label}
              />
              <LayoutComponents.breadcrumb>
                <:label>
                  <.link navigate={~p"/projects/#{@project}/w"}>Workflows</.link>
                </:label>
              </LayoutComponents.breadcrumb>
              <LayoutComponents.breadcrumb>
                <:label>{@workflow.name}</:label>
              </LayoutComponents.breadcrumb>
            </LayoutComponents.breadcrumbs>
          </:breadcrumbs>
          <:period>{@window_label}</:period>
        </LayoutComponents.header>
      </:header>

      <LayoutComponents.centered>
        <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 class="text-2xl font-semibold text-gray-900">
              {@workflow.name}
            </h1>
            <p class="mt-1 text-sm text-gray-500">
              {@window_label} · {@metrics.outcomes.total} runs · {@job_count} jobs
            </p>
          </div>

          <.pill_tabs id="health-window-tabs" active={@window}>
            <:tab
              :for={{key, label, _hours} <- windows()}
              id={key}
              patch={~p"/projects/#{@project}/w/#{@workflow}/health?window=#{key}"}
            >
              {label}
            </:tab>
          </.pill_tabs>
        </div>

        <.WorkflowHealth
          outcomes={@metrics.outcomes}
          failure_breakdown={@metrics.failure_breakdown}
          steps_with_failures={@metrics.steps_with_failures}
          volume_over_time={@metrics.volume_over_time}
          response_time={@metrics.response_time}
          triage={@metrics.triage}
        />

        <.legend />
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end

  # Says plainly which panels are backed by stored data and which are standing
  # in for work that has not been done, so the screen cannot be mistaken for a
  # finished feature.
  defp legend(assigns) do
    ~H"""
    <section class="mt-8 rounded-lg border border-gray-200 bg-gray-50 p-5 text-sm">
      <h2 class="mb-3 text-xs font-semibold uppercase tracking-wide text-gray-500">
        What is real on this screen
      </h2>

      <dl class="grid grid-cols-1 gap-x-8 gap-y-3 md:grid-cols-2">
        <div>
          <dt class="font-medium text-gray-900">Backed by stored data</dt>
          <dd class="mt-1 text-gray-600">
            Outcomes, failure breakdown, failures per step, volume over time and
            response time are all computed from run and step records that
            Lightning already writes.
          </dd>
        </div>

        <div>
          <dt class="font-medium text-gray-900">Standing in for future work</dt>
          <dd class="mt-1 text-gray-600">
            Triage groups by error type rather than by the specific error: the
            worker sends an error message, but there is nowhere on a step to
            keep it, so it survives only in the run logs. The blame column is a
            heuristic over exit reason and error type. Row actions are not
            wired up.
          </dd>
        </div>
      </dl>
    </section>
    """
  end

  # The dead render is thrown away the moment the socket connects, so the
  # aggregates are only worth running once the client is actually there.
  defp load_metrics(socket) do
    %{workflow: workflow, window_hours: hours} = socket.assigns

    if connected?(socket) do
      to = DateTime.utc_now()
      from = DateTime.add(to, -hours, :hour)

      assign(socket, metrics: Health.load(workflow, from, to))
    else
      assign(socket, metrics: Health.empty())
    end
  end

  defp windows, do: @windows

  # Unknown keys fall back to the first window rather than raising, so a stale
  # or hand-edited URL still renders a page.
  defp window(key) do
    Enum.find(@windows, hd(@windows), fn {k, _label, _hours} -> k == key end)
  end
end
