defmodule Lightning.PerformanceAnalysis do
  @moduledoc """
  THis module can be used to load a large number of Runs into the database for
  the purposes of evaluating query performance. The module also provides a
  a convenience method to dump query SQL to files for the purposes of comparison
  as well as determining query execution plans.

  This module uses Lightning.Factories to generate the data so it must be run
  in the `test` environment. In addition it requires the
  `PERFORMANCE_TEST` ENV variable to be set to ensure that the process does not
  run afoul of `ownership_timeout` restrictions.

  Usage:

  ```
  MIX_ENV=test PERFORMANCE_TEST=yes iex -S mix run test/support/performance_analysis.exs
  ```
  """
  import Lightning.Factories

  alias Lightning.Repo

  @doc """
  Populate a fixed number of runs into the DB. The runs include a mix of
  states, with the current ratio of 'final' to 'inprogress' being 4:1. One
  percent of the inprogress runs are priority '0'.

  Usage:

  ```
  iex(1)> Lightning.PerformanceAnalysis.populate()
  :ok
  ```
  """
  def populate do
    no_of_projects = 10
    no_of_processing_runs_per_project = 1000
    no_of_finalised_runs_per_project = 4 * no_of_processing_runs_per_project

    insert_list(no_of_projects, :project)
    |> Enum.each(fn project ->
      workflow = insert(:simple_workflow, project: project)

      1..no_of_finalised_runs_per_project
      |> Enum.each(fn counter ->
        insert_finalised_record_set(workflow, project, counter)
      end)

      1..no_of_processing_runs_per_project
      |> Enum.each(fn counter ->
        insert_processing_record_set(
          workflow,
          project,
          counter + no_of_finalised_runs_per_project
        )
      end)
    end)
  end

  @doc """
  This will generate two sql files that can be used to debug and measure
  query changes (in addition to the unit tests).

  The first file contains just
  the resulting SQL and can be used to output the results into a text file
  for before/after comparisons.

  The second file prepends the SQL with the necessary EXPLAIN directive that
  can be used to generate an execution plan suitable for uploading to
  https://explain.dalibo.com/.

  The names of the files are based on the `output_name` parameter. If the
  `output_name` is set to `blah` then the generated files will be named
  `blah.sql` and `explain_blah.sql`.

  Usage:

  ```
  alias Lightning.Runs.Query
  Query.eligible_for_claim() |> Lightning.PerformanceAnalysis.dump_to_sql("blah")
  ```

  """
  def dump_to_sql(query, output_name, db_name \\ "lightning_test") do
    {raw_query, _} = Repo.to_sql(:all, query)

    file_name = "#{output_name}.sql"
    explain_file_name = "explain_#{output_name}.sql"
    results_file_name = "explain_#{output_name}_results.json"
    eol = end_of_line()

    File.write!(file_name, "#{raw_query}#{eol}")

    explain_query =
      "EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON) #{raw_query}"

    comment =
      "/* psql -XqAt -f #{explain_file_name} #{db_name} > #{results_file_name} */"

    File.write!(
      explain_file_name,
      "#{comment}#{eol}#{explain_query}#{eol}"
    )
  end

  defp get_finalised_state do
    # Based on stats on prod - approx 87% success, 10% failed, and the balance
    # of states covered in the remaining 3%. Jimmied these numbers a bit so that
    # I can represent all states within a rangeof 1 to 100.
    1..100
    |> Enum.take_random(1)
    |> case do
      [100] -> :killed
      [99] -> :exception
      [98] -> :lost
      [num] when num >= 96 -> :crashed
      [num] when num >= 87 -> :failed
      _ -> :success
    end
  end

  defp get_processing_state do
    1..100
    |> Enum.take_random(1)
    |> case do
      [num] when num >= 96 -> :started
      [num] when num >= 91 -> :claimed
      _ -> :available
    end
  end

  defp set_priority do
    1..100
    |> Enum.take_random(1)
    |> case do
      [1] -> 0
      _ -> 1
    end
  end

  defp insert_finalised_record_set(workflow, project, counter) do
    priority = 1

    workflow
    |> setup_dataclip_workorder_run(
      project,
      get_finalised_state(),
      priority,
      counter
    )
  end

  defp insert_processing_record_set(workflow, project, counter) do
    workflow
    |> setup_dataclip_workorder_run(
      project,
      get_processing_state(),
      set_priority(),
      counter
    )
  end

  defp setup_dataclip_workorder_run(
         workflow,
         project,
         state,
         priority,
         counter
       ) do
    %{triggers: [trigger]} = workflow

    dataclip = insert(:dataclip, project: project)

    snapshot = insert(:snapshot, workflow: workflow, lock_version: counter)

    wo =
      insert(:workorder,
        workflow: workflow,
        snapshot: snapshot,
        trigger: trigger,
        dataclip: dataclip
      )

    insert(:run,
      work_order: wo,
      dataclip: dataclip,
      starting_trigger: trigger,
      state: state,
      priority: priority,
      snapshot: snapshot
    )
  end

  defp end_of_line do
    case :os.type() do
      {:win32, _} -> "\r\n"
      _ -> "\n"
    end
  end
end
