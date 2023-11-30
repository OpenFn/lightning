defmodule Lightning.Invocation.QueryTest do
  use Lightning.DataCase, async: true

  alias Lightning.Invocation.Query

  import Lightning.Factories

  test "runs_for/1 with user" do
    user = insert(:user)
    project = insert(:project, project_users: [%{user_id: user.id}])

    %{triggers: [trigger], jobs: [job]} =
      workflow = insert(:simple_workflow, project: project)

    %{attempts: [%{runs: [run1]}]} =
      insert(:workorder,
        workflow: workflow,
        dataclip: build(:dataclip, project: project),
        trigger: trigger,
        attempts: [
          build(:attempt,
            starting_trigger: trigger,
            dataclip: build(:dataclip, project: project),
            runs: [build(:run, job: job)]
          )
        ]
      )

    %{triggers: [trigger2], jobs: [job2]} = workflow2 = insert(:simple_workflow)

    %{attempts: [%{runs: [run2]}]} =
      insert(:workorder,
        workflow: workflow2,
        dataclip: build(:dataclip),
        trigger: trigger2,
        attempts: [
          build(:attempt,
            dataclip: build(:dataclip),
            starting_trigger: trigger2,
            runs: [build(:run, job: job2)]
          )
        ]
      )

    refute run1.id == run2.id

    run1_id = run1.id

    assert [%{id: ^run1_id}] = Query.runs_for(user) |> Repo.all()
  end
end
