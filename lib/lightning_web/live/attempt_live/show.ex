defmodule LightningWeb.AttemptLive.Show do
  use LightningWeb, :live_view

  alias Lightning.Attempts
  alias Lightning.Repo
  alias Phoenix.LiveView.AsyncResult

  import LightningWeb.AttemptLive.Components
  alias LightningWeb.Components.Viewers

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def render(assigns) do
    assigns =
      assigns |> assign(:no_run_selected?, is_nil(assigns.selected_run_id))

    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:title><%= @page_title %></:title>
        </LayoutComponents.header>
      </:header>

      <LayoutComponents.centered class="@container/main">
        <.async_result :let={attempt} assign={@attempt}>
          <:loading>
            <.loading_filler />
          </:loading>
          <:failed :let={_reason}>
            there was an error loading the attemptanization
          </:failed>

          <div class="flex gap-6 @5xl/main:flex-row flex-col">
            <div class="basis-1/3 flex-none flex gap-6 @5xl/main:flex-col flex-row">
              <.attempt_detail attempt={attempt} class="flex-1 @5xl/main:flex-none" />

              <.step_list
                id={"step-list-#{attempt.id}"}
                runs={@runs}
                selected_run_id={@selected_run_id}
                class="flex-1"
              />
            </div>
            <div class="basis-2/3 flex-none flex flex-col gap-4">
              <Common.tab_bar orientation="horizontal" id="1" default_hash="log">
                <Common.tab_item orientation="horizontal" hash="log">
                  <.icon
                    name="hero-command-line"
                    class="h-5 w-5 inline-block mr-1 align-middle"
                  />
                  <span class="inline-block align-middle">Log</span>
                </Common.tab_item>
                <Common.tab_item
                  orientation="horizontal"
                  hash="input"
                  disabled={@no_run_selected?}
                >
                  <.icon
                    name="hero-arrow-down-on-square"
                    class="h-5 w-5 inline-block mr-1 align-middle"
                  />
                  <span class="inline-block align-middle">Input</span>
                </Common.tab_item>
                <Common.tab_item
                  orientation="horizontal"
                  hash="output"
                  disabled={@no_run_selected?}
                >
                  <.icon
                    name="hero-arrow-up-on-square"
                    class="h-5 w-5 inline-block mr-1 align-middle"
                  />
                  <span class="inline-block align-middle">
                    Output
                  </span>
                </Common.tab_item>
              </Common.tab_bar>

              <Common.panel_content for_hash="log">
                <Viewers.log_viewer
                  id={"attempt-log-#{attempt.id}"}
                  highlight_id={@selected_run_id}
                  stream={@streams.log_lines}
                />
              </Common.panel_content>
              <Common.panel_content for_hash="input">
                <Viewers.dataclip_viewer
                  id={"run-input-#{@selected_run_id}"}
                  stream={@streams.input_dataclip}
                />
              </Common.panel_content>
              <Common.panel_content for_hash="output">
                <Viewers.dataclip_viewer
                  id={"run-output-#{@selected_run_id}"}
                  stream={@streams.output_dataclip}
                />
              </Common.panel_content>
            </div>
          </div>
        </.async_result>
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(
       active_menu_item: :runs,
       page_title: "Attempt",
       selected_run_id: nil,
       runs: []
     )
     |> stream(:log_lines, [])
     |> stream(:input_dataclip, [])
     |> assign(:input_dataclip, false)
     |> stream(:output_dataclip, [])
     |> assign(:output_dataclip, false)
     |> assign(:attempt, AsyncResult.loading())
     |> assign(:log_lines, AsyncResult.loading())
     |> start_async(:attempt, fn -> Attempts.get(id, include: [runs: :job]) end)}
  end

  defp maybe_set_selected_run(socket) do
    %{selected_run_id: selected_run_id, runs: runs} = socket.assigns

    selected_run = runs |> Enum.find(&(&1.id == selected_run_id))

    socket
    |> assign(selected_run: selected_run)
    |> maybe_load_input_dataclip()
    |> maybe_load_output_dataclip()
  end

  @impl true
  def handle_params(params, _, socket) do
    selected_run_id = Map.get(params, "r")

    {:noreply, socket |> apply_selected_run_id(selected_run_id)}
  end

  defp apply_selected_run_id(socket, id) do
    case id do
      nil ->
        socket
        |> assign(
          selected_run_id: nil,
          selected_run: nil,
          input_dataclip: false,
          output_dataclip: false
        )
        |> stream(:input_dataclip, [], reset: true)
        |> stream(:output_dataclip, [], reset: true)

      _ ->
        socket
        |> assign(:selected_run_id, id)
        |> then(fn socket ->
          if socket |> changed?(:selected_run_id) do
            socket
            |> assign(input_dataclip: false, output_dataclip: false)
            |> stream(:input_dataclip, [], reset: true)
            |> stream(:output_dataclip, [], reset: true)
          else
            socket
          end
        end)
        |> maybe_set_selected_run()
    end
  end

  defp maybe_load_input_dataclip(socket) do
    live_view_pid = self()
    import Ecto.Query

    %{selected_run: selected_run} = socket.assigns

    if selected_run && socket.assigns.input_dataclip == false do
      Task.start(fn ->
        lines =
          from(d in Ecto.assoc(selected_run, :input_dataclip),
            select: d.body
          )
          |> Repo.one()
          |> Jason.encode!(pretty: true)
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Enum.map(fn {line, index} ->
            %{id: index, line: line, index: index}
          end)

        send(live_view_pid, {:input_dataclip, lines})
      end)

      socket |> assign(:input_dataclip, true)
    else
      socket
    end
  end

  defp maybe_load_output_dataclip(socket) do
    live_view_pid = self()

    %{selected_run: selected_run} = socket.assigns

    if selected_run && selected_run.output_dataclip_id &&
         socket.assigns.output_dataclip == false do
      Task.start(fn ->
        lines = get_output_dataclip_lines(selected_run)

        send(live_view_pid, {:output_dataclip, lines})
      end)

      socket |> assign(:output_dataclip, true)
    else
      socket
    end
  end

  defp get_output_dataclip_lines(run) do
    import Ecto.Query

    from(d in Ecto.assoc(run, :output_dataclip),
      select: d.body
    )
    |> Repo.one()
    |> case do
      nil ->
        []

      body ->
        body
        |> Jason.encode!(pretty: true)
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.map(fn {line, index} ->
          %{id: index, line: line, index: index}
        end)
    end
  end

  @impl true
  def handle_info({:log_line_chunk, lines}, socket) do
    {:noreply, socket |> stream(:log_lines, lines)}
  end

  def handle_info({:input_dataclip, lines}, socket) do
    {:noreply, socket |> stream(:input_dataclip, lines)}
  end

  def handle_info({:output_dataclip, lines}, socket) do
    {:noreply, socket |> stream(:output_dataclip, lines)}
  end

  def handle_info(
        %Attempts.Events.AttemptUpdated{attempt: updated_attempt},
        socket
      ) do
    {:noreply,
     socket
     |> assign(attempt: AsyncResult.ok(socket.assigns.attempt, updated_attempt))}
  end

  def handle_info(%{__struct__: type, run: run}, socket)
      when type in [Attempts.Events.RunStarted, Attempts.Events.RunCompleted] do
    {:noreply,
     socket
     |> add_or_update_run(run)
     |> maybe_set_selected_run()}
  end

  def handle_info(%Attempts.Events.LogAppended{log_line: log_line}, socket) do
    {:noreply, socket |> stream_insert(:log_lines, log_line)}
  end

  def handle_async(:attempt, {:ok, updated_attempt}, socket) do
    %{attempt: attempt} = socket.assigns

    Attempts.subscribe(updated_attempt)

    live_view_pid = self()

    {:noreply,
     socket
     |> assign(
       attempt: AsyncResult.ok(attempt, updated_attempt),
       # set the initial set of runs
       runs: updated_attempt.runs
     )
     |> start_async(
       :log_lines,
       fn ->
         # This doesn't have to be a liveview async, but it might be easier to
         # leverage it for cancelling the stream if the user navigates away
         Repo.transaction(fn ->
           Attempts.get_log_lines(updated_attempt)
           |> Stream.chunk_every(5)
           |> Stream.each(fn lines ->
             send(live_view_pid, {:log_line_chunk, lines})
           end)
           |> Stream.run()
         end)

         :ok
       end
     )
     |> maybe_set_selected_run()}
  end

  def handle_async(:attempt, {:exit, reason}, socket) do
    %{attempt: attempt} = socket.assigns

    {:noreply,
     assign(socket, :attempt, AsyncResult.failed(attempt, {:exit, reason}))}
  end

  def handle_async(:log_lines, {:ok, _}, socket) do
    %{log_lines: log_lines} = socket.assigns

    socket =
      socket
      |> assign(log_lines: AsyncResult.ok(log_lines, :ok))

    {:noreply, socket}
  end

  def handle_async(:log_lines, {:exit, reason}, socket) do
    %{log_lines: log_lines} = socket.assigns

    {:noreply,
     assign(socket, :log_lines, AsyncResult.failed(log_lines, {:exit, reason}))}
  end

  def loading_filler(assigns) do
    ~H"""
    <.detail_list class="animate-pulse">
      <.list_item>
        <:label>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-16">&nbsp;</span>
        </:label>
        <:value>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-24"></span>
        </:value>
      </.list_item>
      <.list_item>
        <:label>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-12">&nbsp;</span>
        </:label>
        <:value>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-12"></span>
        </:value>
      </.list_item>
      <.list_item>
        <:label>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-12">&nbsp;</span>
        </:label>
        <:value>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-24"></span>
        </:value>
      </.list_item>
    </.detail_list>
    """
  end

  @doc """
  Renders a list of runs for the attempt
  """
  attr :runs, :list, required: true
  attr :selected_run_id, :string, default: nil
  attr :rest, :global

  def step_list(assigns) do
    ~H"""
    <ul {@rest} role="list" class="-mb-8">
      <li :for={run <- @runs} data-run-id={run.id} class="group">
        <div class="relative pb-8">
          <span
            class="absolute left-4 top-4 -ml-px h-full w-0.5 bg-gray-200 group-last:hidden"
            aria-hidden="true"
          >
          </span>
          <.link patch={"?r=#{run.id}"} id={"select-run-#{run.id}"}>
            <div class={[
              "relative flex space-x-3 hover:cursor-pointer",
              if(run.id == @selected_run_id,
                do:
                  "rounded-full outline outline-2 outline-primary-500 outline-offset-4",
                else: ""
              )
            ]}>
              <div>
                <.run_state_circle run={run} />
              </div>
              <div class="flex min-w-0 flex-1 justify-between space-x-4 pt-1.5 pr-1.5">
                <div>
                  <p class="text-sm text-gray-900">
                    <%= run.job.name %>
                  </p>
                </div>
                <div class="whitespace-nowrap text-right text-sm text-gray-500">
                  <.run_duration run={run} />
                </div>
              </div>
            </div>
          </.link>
        </div>
      </li>
    </ul>
    """
  end

  defp run_duration(assigns) do
    ~H"""
    <%= cond do %>
      <% is_nil(@run.started_at) -> %>
        Unknown
      <% is_nil(@run.finished_at) -> %>
        Running...
      <% true -> %>
        <%= DateTime.to_unix(@run.finished_at, :millisecond) -
          DateTime.to_unix(@run.started_at, :millisecond) %> ms
    <% end %>
    """
  end

  defp add_or_update_run(socket, run) do
    %{runs: runs} = socket.assigns

    run = Repo.preload(run, :job)

    case Enum.find_index(runs, &(&1.id == run.id)) do
      nil ->
        runs = [run | runs] |> Enum.sort_by(& &1.started_at)
        socket |> assign(runs: runs)

      index ->
        socket |> assign(runs: List.replace_at(runs, index, run))
    end
  end
end
