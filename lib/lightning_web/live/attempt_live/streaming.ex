defmodule LightningWeb.AttemptLive.Streaming do
  import Phoenix.Component, only: [assign: 2, changed?: 2]
  import Phoenix.LiveView
  import Ecto.Query

  alias Lightning.Attempts
  alias Lightning.AttemptStep
  alias Lightning.Credentials
  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Step
  alias Lightning.Repo
  alias Lightning.Scrubber
  alias Phoenix.LiveView.AsyncResult

  @doc """
  Starts an async process that will fetch the attempt with the given ID.
  """
  @spec get_attempt_async(Phoenix.LiveView.Socket.t(), Ecto.UUID.t()) ::
          Phoenix.LiveView.Socket.t()
  def get_attempt_async(socket, attempt_id) do
    socket
    |> start_async(:attempt, fn ->
      Attempts.get(attempt_id, include: [steps: [:job], workflow: [:project]])
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

      %Dataclip{body: nil} ->
        {nil, []}

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
    attempt_step =
      from(as in AttemptStep,
        where: as.step_id == ^step_id,
        select: as.attempt_id
      )

    from(as in AttemptStep,
      join: s in assoc(as, :step),
      join: j in assoc(s, :job),
      join: c in assoc(j, :credential),
      where: as.attempt_id in subquery(attempt_step),
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
      unquote(handle_asyncs())
    end
  end

  defp handle_infos do
    quote do
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
         |> assign(
           attempt: AsyncResult.ok(socket.assigns.attempt, updated_attempt)
         )}
      end

      def handle_info(%{__struct__: type, step: step}, socket)
          when type in [
                 Attempts.Events.StepStarted,
                 Attempts.Events.StepCompleted
               ] do
        {:noreply,
         socket
         |> add_or_update_step(step)
         |> handle_steps_change()}
      end

      def handle_info(
            %Attempts.Events.LogAppended{log_line: log_line},
            socket
          ) do
        {:noreply, socket |> stream_insert(:log_lines, log_line)}
      end
    end
  end

  defp handle_asyncs do
    quote do
      def handle_async(:attempt, {:ok, nil}, socket) do
        {:noreply,
         socket
         |> assign(
           :attempt,
           AsyncResult.failed(socket.assigns.attempt, :not_found)
         )}
      end

      def handle_async(:attempt, {:ok, updated_attempt}, socket) do
        %{attempt: attempt} = socket.assigns

        Attempts.subscribe(updated_attempt)

        live_view_pid = self()

        {:noreply,
         socket
         |> assign(
           attempt: AsyncResult.ok(attempt, updated_attempt),
           # set the initial set of steps
           steps: updated_attempt.steps |> sort_steps(),
           project: updated_attempt.workflow.project,
           workflow: updated_attempt.workflow
         )
         |> assign_async(
           :log_lines,
           fn ->
             Repo.transaction(fn ->
               Attempts.get_log_lines(updated_attempt)
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

      def handle_async(:attempt, {:exit, reason}, socket) do
        %{attempt: attempt} = socket.assigns

        {:noreply,
         assign(
           socket,
           :attempt,
           AsyncResult.failed(attempt, {:exit, reason})
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
