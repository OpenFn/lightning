defmodule Lightning.WorkOrders.ExportWorker do
  @moduledoc """
    This module handles the export of work orders for a given project. The export process is performed asynchronously using the Oban background job system.

    ## Responsibilities

    - **Enqueueing Export Jobs**: The `enqueue_export/2` function creates and enqueues an Oban job for exporting work orders based on the given project and search parameters.
    - **Processing Exports**: The `perform/1` function is the main entry point for executing the export job. It retrieves the project, processes work orders, and handles the export process.
    - **Export Logic**: The export logic involves querying work orders, extracting relevant entities, processing logs and dataclips asynchronously, and writing the final export data to files.
    - **Error Handling**: The module includes comprehensive error handling and logging to ensure that issues during the export process are recorded and can be diagnosed.
    - **Zip File Creation**: After processing, the exported files are compressed into a zip file for easy download or further use.

    ## Usage

    - To enqueue an export job, call `enqueue_export/2` with the project and search parameters.
    - The export process is triggered by Oban and runs in the `history_exports` queue, limited to a single attempt per job.

    ## Example

    ```elixir
    # Enqueue an export job
    Lightning.WorkOrders.ExportWorker.enqueue_export(project, search_params)

    # The job will run in the background and log the status of the export process.
    ```

    This module is designed to handle potentially large datasets efficiently by using streaming, async processing, and error recovery mechanisms.
  """
  alias Lightning.Accounts.UserNotifier
  alias Lightning.Projects
  use Oban.Worker, queue: :history_exports, max_attempts: 1

  import Ecto.Query

  alias Lightning.Invocation
  alias Lightning.Invocation.Dataclip
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Storage.ProjectFileDefinition
  alias Lightning.WorkOrders.SearchParams

  require Logger

  @batch_size 50

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "project_id" => project_id,
          "project_file" => project_file_id,
          "search_params" => params
        }
      }) do
    search_params = SearchParams.from_map(params)

    result =
      with {:ok, project_file} <- get_project_file(project_file_id),
           {:ok, project_file} <-
             update_project_file(project_file, %{status: :in_progress}),
           {:ok, project} <- get_project(project_id),
           {:ok, zip_file} <-
             process_export(project, search_params, project_file),
           {:ok, storage_path} <- store_project_file(zip_file, project_file) do
        update_project_file(project_file, %{
          status: :completed,
          path: storage_path
        })
      end

    case result do
      {:ok, project_file} ->
        UserNotifier.notify_history_export_completion(
          project_file.created_by,
          project_file
        )

        Logger.info("Export completed successfully.")
        :ok

      {:error, reason} ->
        Logger.error("Export failed with reason: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def enqueue_export(project, project_file, search_params) do
    job = %{
      "project_id" => project.id,
      "project_file" => project_file.id,
      "search_params" => search_params
    }

    case Oban.insert(
           Lightning.Oban,
           Oban.Job.new(job, worker: __MODULE__, queue: :history_exports)
         ) do
      {:ok, _job} ->
        :ok

      {:error, changeset} ->
        Logger.error(
          "Failed to enqueue export job. Changeset errors: #{inspect(changeset.errors)}"
        )

        {:error, changeset}
    end
  end

  defp store_project_file(source_path, project_file) do
    storage_path =
      ProjectFileDefinition.storage_path_for_exports(project_file, ".zip")

    with {:ok, _} <-
           ProjectFileDefinition.store(source_path, %{
             project_file
             | path: storage_path
           }) do
      {:ok, storage_path}
    end
  end

  defp process_export(
         %Project{} = project,
         %SearchParams{} = params,
         %Projects.File{} = project_file
       ) do
    workorders_query =
      Invocation.search_workorders_for_export_query(project, params)

    case create_export_directories() do
      {:ok, export_dir} ->
        Repo.transaction(fn ->
          workorders_query
          |> Repo.stream(max_rows: 100)
          |> Stream.chunk_every(@batch_size)
          |> Stream.each(&process_and_write_batch(&1, export_dir))
          |> Stream.run()
        end)
        |> case do
          {:ok, _result} ->
            finalize_export(export_dir, project_file)

          {:error, reason} ->
            Logger.error(
              "Export transaction failed. Reason: #{inspect(reason)}. Rolled back transaction."
            )

            {:error, reason}
        end

      {:error, reason} ->
        Logger.error(
          "Failed to create export directories. Reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp process_and_write_batch(work_orders, export_dir) do
    export_result =
      work_orders
      |> Enum.map(&preload_and_extract_entities/1)
      |> Enum.reduce(%{}, &combine_entities/2)

    process_logs_and_dataclips_chunk(export_result, export_dir)
  end

  defp process_logs_and_dataclips_chunk(export_result, export_dir) do
    process_logs_async(export_result.log_lines, export_dir)

    export_result.dataclips
    |> fetch_dataclips()
    |> process_dataclips_async(export_dir)

    encode_and_write_export_chunk(export_result, export_dir)
  end

  defp encode_and_write_export_chunk(export_result, export_dir) do
    file_path = Path.join(export_dir.root_dir, "export.json")

    json_chunk =
      Jason.encode!(
        %{
          work_orders: export_result.work_orders,
          runs: export_result.runs,
          steps: export_result.steps,
          run_steps: export_result.run_steps
        },
        pretty: true
      )

    File.write!(file_path, json_chunk, [:append])
  end

  defp finalize_export(export_dir, project_file) do
    zip_file_name = Path.join(export_dir.root_dir, "#{project_file.id}.zip")

    case zip_folder(export_dir.root_dir, zip_file_name) do
      {:ok, zip_file} ->
        Logger.info(
          "Export content written and zipped successfully. Zip file location: #{zip_file}"
        )

        {:ok, zip_file}

      {:error, reason} ->
        Logger.error(
          "Failed to finalize export. Could not create zip file. Reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp zip_folder(folder_path, output_file) do
    case File.open(output_file, [:write, :binary], fn output ->
           entries = generate_entries(folder_path, "")

           entries
           |> Enum.reject(fn entry -> entry[:source] == {:file, output_file} end)
           |> Packmatic.build_stream()
           |> Enum.each(&IO.binwrite(output, &1))
         end) do
      {:ok, _} ->
        {:ok, output_file}

      {:error, error} ->
        {:error, error}
    end
  end

  defp generate_entries(directory_path, parent_path) do
    directory_path
    |> File.ls!()
    |> Enum.flat_map(fn entry ->
      full_path = Path.join([directory_path, entry])
      zip_entry_name = Path.join([parent_path, entry])

      if File.dir?(full_path) do
        generate_entries(full_path, zip_entry_name)
      else
        [
          [source: {:file, full_path}, path: zip_entry_name]
        ]
      end
    end)
  end

  defp get_project(project_id) do
    case Repo.get(Project, project_id) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project}
    end
  end

  defp get_project_file(project_file_id) do
    case Repo.get(Projects.File, project_file_id)
         |> Repo.preload([:created_by, :project]) do
      nil -> {:error, :project_file_not_found}
      project_file -> {:ok, project_file}
    end
  end

  defp update_project_file(project_file, attrs) do
    changeset = Ecto.Changeset.change(project_file, attrs)
    Repo.update(changeset)
  end

  defp preload_and_extract_entities(work_order) do
    work_order
    |> Repo.preload([
      :workflow,
      runs: [
        :run_steps,
        :log_lines,
        :steps
      ]
    ])
    |> extract_entities()
  end

  defp extract_entities(work_order) do
    runs = work_order.runs

    steps = Enum.flat_map(runs, & &1.steps)
    run_steps = Enum.flat_map(runs, & &1.run_steps)

    %{
      runs: format_runs(runs),
      steps: format_steps(steps),
      run_steps: format_run_steps(run_steps),
      work_orders: format_work_orders([work_order]),
      log_lines: extract_log_lines(runs),
      dataclips: extract_dataclips(steps)
    }
  end

  defp combine_entities(entity1, entity2) do
    # TODO: lets chat about this, i'm curious.. :)
    Map.merge(entity1, entity2, fn _key, val1, val2 -> val1 ++ val2 end)
  end

  defp create_export_directories do
    with {:ok, root_dir} <-
           Briefly.create(type: :directory),
         :ok <- File.mkdir_p(Path.join(root_dir, "logs")),
         :ok <- File.mkdir_p(Path.join(root_dir, "dataclips")) do
      {:ok,
       %{
         root_dir: root_dir,
         logs_dir: Path.join(root_dir, "logs"),
         dataclips_dir: Path.join(root_dir, "dataclips")
       }}
    end
  end

  defp process_logs_async(log_lines, %{logs_dir: logs_dir}) do
    log_lines
    |> Enum.group_by(& &1.run_id)
    |> Enum.chunk_every(@batch_size)
    |> Task.async_stream(&process_log_batch(&1, logs_dir))
    |> Enum.each(fn
      {:ok, :ok} ->
        :ok

      {:ok, error} ->
        Logger.error("Error in log processing: #{inspect(error)}")

      # TODO: does this imply we are skipping a log in the batch?
      {:exit, reason} ->
        Logger.error("Task exited with reason: #{inspect(reason)}")
    end)

    :ok
  end

  defp process_log_batch([{run_id, logs}], logs_dir) do
    combined_logs = Enum.map_join(logs, "\n", & &1.message)
    file_path = Path.join([logs_dir, "#{run_id}.txt"])

    case File.write(file_path, combined_logs) do
      :ok ->
        :ok

      error ->
        Logger.error(
          "Failed to write logs for run #{run_id}. Error details: #{inspect(error)}"
        )
    end
  end

  defp process_log_batch(log_batches, logs_dir) do
    Enum.each(log_batches, fn {run_id, logs} ->
      process_log_batch([{run_id, logs}], logs_dir)
    end)
  end

  defp process_dataclips_async(dataclips, %{dataclips_dir: dataclips_dir}) do
    dataclips
    |> Enum.chunk_every(@batch_size)
    |> Task.async_stream(&process_dataclip_batch(&1, dataclips_dir))
    |> Enum.each(fn
      {:ok, :ok} ->
        :ok

      {:ok, error} ->
        Logger.error(
          "Error in dataclip processing. Error details: #{inspect(error)}"
        )

      {:exit, reason} ->
        Logger.error(
          "Dataclip processing task exited prematurely. Exit reason: #{inspect(reason)}"
        )
    end)

    :ok
  end

  defp process_dataclip_batch(dataclips, dataclips_dir) do
    Enum.each(dataclips, fn %{id: dataclip_id, body: dataclip_body} ->
      file_path = Path.join([dataclips_dir, "#{dataclip_id}.json"])

      case File.write(file_path, dataclip_body) do
        :ok ->
          :ok

        error ->
          Logger.error(
            "Failed to write dataclip #{dataclip_id}: #{inspect(error)}"
          )
      end
    end)
  end

  # TODO: there are now 3 functions that are almost identical, need to refactor
  def fetch_dataclips(dataclip_ids) do
    from(d in Dataclip,
      where: d.id in ^dataclip_ids,
      select: %{
        id: d.id,
        body:
          type(
            fragment(
              """
              CASE WHEN type IN ('http_request', 'kafka')
              THEN jsonb_build_object('data', ?, 'request', ?)
              ELSE ? END
              """,
              d.body,
              d.request,
              d.body
            ),
            :string
          )
      }
    )
    |> Repo.all()
  end

  defp format_work_orders(work_orders) do
    Enum.map(work_orders, fn wo ->
      %{
        id: wo.id,
        workflow_id: wo.workflow_id,
        workflow_name: wo.workflow.name,
        # TODO: should probably not rename the keys for now.
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
        # TODO: need to add `claimed_at`, `started_at`, `finished_at`
        # TODO: should be add `options`?
        finished_at: r.finished_at,
        status: r.state
      }
    end)
  end

  defp format_steps(steps) do
    Enum.map(steps, fn s ->
      %{
        id: s.id,
        # TODO: need to verify we want to rename this to `status`
        # TODO: add `error_type`, `started_at`, `finished_at`, `job_id`, `credential_id`, `snapshot_id`
        status: s.exit_reason,
        inserted_at: s.inserted_at,
        # TODO: perhaps we just keep the keys the same, (i.e. `input_dataclip_id`, `output_dataclip_id`)
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

  defp extract_dataclips(steps) do
    Enum.reduce(steps, MapSet.new(), fn step, acc ->
      acc
      |> MapSet.put(step.input_dataclip_id)
      |> MapSet.put(step.output_dataclip_id)
    end)
    |> MapSet.to_list()
  end

  defp extract_log_lines(runs) do
    runs
    |> Enum.flat_map(& &1.log_lines)
    |> Enum.map(fn log_line ->
      %{id: log_line.id, message: log_line.message, run_id: log_line.run_id}
    end)
  end
end
