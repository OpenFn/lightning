defmodule Lightning.WorkOrders.ExportWorker do
  @moduledoc """
    This module handles the export of work orders for a given project. The export process is performed asynchronously using the Oban background job system.

    ## Responsibilities

    - **Enqueueing Export Jobs**: The `enqueue_export/2` function creates and enqueues an Oban job for exporting work orders based on the given project and search parameters.
    - **Processing Exports**: The `perform/1` function is the main entry point for executing the export job. It retrieves the project, processes work orders, and handles the export process.
    - **Export Logic**: The export lists the matching work order ids up front, then walks them a page at a time. Each page batch-loads its runs, steps, log lines and dataclips, writes the logs and dataclips asynchronously, and appends its slice of the export data. Nothing spans a transaction: the whole point of paging is that no database connection is held while files are being written.
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
  use Oban.Worker, queue: :history_exports, max_attempts: 1

  import Ecto.Query

  alias Lightning.Accounts.UserNotifier
  alias Lightning.Config
  alias Lightning.DataclipScrubber
  alias Lightning.Invocation
  alias Lightning.Invocation.LogLine
  alias Lightning.Invocation.Step
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.RunStep
  alias Lightning.Storage.ProjectFileDefinition
  alias Lightning.WorkOrder
  alias Lightning.WorkOrders.SearchParams

  require Logger

  @batch_size 50

  # Order is the order the sections appear in export.json.
  @export_sections [:work_orders, :runs, :steps, :run_steps]

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "project_id" => project_id,
          "project_file" => project_file_id,
          "search_params" => params
        }
      }) do
    with {:ok, search_params} <- SearchParams.from_map(params),
         {:ok, project_file} <- get_project_file(project_file_id),
         {:ok, project_file} <-
           update_project_file(project_file, %{status: :in_progress}),
         {:ok, project} <- get_project(project_id),
         {:ok, zip_file} <-
           process_export(project, search_params, project_file),
         {:ok, storage_path} <-
           store_project_file(zip_file, project_file),
         {:ok, project_file} <-
           update_project_file(project_file, %{
             status: :completed,
             path: storage_path
           }) do
      UserNotifier.notify_history_export_completion(
        project,
        project_file.created_by,
        project_file
      )

      Logger.info("Export completed successfully.")
      :ok
    else
      {:error, reason} ->
        mark_project_file_failed(project_file_id)

        Logger.error("Export failed with reason: #{inspect(reason)}")

        {:error, reason}
    end
  end

  def enqueue_export(project, project_file, search_params) do
    job =
      new(%{
        "project_id" => project.id,
        "project_file" => project_file.id,
        "search_params" => search_params
      })

    case Oban.insert(Lightning.Oban, job) do
      {:ok, job} ->
        {:ok, job}

      {:error, changeset} ->
        Logger.error(
          "Failed to enqueue export job. Changeset errors: #{inspect(changeset.errors)}"
        )

        mark_project_file_failed(project_file.id)

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
    case create_export_directories() do
      {:ok, export_dir} ->
        walk_export(project, params, export_dir, project_file)

      {:error, reason} ->
        Logger.error(
          "Failed to create export directories. Reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  # `max_attempts: 1`, so an exception here would crash the job before
  # `perform/1` could mark the project file failed, leaving it `:in_progress`
  # with nothing able to recover it.
  defp walk_export(project, params, export_dir, project_file) do
    project
    |> list_workorder_ids(params)
    |> Stream.chunk_every(@batch_size)
    |> Stream.each(&process_and_write_batch(&1, export_dir))
    |> Stream.run()

    finalize_export(export_dir, project_file)
  rescue
    exception ->
      Logger.error(Exception.format(:error, exception, __STACKTRACE__))
      {:error, exception}
  catch
    :exit, reason ->
      Logger.error("Export exited with reason: #{inspect(reason)}")
      {:error, reason}
  end

  # An ordered snapshot taken up front rather than a cursor held open for the
  # length of the export. Large histories make this one query expensive enough
  # to need more than the default timeout.
  defp list_workorder_ids(project, params) do
    project
    |> Invocation.search_workorders_for_export_query(params)
    |> exclude(:select)
    # `SELECT DISTINCT` requires every `ORDER BY` expression in the select list,
    # so the sort columns have to come back with the ids and get dropped here.
    |> select([workorder: workorder], %{
      id: workorder.id,
      inserted_at: workorder.inserted_at,
      last_activity: workorder.last_activity
    })
    |> Repo.all(timeout: Config.default_ecto_database_timeout() * 3)
    |> Enum.map(& &1.id)
  end

  defp process_and_write_batch(work_order_ids, export_dir) do
    work_order_ids
    |> load_page()
    |> process_logs_and_dataclips_chunk(export_dir)
  end

  # A page costs a fixed handful of queries regardless of how many work orders
  # it holds; the per-work-order preloads this replaced cost ~5 each.
  defp load_page(work_order_ids) do
    work_orders = fetch_work_orders(work_order_ids)
    runs = fetch_runs(work_order_ids)
    run_ids = Enum.map(runs, & &1.id)

    steps_by_run = fetch_steps_by_run(run_ids)
    run_steps_by_run = group_by_run(fetch_run_steps(run_ids))
    log_lines_by_run = group_by_run(fetch_log_lines(run_ids))

    # Flat-mapping over the runs keeps entities grouped by run, and exports a
    # step shared by two runs once per run.
    steps = flat_map_by_run(runs, steps_by_run)

    %{
      work_orders: format_work_orders(work_orders),
      runs: format_runs(runs),
      steps: format_steps(steps),
      run_steps: format_run_steps(flat_map_by_run(runs, run_steps_by_run)),
      log_lines: extract_log_lines(flat_map_by_run(runs, log_lines_by_run)),
      dataclips: extract_dataclips(steps)
    }
  end

  defp fetch_work_orders(work_order_ids) do
    work_orders =
      from(wo in WorkOrder,
        where: wo.id in ^work_order_ids,
        preload: [:workflow]
      )
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    # `where ... in` gives no ordering, so the page is put back into search
    # order. A work order deleted since the ids were listed drops out.
    Enum.flat_map(work_order_ids, fn id ->
      case Map.fetch(work_orders, id) do
        {:ok, work_order} -> [work_order]
        :error -> []
      end
    end)
  end

  defp fetch_runs(work_order_ids) do
    from(r in Run,
      where: r.work_order_id in ^work_order_ids,
      order_by: [asc: r.inserted_at, asc: r.id]
    )
    |> Repo.all()
  end

  defp fetch_run_steps(run_ids) do
    from(rs in RunStep,
      where: rs.run_id in ^run_ids,
      order_by: [asc: rs.inserted_at]
    )
    |> Repo.all()
  end

  # Joined through `run_steps` rather than fetched by id: a step can belong to
  # more than one run, and each of those runs exports it.
  defp fetch_steps_by_run(run_ids) do
    from(s in Step,
      join: rs in RunStep,
      on: rs.step_id == s.id,
      where: rs.run_id in ^run_ids,
      order_by: [asc: s.started_at],
      select: {rs.run_id, s}
    )
    |> Repo.all()
    |> Enum.group_by(
      fn {run_id, _step} -> run_id end,
      fn {_run_id, step} -> step end
    )
  end

  # `log_lines` has no `inserted_at` and batched worker timestamps routinely
  # tie, so `id` breaks ties - arbitrary, but stable across exports.
  defp fetch_log_lines(run_ids) do
    from(l in LogLine,
      where: l.run_id in ^run_ids,
      order_by: [asc: l.timestamp, asc: l.id]
    )
    |> Repo.all()
  end

  defp group_by_run(entities), do: Enum.group_by(entities, & &1.run_id)

  defp flat_map_by_run(runs, grouped) do
    Enum.flat_map(runs, &Map.get(grouped, &1.id, []))
  end

  defp process_logs_and_dataclips_chunk(export_result, export_dir) do
    process_logs_async(export_result.log_lines, export_dir)

    export_result.dataclips
    |> fetch_dataclips()
    |> process_dataclips_async(export_dir)

    encode_and_write_export_chunk(export_result, export_dir)
  end

  # One compact JSON value per line per section; `assemble_export_json/1`
  # stitches those into a single `export.json` at the end. Appending a whole
  # object per page instead leaves anything past the first page unparseable.
  defp encode_and_write_export_chunk(export_result, export_dir) do
    Enum.each(@export_sections, fn section ->
      case Map.fetch!(export_result, section) do
        [] ->
          :ok

        entities ->
          lines = Enum.map(entities, &[Jason.encode_to_iodata!(&1), "\n"])
          File.write!(section_path(export_dir, section), lines, [:append])
      end
    end)
  end

  defp section_path(export_dir, section) do
    Path.join(export_dir.sections_dir, "#{section}.jsonl")
  end

  defp assemble_export_json(export_dir) do
    path = Path.join(export_dir.root_dir, "export.json")
    file = File.open!(path, [:write, :binary, {:delayed_write, 512_000, 2_000}])

    try do
      IO.binwrite(file, "{\n")

      @export_sections
      |> Enum.with_index()
      |> Enum.each(fn {section, index} ->
        write_section(file, export_dir, section, index)
      end)

      IO.binwrite(file, "\n}\n")
    after
      # `:delayed_write` clears a failed write after reporting it, so the last
      # block's failure only surfaces on close, when the buffer is flushed.
      # Ignoring it would zip a truncated `export.json` and mark it `:completed`.
      :ok = File.close(file)
    end
  end

  defp write_section(file, export_dir, section, index) do
    separator = if index == 0, do: "", else: ",\n"
    IO.binwrite(file, [separator, ~s(  "#{section}": [)])

    section_path = section_path(export_dir, section)

    if File.exists?(section_path) do
      section_path
      |> File.stream!()
      |> Stream.map(&String.trim_trailing(&1, "\n"))
      |> Stream.intersperse(",\n")
      |> Enum.each(&IO.binwrite(file, &1))
    end

    IO.binwrite(file, "]")
  end

  defp finalize_export(export_dir, project_file) do
    :ok = assemble_export_json(export_dir)
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
    generate_entries(folder_path, "")
    |> Enum.reject(fn entry -> entry[:source] == {:file, output_file} end)
    |> Packmatic.build_stream()
    |> Stream.into(File.stream!(output_file, []))
    |> Stream.run()

    {:ok, output_file}
  catch
    error ->
      {:error, error}
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

  defp create_export_directories do
    with {:ok, root_dir} <-
           Briefly.create(type: :directory),
         # Deliberately outside root_dir: everything under root_dir ends up in
         # the zip, and these are scratch files.
         {:ok, sections_dir} <- Briefly.create(type: :directory),
         :ok <- File.mkdir_p(Path.join(root_dir, "logs")),
         :ok <- File.mkdir_p(Path.join(root_dir, "dataclips")) do
      {:ok,
       %{
         root_dir: root_dir,
         sections_dir: sections_dir,
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

  defp fetch_dataclips(dataclip_ids) do
    Invocation.Query.dataclip_with_body()
    |> where([d], d.id in ^dataclip_ids)
    |> Repo.all()
    |> then(fn dataclips ->
      scrubbed = DataclipScrubber.scrub_dataclip_bodies!(dataclips)

      Enum.map(dataclips, fn dataclip ->
        %{id: dataclip.id, body: Map.fetch!(scrubbed, dataclip.id)}
      end)
    end)
  end

  defp format_work_orders(work_orders) do
    Enum.map(work_orders, fn wo ->
      Map.take(wo, [
        :id,
        :dataclip_id,
        :inserted_at,
        :last_activity,
        :snapshot_id,
        :state,
        :trigger_id,
        :updated_at,
        :workflow_id
      ])
      |> Map.merge(%{
        workflow_name: wo.workflow.name
      })
    end)
  end

  defp format_runs(runs) do
    Enum.map(runs, fn r ->
      Map.take(r, [
        :claimed_at,
        :created_by_id,
        :dataclip_id,
        :error_type,
        :finished_at,
        :id,
        :inserted_at,
        :options,
        :snapshot_id,
        :started_at,
        :starting_job_id,
        :starting_trigger_id,
        :state,
        :work_order_id
      ])
    end)
  end

  defp format_steps(steps) do
    Enum.map(steps, fn s ->
      Map.take(s, [
        :id,
        :credential_id,
        :error_type,
        :exit_reason,
        :finished_at,
        :inserted_at,
        :job_id,
        :snapshot_it,
        :started_at
      ])
      |> Map.merge(%{
        input_dataclip: s.input_dataclip_id,
        output_dataclip: s.output_dataclip_id
      })
    end)
  end

  defp format_run_steps(run_steps) do
    Enum.map(run_steps, fn rs ->
      Map.take(rs, [:id, :run_id, :step_id, :inserted_at])
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

  defp extract_log_lines(log_lines) do
    Enum.map(log_lines, fn log_line ->
      %{id: log_line.id, message: log_line.message, run_id: log_line.run_id}
    end)
  end

  defp mark_project_file_failed(project_file_id) do
    case Repo.get(Projects.File, project_file_id) do
      nil ->
        :ok

      project_file ->
        project_file
        |> Projects.File.mark_failed()
        |> Repo.update()
        |> case do
          {:ok, _project_file} ->
            :ok

          {:error, changeset} ->
            Logger.error(
              "Failed to mark project file #{project_file_id} as failed: #{inspect(changeset.errors)}"
            )

            {:error, changeset}
        end
    end
  end
end
