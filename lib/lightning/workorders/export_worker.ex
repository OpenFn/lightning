defmodule Lightning.WorkOrders.ExportWorker do
  use Oban.Worker, queue: :history_exports, max_attempts: 1

  require Logger

  alias Lightning.Invocation.Dataclip
  alias Lightning.Repo
  alias Lightning.Invocation
  alias Lightning.Projects.Project
  alias Lightning.WorkOrders.SearchParams

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"project_id" => project_id, "search_params" => params}
      }) do
    search_params = SearchParams.from_map(params)

    with {:ok, project} <- get_project(project_id),
         :ok <- process_export(project, search_params) do
      Logger.info("Export completed successfully.")
      :ok
    else
      {:error, reason} ->
        Logger.error("Export failed with reason: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def enqueue_export(project, search_params) do
    job = %{
      "project_id" => project.id,
      "search_params" => search_params
    }

    case Oban.insert(
           Lightning.Oban,
           Oban.Job.new(job, worker: __MODULE__, queue: :history_exports)
         ) do
      {:ok, _job} ->
        :ok

      {:error, changeset} ->
        Logger.error("Failed to enqueue export job: #{inspect(changeset)}")
        {:error, changeset}
    end
  end

  defp process_export(%Project{} = project, %SearchParams{} = params) do
    workorders_query =
      Invocation.search_workorders_for_export_query(project, params)

    workorders_stream = Repo.stream(workorders_query, max_rows: 100)

    result =
      Repo.transaction(fn ->
        export_result =
          workorders_stream
          |> Stream.map(&preload_and_extract_entities/1)
          |> Enum.reduce(%{}, &combine_entities/2)

        with {:ok, export_dir} <- create_export_directories(),
             :ok <- process_logs_async(export_result.log_lines, export_dir),
             :ok <-
               process_dataclips_async(
                 export_result.input_dataclips ++ export_result.output_dataclips,
                 export_dir
               ),
             {:ok, json_data} <- format_and_encode_export(export_result),
             :ok <- write_export_file(json_data, export_dir) do
          Logger.info("Export content written to #{export_dir.root_dir}")
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_project(project_id) do
    case Repo.get(Project, project_id) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp preload_and_extract_entities(work_order) do
    work_order
    |> Repo.preload([
      :workflow,
      runs: [
        :run_steps,
        :log_lines,
        steps: [
          input_dataclip: [:project, :source_step],
          output_dataclip: [:project, :source_step]
        ]
      ]
    ])
    |> extract_entities()
  end

  defp extract_entities(work_order) do
    runs = work_order.runs

    steps = Enum.flat_map(runs, & &1.steps)
    run_steps = Enum.flat_map(runs, & &1.run_steps)
    log_lines = Enum.flat_map(runs, & &1.log_lines)
    input_dataclips = Enum.map(steps, & &1.input_dataclip)
    output_dataclips = Enum.map(steps, & &1.output_dataclip)

    %{
      runs: runs,
      steps: steps,
      run_steps: run_steps,
      log_lines: log_lines,
      work_orders: [work_order],
      input_dataclips: input_dataclips,
      output_dataclips: output_dataclips
    }
  end

  defp combine_entities(entity1, entity2) do
    Map.merge(entity1, entity2, fn _key, val1, val2 -> val1 ++ val2 end)
  end

  defp create_export_directories() do
    with {:ok, root_dir} <- Temp.mkdir("openfn"),
         logs_dir = Path.join([root_dir, "logs"]),
         dataclips_dir = Path.join([root_dir, "dataclips"]),
         :ok <- File.mkdir_p(logs_dir),
         :ok <- File.mkdir_p(dataclips_dir) do
      {:ok,
       %{
         root_dir: root_dir,
         logs_dir: logs_dir,
         dataclips_dir: dataclips_dir
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_logs_async(log_lines, %{logs_dir: logs_dir}) do
    log_lines
    |> Enum.group_by(& &1.run_id)
    |> Task.async_stream(fn {run_id, logs} ->
      combined_logs = Enum.map_join(logs, "\n", & &1.message)
      file_path = Path.join([logs_dir, "#{run_id}.txt"])

      case File.write(file_path, combined_logs) do
        :ok ->
          :ok

        error ->
          Logger.error(
            "Failed to write logs for run #{run_id}: #{inspect(error)}"
          )
      end
    end)
    |> Enum.each(fn
      {:ok, :ok} ->
        :ok

      {:ok, error} ->
        Logger.error("Error in log processing: #{inspect(error)}")

      {:exit, reason} ->
        Logger.error("Task exited with reason: #{inspect(reason)}")
    end)

    :ok
  end

  defp process_dataclips_async(dataclips, %{dataclips_dir: dataclips_dir}) do
    dataclips
    |> Task.async_stream(fn dataclip ->
      case format_dataclip(dataclip) do
        {:ok, data} ->
          file_path = Path.join([dataclips_dir, "#{dataclip.id}.json"])

          case File.write(file_path, data) do
            :ok ->
              :ok

            error ->
              Logger.error(
                "Failed to write data clip #{dataclip.id}: #{inspect(error)}"
              )
          end

        {:error, error} ->
          Logger.error(
            "Error serializing data clip #{dataclip.id}: #{inspect(error)}"
          )
      end
    end)
    |> Enum.each(fn
      {:ok, :ok} ->
        :ok

      {:ok, error} ->
        Logger.error("Error in data clip processing: #{inspect(error)}")

      {:exit, reason} ->
        Logger.error("Task exited with reason: #{inspect(reason)}")
    end)

    :ok
  end

  defp format_dataclip(%Dataclip{
         body: body,
         type: type,
         wiped_at: wiped_at,
         project: project,
         source_step: source_step
       }) do
    %{
      body: body,
      type: type,
      wiped_at: wiped_at,
      project: project.id,
      source_step: source_step && source_step.id
    }
    |> Jason.encode(pretty: true)
  end

  defp format_and_encode_export(%{
         work_orders: work_orders,
         runs: runs,
         steps: steps,
         run_steps: run_steps
       }) do
    export_data = %{
      work_orders: format_work_orders(work_orders),
      runs: format_runs(runs),
      steps: format_steps(steps),
      run_steps: format_run_steps(run_steps)
    }

    Jason.encode(export_data, pretty: true)
  end

  defp format_work_orders(work_orders) do
    Enum.map(work_orders, fn wo ->
      %{
        id: wo.id,
        workflow_id: wo.workflow_id,
        workflow_name: wo.workflow.name,
        received_at: wo.inserted_at,
        last_activity: wo.updated_at,
        status: wo.state
      }
    end)
  end

  defp format_runs(runs) do
    Enum.map(runs, fn r ->
      %{
        id: r.id,
        work_order_id: r.work_order_id,
        finished_at: r.finished_at,
        status: r.state
      }
    end)
  end

  defp format_steps(steps) do
    Enum.map(steps, fn s ->
      %{
        id: s.id,
        status: s.exit_reason,
        inserted_at: s.inserted_at,
        input_dataclip: s.input_dataclip_id,
        output_dataclip: s.output_dataclip_id
      }
    end)
  end

  defp format_run_steps(run_steps) do
    Enum.map(run_steps, fn rs ->
      %{
        id: rs.id,
        run_id: rs.run_id,
        step_id: rs.step_id,
        inserted_at: rs.inserted_at
      }
    end)
  end

  defp write_export_file(json_data, %{root_dir: root_dir}) do
    file_path = Path.join(root_dir, "export.json")

    case File.write(file_path, json_data) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
