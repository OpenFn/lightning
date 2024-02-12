defmodule LightningWeb.RunLive.Streaming do
  import Phoenix.Component, only: [assign: 2, changed?: 2]
  import Phoenix.LiveView
  import Ecto.Query

  alias Lightning.Credentials
  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Step
  alias Lightning.Repo
  alias Lightning.Runs
  alias Lightning.RunStep
  alias Lightning.Scrubber
  alias Phoenix.LiveView.AsyncResult

  @doc """
  Starts an async process that will fetch the run with the given ID.
  """
  @spec get_run_async(Phoenix.LiveView.Socket.t(), Ecto.UUID.t()) ::
          Phoenix.LiveView.Socket.t()
  def get_run_async(socket, run_id) do
    socket
    |> start_async(:run, fn ->
      Runs.get(run_id, include: [steps: [:job], workflow: [:project]])
    end)
  end

  def add_or_update_step(socket, step) do
    %{steps: steps} = socket.assigns

    step = Lightning.Repo.preload(step, :job)

    case Enum.find_index(steps, &(&1.id == step.id)) do
      nil ->
        steps =
          [step | steps]
          |> sort_steps()

        socket |> assign(steps: steps)

      index ->
        socket |> assign(steps: List.replace_at(steps, index, step))
    end
  end

  def get_dataclip_lines(step, field) do
    import Ecto.Query

    from(d in Ecto.assoc(step, field))
    |> Lightning.Invocation.Query.select_as_input()
    |> Repo.one()
    |> case do
      nil ->
        {nil, []}

      %Dataclip{id: id, type: type, body: nil, wiped_at: %{} = wiped_at} ->
        {%{id: id, step_id: step.id, type: type, wiped_at: wiped_at}, []}

      %Dataclip{id: id, body: body, type: type, wiped_at: wiped_at} ->
        {%{id: id, step_id: step.id, type: type, wiped_at: wiped_at},
         body
         |> Jason.encode!(pretty: true)
         |> maybe_scrub(type, step)
         |> String.split("\n")
         |> Stream.with_index(1)
         |> Stream.map(fn {line, index} ->
           %{id: index, line: line, index: index}
         end)}
    end
  end

  def maybe_load_input_dataclip(socket, chunk_size) do
    live_view_pid = self()

    %{selected_step: selected_step} = socket.assigns

    if selected_step && needs_dataclip_stream?(socket, :input_dataclip) do
      socket
      |> assign_async(:input_dataclip, fn ->
        {dataclip, lines} =
          get_dataclip_lines(selected_step, :input_dataclip)

        lines
        |> Stream.chunk_every(chunk_size)
        |> Stream.each(fn lines ->
          send(live_view_pid, {:input_dataclip, lines})
        end)
        |> Stream.run()

        {:ok, %{input_dataclip: dataclip}}
      end)
    else
      socket
    end
  end

  def maybe_load_output_dataclip(socket, chunk_size) do
    live_view_pid = self()

    %{selected_step: selected_step} = socket.assigns

    if selected_step && selected_step.output_dataclip_id &&
         needs_dataclip_stream?(socket, :output_dataclip) do
      socket
      |> assign_async(:output_dataclip, fn ->
        {dataclip, lines} =
          get_dataclip_lines(selected_step, :output_dataclip)

        lines
        |> Stream.chunk_every(chunk_size)
        |> Stream.each(fn lines ->
          send(live_view_pid, {:output_dataclip, lines})
        end)
        |> Stream.run()

        {:ok, %{output_dataclip: dataclip}}
      end)
    else
      socket
    end
  end

  def reset_dataclip_streams(socket) do
    socket
    |> stream(:input_dataclip, [], reset: true)
    |> stream(:output_dataclip, [], reset: true)
    |> assign(
      input_dataclip_stream_empty?: true,
      output_dataclip_stream_empty?: true
    )
  end

  def unselect_step(socket) do
    socket
    |> assign(
      selected_step_id: nil,
      selected_step: nil,
      input_dataclip: false,
      output_dataclip: false
    )
    |> reset_dataclip_streams()
  end

  def sort_steps(steps) do
    steps
    |> Enum.sort(fn x, y ->
      DateTime.compare(x.started_at, y.started_at) == :lt
    end)
  end

  defp maybe_scrub(body_str, :step_result, %Step{
         id: step_id,
         started_at: started_at
       }) do
    run_step =
      from(as in RunStep,
        where: as.step_id == ^step_id,
        select: as.run_id
      )

    from(as in RunStep,
      join: s in assoc(as, :step),
      join: j in assoc(s, :job),
      join: c in assoc(j, :credential),
      where: as.run_id in subquery(run_step),
      where: s.started_at <= ^started_at,
      select: c
    )
    |> Repo.all()
    |> case do
      [] ->
        body_str

      credentials ->
        {:ok, scrubber} = Scrubber.start_link([])

        credentials
        |> Enum.reduce(scrubber, fn credential, scrubber ->
          samples = Credentials.sensitive_values_for(credential)
          basic_auth = Credentials.basic_auth_for(credential)
          :ok = Scrubber.add_samples(scrubber, samples, basic_auth)
          scrubber
        end)
        |> Scrubber.scrub(body_str)
    end
  end

  defp maybe_scrub(body_str, _type, _step), do: body_str

  defp needs_dataclip_stream?(socket, assign) do
    selected_step_id = socket.assigns.selected_step_id

    case socket.assigns[assign] do
      false ->
        true

      %Phoenix.LiveView.AsyncResult{loading: true} ->
        false

      %Phoenix.LiveView.AsyncResult{
        ok?: true,
        result: %{step_id: ^selected_step_id}
      } ->
        false

      _ ->
        true
    end
  end

  defmacro __using__(opts) do
    quote location: :keep do
      chunk_size = unquote(opts[:chunk_size]) || 50
      Module.put_attribute(__MODULE__, :chunk_size, chunk_size)

      unquote(helpers())
      unquote(handle_infos())
      @impl true
      unquote(handle_asyncs())
    end
  end

  defp handle_infos do
    quote do
      @impl true
      def handle_info({:log_line_chunk, lines}, socket) do
        {:noreply,
         socket
         |> stream(:log_lines, lines)
         |> assign(:log_lines_stream_empty?, false)}
      end

      def handle_info({:input_dataclip, lines}, socket) do
        {:noreply,
         socket
         |> stream(:input_dataclip, lines)
         |> assign(:input_dataclip_stream_empty?, false)}
      end

      def handle_info({:output_dataclip, lines}, socket) do
        {:noreply,
         socket
         |> stream(:output_dataclip, lines)
         |> assign(:output_dataclip_stream_empty?, false)}
      end

      def handle_info(
            %Runs.Events.RunUpdated{run: updated_run},
            socket
          ) do
        {:noreply,
         socket
         |> assign(run: AsyncResult.ok(socket.assigns.run, updated_run))}
      end

      def handle_info(%{__struct__: type, step: step}, socket)
          when type in [
                 Runs.Events.StepStarted,
                 Runs.Events.StepCompleted
               ] do
        {:noreply,
         socket
         |> add_or_update_step(step)
         |> handle_steps_change()}
      end

      def handle_info(
            %Runs.Events.LogAppended{log_line: log_line},
            socket
          ) do
        {:noreply,
         socket
         |> stream_insert(:log_lines, log_line)
         |> assign(:log_lines_stream_empty?, false)}
      end
    end
  end

  defp handle_asyncs do
    quote do
      def handle_async(:run, {:ok, nil}, socket) do
        {:noreply,
         socket
         |> assign(
           :run,
           AsyncResult.failed(socket.assigns.run, :not_found)
         )}
      end

      def handle_async(:run, {:ok, updated_run}, socket) do
        %{run: run} = socket.assigns

        Runs.subscribe(updated_run)

        live_view_pid = self()

        {:noreply,
         socket
         |> assign(
           run: AsyncResult.ok(run, updated_run),
           # set the initial set of steps
           steps: updated_run.steps |> sort_steps(),
           project: updated_run.workflow.project,
           workflow: updated_run.workflow
         )
         |> assign_async(
           :log_lines,
           fn ->
             Repo.transaction(fn ->
               Runs.get_log_lines(updated_run)
               |> Stream.chunk_every(@chunk_size)
               |> Stream.each(fn lines ->
                 send(live_view_pid, {:log_line_chunk, lines})
               end)
               |> Stream.run()
             end)

             {:ok, %{log_lines: :ok}}
           end
         )
         |> handle_steps_change()}
      end

      def handle_async(:run, {:exit, reason}, socket) do
        %{run: run} = socket.assigns

        {:noreply,
         assign(
           socket,
           :run,
           AsyncResult.failed(run, {:exit, reason})
         )}
      end
    end
  end

  defp helpers do
    quote do
      import unquote(__MODULE__)

      def maybe_load_input_dataclip(socket) do
        maybe_load_input_dataclip(socket, @chunk_size)
      end

      def maybe_load_output_dataclip(socket) do
        maybe_load_output_dataclip(socket, @chunk_size)
      end

      def apply_selected_step_id(socket, id) do
        case id do
          nil ->
            socket
            |> unselect_step()

          _ ->
            socket
            |> assign(selected_step_id: id)
            |> then(fn socket ->
              if changed?(socket, :selected_step_id) do
                reset_dataclip_streams(socket)
              else
                socket
              end
            end)
            |> handle_steps_change()
        end
      end
    end
  end
end
