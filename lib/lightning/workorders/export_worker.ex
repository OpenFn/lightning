defmodule Lightning.WorkOrders.ExportWorker do
  require Logger
  alias Lightning.Invocation.Dataclip
  alias Lightning.Repo
  alias Lightning.Invocation
  alias Lightning.Projects.Project
  alias Lightning.WorkOrders.SearchParams

  def export(%Project{} = project, %SearchParams{} = params) do
    workorders_query =
      Invocation.search_workorders_for_export_query(project, params)

    workorders_stream = Repo.stream(workorders_query, max_rows: 100)

    Repo.transaction(fn ->
      %{
        work_orders: work_orders,
        runs: runs,
        steps: steps,
        run_steps: run_steps,
        log_lines: log_lines,
        input_dataclips: input_dataclips,
        output_dataclips: output_dataclips
      } =
        workorders_stream
        |> Enum.map(fn work_order ->
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
        end)
        |> Enum.reduce(%{}, fn map, acc ->
          Map.merge(acc, map, fn _key, acc_val, map_val ->
            acc_val ++ map_val
          end)
        end)

      {:ok, dir_path} = Temp.mkdir("openfn")

      logs_dir = Path.join([dir_path, "logs"])
      data_clips_dir = Path.join([dir_path, "dataclips"])

      File.mkdir_p!(logs_dir)
      File.mkdir_p!(data_clips_dir)

      combine_and_write_logs(log_lines, logs_dir)
      write_data_clips(input_dataclips ++ output_dataclips, data_clips_dir)

      case format_for_export(%{
             work_orders: work_orders,
             runs: runs,
             steps: steps,
             run_steps: run_steps
           })
           |> Jason.encode(pretty: true) do
        {:ok, json_data} ->
          File.write(Path.join(dir_path, "export.json"), json_data)
          Logger.info("Content written in #{dir_path}")

        {:error, error} ->
          Logger.error(
            "Error while generating export json data. Error #{inspect(error)}"
          )
      end
    end)
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

  defp format_for_export(%{
         work_orders: work_orders,
         runs: runs,
         steps: steps,
         run_steps: run_steps
       }) do
    work_orders =
      work_orders
      |> Enum.map(fn wo ->
        %{
          id: wo.id,
          workflow_id: wo.workflow_id,
          workflow_name: wo.workflow.name,
          received_at: wo.inserted_at,
          last_activity: wo.updated_at,
          status: wo.state
        }
      end)

    runs =
      runs
      |> Enum.map(fn r ->
        %{
          id: r.id,
          work_order_id: r.work_order_id,
          finished_at: r.finished_at,
          status: r.state
        }
      end)

    steps =
      steps
      |> Enum.map(fn s ->
        %{
          id: s.id,
          status: s.exit_reason,
          inserted_at: s.inserted_at,
          input_dataclip: s.input_dataclip_id,
          output_dataclip: s.output_dataclip_id
        }
      end)

    run_steps =
      run_steps
      |> Enum.map(fn rs ->
        %{
          id: rs.id,
          run_id: rs.run_id,
          step_id: rs.step_id,
          inserted_at: rs.inserted_at
        }
      end)

    %{work_orders: work_orders, runs: runs, steps: steps, run_steps: run_steps}
  end

  defp combine_and_write_logs(log_lines, logs_dir) do
    log_lines
    |> Enum.group_by(& &1.run_id)
    |> Enum.each(fn {run_id, logs} ->
      combined_logs = Enum.map_join(logs, "\n", & &1.message)
      file_path = Path.join([logs_dir, "#{run_id}.txt"])
      File.write!(file_path, combined_logs)
    end)
  end

  defp write_data_clips(data_clips, data_clips_dir) do
    data_clips
    |> Enum.each(fn data_clip ->
      case serialize_data_clip(data_clip) do
        {:ok, data} ->
          file_path = Path.join([data_clips_dir, "#{data_clip.id}.json"])
          File.write!(file_path, data)

        {:error, error} ->
          Logger.error("Error when serializing data clip #{inspect(error)}")
      end
    end)
  end

  defp serialize_data_clip(%Dataclip{
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
end
