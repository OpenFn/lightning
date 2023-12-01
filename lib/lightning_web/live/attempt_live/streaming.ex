defmodule LightningWeb.AttemptLive.Streaming do
  alias Lightning.Repo
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 2]

  alias Lightning.Attempts
  alias Phoenix.LiveView.AsyncResult

  def add_or_update_run(socket, run) do
    %{runs: runs} = socket.assigns

    run = Lightning.Repo.preload(run, :job)

    case Enum.find_index(runs, &(&1.id == run.id)) do
      nil ->
        runs = [run | runs] |> Enum.sort_by(& &1.started_at)
        socket |> assign(runs: runs)

      index ->
        socket |> assign(runs: List.replace_at(runs, index, run))
    end
  end

  def get_dataclip_lines(run, field) do
    import Ecto.Query

    from(d in Ecto.assoc(run, field),
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
        |> Stream.with_index(1)
        |> Stream.map(fn {line, index} ->
          %{id: index, line: line, index: index}
        end)
    end
  end

  def maybe_load_input_dataclip(socket, chunk_size) do
    live_view_pid = self()

    %{selected_run: selected_run} = socket.assigns

    if selected_run && needs_dataclip_stream?(socket, :input_dataclip) do
      socket
      |> assign_async(:input_dataclip, fn ->
        get_dataclip_lines(selected_run, :input_dataclip)
        |> Stream.chunk_every(chunk_size)
        |> Stream.each(fn lines ->
          send(live_view_pid, {:input_dataclip, lines})
        end)
        |> Stream.run()

        {:ok, %{input_dataclip: selected_run.id}}
      end)
    else
      socket
    end
  end

  def maybe_load_output_dataclip(socket, chunk_size) do
    live_view_pid = self()

    %{selected_run: selected_run} = socket.assigns

    if selected_run && selected_run.output_dataclip_id &&
         needs_dataclip_stream?(socket, :output_dataclip) do
      socket
      |> assign_async(:output_dataclip, fn ->
        get_dataclip_lines(selected_run, :output_dataclip)
        |> Stream.chunk_every(chunk_size)
        |> Stream.each(fn lines ->
          send(live_view_pid, {:output_dataclip, lines})
        end)
        |> Stream.run()

        {:ok, %{output_dataclip: selected_run.id}}
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

  def unselect_run(socket) do
    socket
    |> assign(
      selected_run_id: nil,
      selected_run: nil,
      input_dataclip: false,
      output_dataclip: false
    )
    |> reset_dataclip_streams()
  end

  defp needs_dataclip_stream?(socket, assign) do
    selected_run_id = socket.assigns.selected_run_id

    case socket.assigns[assign] do
      false ->
        true

      %Phoenix.LiveView.AsyncResult{loading: true} ->
        false

      %Phoenix.LiveView.AsyncResult{ok?: true, result: ^selected_run_id} ->
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

  defp handle_infos() do
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

      def handle_info(%{__struct__: type, run: run}, socket)
          when type in [
                 Attempts.Events.RunStarted,
                 Attempts.Events.RunCompleted
               ] do
        {:noreply,
         socket
         |> add_or_update_run(run)
         |> handle_runs_change()}
      end

      def handle_info(
            %Attempts.Events.LogAppended{log_line: log_line},
            socket
          ) do
        {:noreply, socket |> stream_insert(:log_lines, log_line)}
      end
    end
  end

  defp handle_asyncs() do
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
           # set the initial set of runs
           runs: updated_attempt.runs
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
         |> handle_runs_change()}
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

  defp helpers() do
    quote do
      import unquote(__MODULE__)

      def maybe_load_input_dataclip(socket) do
        maybe_load_input_dataclip(socket, @chunk_size)
      end

      def maybe_load_output_dataclip(socket) do
        maybe_load_output_dataclip(socket, @chunk_size)
      end
    end
  end
end
