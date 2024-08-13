defmodule Lightning.WorkOrders.ExportWorker do
  alias Lightning.Repo
  alias Lightning.Invocation
  alias Lightning.Projects.Project
  alias Lightning.WorkOrders.SearchParams

  def start_export(%Project{} = project, %SearchParams{} = params) do
    workorders_query =
      Invocation.search_workorders_for_export_query(project, params)

    workorders_stream = Repo.stream(workorders_query, max_rows: 100)

    # {:ok, {runs, steps, log_lines, input_dataclips, output_dataclips}} =
    Repo.transaction(fn ->
      workorders_stream
      |> Enum.map(fn work_order ->
        work_order
        |> Repo.preload(
          runs: [
            :log_lines,
            steps: [
              :input_dataclip,
              :output_dataclip
            ]
          ]
        )
        |> extract_entities()
      end)
      |> IO.inspect()
      |> List.foldl({[], [], [], [], []}, fn {r, s, l, i, o}, acc ->
        Enum.reduce([r, s, l, i, o], acc, fn _a, _b ->
          nil
          # IO.inspect(a, label: "THIS IS A")
          # IO.inspect(b, label: "THIS IS B")
        end)
      end)
    end)

    # {runs, steps, log_lines, input_dataclips, output_dataclips}
    :ok
  end

  defp extract_entities(work_order) do
    runs = work_order.runs
    steps = Enum.flat_map(runs, & &1.steps)
    log_lines = Enum.flat_map(runs, & &1.log_lines)
    input_dataclips = Enum.map(steps, & &1.input_dataclip)
    output_dataclips = Enum.map(steps, & &1.output_dataclip)

    %{
      runs: runs,
      steps: steps,
      log_lines: log_lines,
      input_dataclips: input_dataclips,
      output_dataclips: output_dataclips
    }
  end

  # defp merge_entities({r, s, l, i, o}, {acc_r, acc_s, acc_l, acc_i, acc_o}) do
  #   {
  #     acc_r ++ r,
  #     acc_s ++ s,
  #     acc_l ++ l,
  #     acc_i ++ i,
  #     acc_o ++ o
  #   }
  # end
end
