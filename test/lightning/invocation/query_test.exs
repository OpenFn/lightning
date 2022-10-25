defmodule Lightning.Invocation.QueryTest do
  use Lightning.DataCase, async: true

  alias Lightning.Invocation.Query
  import Lightning.InvocationFixtures
  import Lightning.JobsFixtures
  import Lightning.AccountsFixtures
  import Lightning.ProjectsFixtures
  import Lightning.WorkflowsFixtures

  test "runs_for/1 with user" do
    user = user_fixture()
    project = project_fixture(project_users: [%{user_id: user.id}])

    job = job_fixture(workflow_id: workflow_fixture(project_id: project.id).id)
    run = run_fixture(job_id: job.id)
    _other_run = run_fixture()

    assert Query.runs_for(user) |> Repo.all() == [run]
  end
end
