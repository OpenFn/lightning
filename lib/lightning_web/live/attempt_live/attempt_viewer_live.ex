defmodule LightningWeb.AttemptLive.AttemptViewerLive do
  use LightningWeb, {:live_view, container: {:div, []}}

  import LightningWeb.AttemptLive.Components
  alias LightningWeb.Components.Viewers
  alias Lightning.Attempts

  alias Lightning.Repo
  alias Phoenix.LiveView.AsyncResult

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full min-h-0">
      <.attempt_detail class="flex-0" attempt={@attempt} />
      <div
        phx-hook="LogLineHighlight"
        id={"attempt-log-#{@attempt.id}"}
        data-selected-run-id={@selected_run_id}
        class="flex-1 max-h-full min-h-0 flex flex-col"
      >
        <Viewers.log_viewer
          id={@attempt.id}
          stream={@streams.log_lines}
          class="flex-0 max-h-full"
        />
      </div>
    </div>
    """
  end

  # TODO: async load the attempt

  @impl true
  def mount(_params, %{"attempt_id" => attempt_id} = session, socket) do
    job_id = Map.get(session, "job_id")
    attempt = Attempts.get(attempt_id, include: [:runs])

    # either a job_id or a run_id is passed in
    # if a run_id is passed in, we can hightlight the log lines immediately
    # if a job_id is passed in, we need to wait for the run to start
    # if neither is passed in, we can't highlight anything

    Attempts.subscribe(attempt)

    {:ok,
     socket
     |> assign(
       attempt: attempt,
       job_id: job_id,
       selected_run_id: nil
     )
     |> maybe_set_selected_run_id(attempt.runs)
     |> assign(:initial_log_lines, AsyncResult.loading())
     |> start_async(:initial_log_lines, fn ->
       {:ok, lines} =
         Repo.transaction(fn ->
           Attempts.get_log_lines(attempt)
           |> Enum.reverse()
         end)

       lines
     end)
     |> stream(:log_lines, []), layout: false}
  end

  def handle_async(:initial_log_lines, {:ok, lines}, socket) do
    socket =
      socket
      |> stream(:log_lines, lines, at: 0)
      |> then(fn socket ->
        %{initial_log_lines: initial_log_lines} = socket.assigns

        socket
        |> assign(
          :initial_log_lines,
          AsyncResult.ok(initial_log_lines, Enum.any?(lines))
        )
      end)

    {:noreply, socket}
  end

  def handle_async(:initial_log_lines, {:exit, reason}, socket) do
    %{initial_log_lines: initial_log_lines} = socket.assigns

    {:noreply,
     assign(
       socket,
       :initial_log_lines,
       AsyncResult.failed(initial_log_lines, {:exit, reason})
     )}
  end

  @impl true
  def handle_info(%Attempts.Events.RunStarted{run: run}, socket) do
    # TODO: add the run to a list of runs in assigns, preseeded with the
    # attempts' runs (if any)
    {:noreply, socket |> maybe_set_selected_run_id([run])}
  end

  def handle_info(%Attempts.Events.AttemptUpdated{attempt: attempt}, socket) do
    {:noreply, socket |> assign(attempt: attempt)}
  end

  def handle_info(%Attempts.Events.LogAppended{log_line: log_line}, socket) do
    {:noreply, socket |> stream_insert(:log_lines, log_line)}
  end

  # Fallthrough in case there are events we don't care about.
  # def handle_info(%{} = m, socket), do: {:noreply, socket}

  defp maybe_set_selected_run_id(socket, runs) when is_list(runs) do
    case socket.assigns do
      %{job_id: job_id, selected_run_id: nil} ->
        runs
        |> Enum.find(&(&1.job_id == job_id))
        |> then(fn run ->
          selected_run_id = Map.get(run || %{}, :id)
          socket |> assign(selected_run_id: selected_run_id)
        end)

      _ ->
        socket
    end
  end
end
