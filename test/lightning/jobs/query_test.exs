defmodule Lightning.Jobs.QueryTest do
  use Lightning.DataCase, async: true

  alias Lightning.Jobs.Query
  import Lightning.JobsFixtures
  import Lightning.AccountsFixtures
  import Lightning.ProjectsFixtures

  test "jobs_for/1 with user" do
    user = user_fixture()
    project = project_fixture(project_users: [%{user_id: user.id}])

    job = job_fixture(project_id: project.id)
    _other_job = job_fixture()

    assert Query.jobs_for(user) |> Repo.all() == [
             job |> unload_relation(:trigger)
           ]
  end

  test "enabled_cron_jobs/0" do
    job = job_fixture(trigger: %{type: :cron, cron: "* * * * *"}, enabled: true)

    _disabled_conjob =
      job_fixture(trigger: %{type: :cron, cron: "* * * * *"}, enabled: false)

    _non_cronjob = job_fixture()

    assert Query.enabled_cron_jobs() |> Repo.all() == [job]
  end
end
