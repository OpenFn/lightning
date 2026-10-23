defmodule LightningWeb.ApiReadHelpers do
  @moduledoc """
  Builders for the API tests of the routes that list and show runs, work
  orders, log lines and jobs.
  """
  import Lightning.Factories

  alias Lightning.Projects.Project

  @doc """
  Inserts a work order in `target`, a workflow or a project (which gets a new
  workflow). `attrs` go to the work order.
  """
  def insert_work_order(target, attrs \\ []) do
    workflow = workflow_for(target)

    trigger =
      Keyword.get_lazy(attrs, :trigger, fn ->
        insert(:trigger, workflow: workflow)
      end)

    insert(
      :workorder,
      Keyword.merge(
        [workflow: workflow, trigger: trigger, dataclip: build(:dataclip)],
        attrs
      )
    )
  end

  @doc """
  Inserts a work order holding one run, in `target`, and returns the run.
  `run_attrs` go to the run, `work_order_attrs` to the work order, which takes
  the run's `inserted_at` unless it is given its own.
  """
  def insert_run(target, run_attrs \\ [], work_order_attrs \\ []) do
    workflow = workflow_for(target)
    trigger = insert(:trigger, workflow: workflow)

    run =
      Map.merge(
        %{
          state: :started,
          dataclip: build(:dataclip),
          starting_trigger: trigger
        },
        Map.new(run_attrs)
      )

    inserted =
      for {:inserted_at, at} <- Map.to_list(run), do: {:inserted_at, at}

    %{runs: [run]} =
      insert_work_order(
        workflow,
        Keyword.merge(
          [trigger: trigger, runs: [run]] ++ inserted,
          work_order_attrs
        )
      )

    run
  end

  defp workflow_for(%Project{} = project),
    do: insert(:workflow, project: project)

  defp workflow_for(workflow), do: workflow
end
