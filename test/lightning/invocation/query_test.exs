defmodule Lightning.Invocation.QueryTest do
  use Lightning.DataCase, async: true

  alias Lightning.Invocation.Query
  alias Lightning.Workflows
  alias Lightning.Workflows.Trigger

  import Lightning.Factories

  test "steps_for/1 with user" do
    user = insert(:user)
    project = insert(:project, project_users: [%{user_id: user.id}])

    %{triggers: [trigger], jobs: [job]} =
      workflow = insert(:simple_workflow, project: project)

    %{runs: [%{steps: [step1]}]} =
      insert(:workorder,
        workflow: workflow,
        dataclip: build(:dataclip, project: project),
        trigger: trigger,
        runs: [
          build(:run,
            starting_trigger: trigger,
            dataclip: build(:dataclip, project: project),
            steps: [build(:step, job: job)]
          )
        ]
      )

    %{triggers: [trigger2], jobs: [job2]} = workflow2 = insert(:simple_workflow)

    %{runs: [%{steps: [step2]}]} =
      insert(:workorder,
        workflow: workflow2,
        dataclip: build(:dataclip),
        trigger: trigger2,
        runs: [
          build(:run,
            dataclip: build(:dataclip),
            starting_trigger: trigger2,
            steps: [build(:step, job: job2)]
          )
        ]
      )

    refute step1.id == step2.id

    step1_id = step1.id

    assert [%{id: ^step1_id}] = Query.steps_for(user) |> Repo.all()
  end

  test "any_step/0 returns only 1 result when used in a preload for a job" do
    %{jobs: [job1]} = workflow = insert(:simple_workflow)

    insert(:step, job: job1)
    insert(:step, job: job1)

    assert Repo.preload(workflow, [
             :edges,
             triggers: Trigger.with_auth_methods_query(),
             jobs: {Workflows.jobs_ordered_subquery(), [:credential, :steps]}
           ])
           |> count_steps() == 2

    assert Repo.preload(workflow, [
             :edges,
             triggers: Trigger.with_auth_methods_query(),
             jobs: {
               Workflows.jobs_ordered_subquery(),
               [:credential, steps: Query.any_step()]
             }
           ])
           |> count_steps == 1
  end

  defp count_steps(workflow) do
    workflow
    |> Map.get(:jobs)
    |> Enum.at(0)
    |> Map.get(:steps)
    |> Enum.count()
  end
end
