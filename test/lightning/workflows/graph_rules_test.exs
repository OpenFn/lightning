defmodule Lightning.Workflows.GraphRulesTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows
  alias Lightning.Workflows.GraphRules
  alias Lightning.Workflows.Workflow

  setup do
    %{project: insert(:project)}
  end

  defp new_workflow(project, params) do
    Workflow.changeset(
      %Workflow{},
      Map.merge(%{"name" => "graph rules", "project_id" => project.id}, params)
    )
  end

  defp change_stored(workflow, params) do
    workflow
    |> Repo.preload([:jobs, :triggers, :edges], force: true)
    |> Workflows.change_workflow(params)
  end

  # The errors on the workflow itself, which are the ones on a list as a whole.
  defp list_errors(changeset),
    do: changeset |> GraphRules.validate() |> Map.fetch!(:errors) |> Enum.sort()

  # The errors on each of `relation`'s children, each with the params of the
  # request item it came from, so a rule is held to the item at fault whatever
  # order Ecto keeps its list in.
  defp item_errors(changeset, relation) do
    for child <- Map.get(GraphRules.validate(changeset).changes, relation, []),
        child.errors != [],
        do: {child.params, Enum.sort(child.errors)}
  end

  defp cycle, do: [target_job_id: {"is part of a cycle", [code: :cycle]}]

  defp no_trigger_edge,
    do:
      {:edges,
       {"needs an enabled edge from a trigger", [code: :missing_trigger_edge]}}

  defp job(id), do: %{"id" => id, "name" => "job #{id}", "body" => "fn(s => s)"}

  defp trigger(id, enabled \\ true),
    do: %{"id" => id, "type" => "webhook", "enabled" => enabled}

  defp edge({:trigger, from}, to),
    do: %{
      "source_trigger_id" => from,
      "target_job_id" => to,
      "condition_type" => "always"
    }

  defp edge(from, to),
    do: %{
      "source_job_id" => from,
      "target_job_id" => to,
      "condition_type" => "on_job_success"
    }

  defp ids(count), do: for(_ <- 1..count, do: Ecto.UUID.generate())

  test "a workflow that keeps every rule passes", %{project: project} do
    [t, a, b] = ids(3)

    changeset =
      new_workflow(project, %{
        "triggers" => [trigger(t)],
        "jobs" => [job(a), job(b)],
        "edges" => [edge({:trigger, t}, a), edge(a, b)]
      })

    assert GraphRules.validate(changeset).valid?
  end

  describe "cycles" do
    test "a cycle through several edges is reported at the edge that closes it",
         %{project: project} do
      [t, a, b, c] = ids(4)

      changeset =
        new_workflow(project, %{
          "triggers" => [trigger(t)],
          "jobs" => [job(a), job(b), job(c)],
          "edges" => [
            edge({:trigger, t}, a),
            edge(a, b),
            edge(b, c),
            edge(c, a)
          ]
        })

      assert item_errors(changeset, :edges) == [{edge(c, a), cycle()}]
      assert list_errors(changeset) == []
      refute GraphRules.validate(changeset).valid?
    end

    test "the edge's position is the request's, not the stored list's" do
      workflow = insert(:simple_workflow)
      [trigger] = workflow.triggers
      [stored_job] = workflow.jobs
      [k] = ids(1)

      # The stored edge is left out, so Ecto puts its removal ahead of the
      # request's edges in the changeset.
      changeset =
        change_stored(workflow, %{
          "jobs" => [job(stored_job.id), job(k)],
          "edges" => [
            edge({:trigger, trigger.id}, k),
            edge(k, stored_job.id),
            edge(stored_job.id, k)
          ]
        })

      assert item_errors(changeset, :edges) == [
               {edge(stored_job.id, k), cycle()}
             ]

      assert list_errors(changeset) == []
    end

    test "two separate cycles are each reported", %{project: project} do
      [t, a, b, c, d] = ids(5)

      changeset =
        new_workflow(project, %{
          "triggers" => [trigger(t)],
          "jobs" => [job(a), job(b), job(c), job(d)],
          "edges" => [
            edge({:trigger, t}, a),
            edge(a, b),
            edge(b, a),
            edge(c, d),
            edge(d, c)
          ]
        })

      assert item_errors(changeset, :edges) == [
               {edge(b, a), cycle()},
               {edge(d, c), cycle()}
             ]
    end

    test "an edge from a job to itself is reported once, by the edge",
         %{project: project} do
      [t, a] = ids(2)

      changeset =
        new_workflow(project, %{
          "triggers" => [trigger(t)],
          "jobs" => [job(a)],
          "edges" => [edge({:trigger, t}, a), edge(a, a)]
        })

      assert item_errors(changeset, :edges) == [
               {edge(a, a),
                [
                  target_job_id:
                    {"target_job_id must be different from source_job_id",
                     [code: :cycle]}
                ]}
             ]

      assert list_errors(changeset) == []
    end

    test "a stored cycle the request leaves alone is reported at the list" do
      workflow = insert(:simple_workflow)
      [trigger] = workflow.triggers
      [a] = workflow.jobs
      b = insert(:job, workflow: workflow)
      insert(:edge, workflow: workflow, source_job_id: a.id, target_job_id: b.id)
      insert(:edge, workflow: workflow, source_job_id: b.id, target_job_id: a.id)

      assert trigger.enabled

      changeset = change_stored(workflow, %{"name" => "renamed"})

      assert list_errors(changeset) == [
               edges: {"is part of a cycle", [code: :cycle]}
             ]

      assert item_errors(changeset, :edges) == []
    end
  end

  describe "edges from triggers" do
    test "a workflow with no edge from a trigger", %{project: project} do
      [t, a, b] = ids(3)

      changeset =
        new_workflow(project, %{
          "triggers" => [trigger(t)],
          "jobs" => [job(a), job(b)],
          "edges" => [edge(a, b)]
        })

      assert list_errors(changeset) == [no_trigger_edge()]
    end

    test "a workflow with no jobs, triggers or edges", %{project: project} do
      assert list_errors(new_workflow(project, %{})) == [no_trigger_edge()]
    end

    test "edges from two triggers, both enabled", %{project: project} do
      [t1, t2, a, b] = ids(4)

      changeset =
        new_workflow(project, %{
          "triggers" => [trigger(t1), trigger(t2, false)],
          "jobs" => [job(a), job(b)],
          "edges" => [edge({:trigger, t1}, a), edge({:trigger, t2}, b)]
        })

      assert list_errors(changeset) == [
               {:edges,
                {"only one edge from a trigger may be enabled",
                 [code: :one_enabled_edge]}}
             ]
    end

    test "a trigger with two targets", %{project: project} do
      [t, a, b] = ids(3)

      changeset =
        new_workflow(project, %{
          "triggers" => [trigger(t)],
          "jobs" => [job(a), job(b)],
          "edges" => [edge({:trigger, t}, a), edge({:trigger, t}, b)]
        })

      assert list_errors(changeset) == [
               {:edges,
                {"a trigger must have a single target", [code: :single_target]}},
               {:edges,
                {"only one edge from a trigger may be enabled",
                 [code: :one_enabled_edge]}}
             ]
    end

    test "an edge naming a trigger as its source job counts as the trigger's",
         %{project: project} do
      [t, a, b] = ids(3)

      changeset =
        new_workflow(project, %{
          "triggers" => [trigger(t)],
          "jobs" => [job(a), job(b)],
          "edges" => [edge({:trigger, t}, a), edge(t, b)]
        })

      assert list_errors(changeset) == [
               {:edges,
                {"a trigger must have a single target", [code: :single_target]}}
             ]
    end
  end

  describe "triggers" do
    test "two enabled triggers", %{project: project} do
      [t1, t2, a] = ids(3)

      changeset =
        new_workflow(project, %{
          "triggers" => [trigger(t1), trigger(t2)],
          "jobs" => [job(a)],
          "edges" => [edge({:trigger, t1}, a)]
        })

      assert list_errors(changeset) == [
               triggers:
                 {"only one trigger may be enabled", [code: :one_enabled]}
             ]
    end

    test "a request that leaves a stored trigger out" do
      workflow = insert(:simple_workflow)
      [stored_job] = workflow.jobs
      [t] = ids(1)

      changeset =
        change_stored(workflow, %{
          "triggers" => [trigger(t, false)],
          "edges" => [edge({:trigger, t}, stored_job.id)]
        })

      assert list_errors(changeset) == [
               triggers:
                 {"a trigger cannot be removed, only edited or added",
                  [code: :trigger_removed]}
             ]
    end

    # The rule is checked only on the triggers a request sends, so a workflow
    # the editor saved with two enabled triggers can still be renamed.
    test "a request that leaves the triggers alone isn't checked for them" do
      workflow = insert(:simple_workflow)
      insert(:trigger, workflow: workflow, enabled: true)

      changeset = change_stored(workflow, %{"name" => "renamed"})

      assert list_errors(changeset) == []
      assert item_errors(changeset, :triggers) == []
    end
  end

  test "a job sent without its id", %{project: project} do
    [t, a] = ids(2)

    changeset =
      new_workflow(project, %{
        "triggers" => [trigger(t)],
        "jobs" => [job(a), %{"name" => "no id", "body" => "fn(s => s)"}],
        "edges" => [edge({:trigger, t}, a)]
      })

    assert item_errors(changeset, :jobs) == [
             {%{"name" => "no id", "body" => "fn(s => s)"},
              [id: {"can't be blank", [validation: :required]}]}
           ]
  end

  test "a trigger sent without its id", %{project: project} do
    [a] = ids(1)

    changeset =
      new_workflow(project, %{
        "triggers" => [%{"type" => "webhook", "enabled" => true}],
        "jobs" => [job(a)],
        "edges" => []
      })

    assert list_errors(changeset) == [no_trigger_edge()]

    assert item_errors(changeset, :triggers) == [
             {%{"type" => "webhook", "enabled" => true},
              [id: {"can't be blank", [validation: :required]}]}
           ]
  end
end
