defmodule Lightning.WorkOrders.ExportWorker do
  require Logger
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
        log_lines: _log_lines,
        input_dataclips: _input_dataclips,
        output_dataclips: _output_dataclips
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
                :input_dataclip,
                :output_dataclip
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

      case format_for_export(%{
             work_orders: work_orders,
             runs: runs,
             steps: steps,
             run_steps: run_steps
           })
           |> Jason.encode(pretty: true) do
        {:ok, json_data} ->
          {:ok, dir_path} = Temp.mkdir("my-dir")
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
end
