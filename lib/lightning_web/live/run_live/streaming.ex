defmodule LightningWeb.RunLive.Streaming do
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView
  import Ecto.Query

  alias Lightning.Repo
  alias Lightning.Runs
  alias Phoenix.LiveView.AsyncResult

  @doc """
  Starts an async process that will fetch the run with the given ID.
  """
  @spec get_run_async(Phoenix.LiveView.Socket.t(), Ecto.UUID.t()) ::
          Phoenix.LiveView.Socket.t()
  def get_run_async(socket, run_id) do
    socket
    |> start_async(:run, fn ->
      Runs.get(run_id,
        include: [
          steps: [:job, snapshot: [triggers: :webhook_auth_methods]],
          workflow: [:project],
          snapshot: [triggers: :webhook_auth_methods]
        ]
      )
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

  def get_dataclip(step, field) do
    import Ecto.Query

    from(d in Ecto.assoc(step, field))
    |> Repo.one()
  end

  def maybe_load_input_dataclip(socket) do
    %{selected_step: selected_step, input_dataclip: dataclip} = socket.assigns

    if selected_step &&
         (!dataclip or selected_step.input_dataclip_id != dataclip.id) do
      socket
      |> assign(input_dataclip: get_dataclip(selected_step, :input_dataclip))
    else
      socket
    end
  end

  def maybe_load_output_dataclip(socket) do
    %{selected_step: selected_step, output_dataclip: dataclip} = socket.assigns

    if selected_step &&
         (!dataclip or selected_step.output_dataclip_id != dataclip.id) do
      socket
      |> assign(output_dataclip: get_dataclip(selected_step, :output_dataclip))
    else
      socket
    end
  end

  def unselect_step(socket) do
    socket
    |> assign(
      selected_step_id: nil,
      selected_step: nil,
      input_dataclip: nil,
      output_dataclip: nil
    )
  end

  def sort_steps(steps) do
    steps
    |> Enum.sort(fn x, y ->
      DateTime.compare(x.started_at, y.started_at) == :lt
    end)
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
         |> assign(:log_lines_empty?, false)
         |> push_event("logs-#{socket.assigns.run.result.id}", %{logs: lines})}
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
         |> assign(:log_lines_empty?, false)
         |> push_event("logs-#{socket.assigns.run.result.id}", %{
           logs: [log_line]
         })}
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

      def apply_selected_step_id(socket, id) do
        case id do
          nil ->
            socket
            |> unselect_step()

          _ ->
            socket
            |> assign(selected_step_id: id)
            |> handle_steps_change()
        end
      end
    end
  end
end
