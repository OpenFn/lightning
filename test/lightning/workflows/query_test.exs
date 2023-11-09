defmodule Lightning.Workflows.QueryTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.Query
  import Lightning.JobsFixtures
  import Lightning.AccountsFixtures
  import Lightning.ProjectsFixtures
  import Lightning.Factories

  test "jobs_for/1 with user" do
    user = user_fixture()
    project = project_fixture(project_users: [%{user_id: user.id}])

    job = job_fixture(project_id: project.id)
    _other_job = job_fixture()

    assert Query.jobs_for(user) |> Repo.all() == [
             job |> unload_relation(:trigger)
           ]
  end

  describe "enabled_cron_jobs_by_edge/0" do
    test "returns the jobs when trigger is enabled" do
      trigger =
        insert(:trigger, %{
          type: :cron,
          cron_expression: "* * * * *",
          enabled: true
        })

      job = insert(:job, enabled: true, workflow: trigger.workflow)

      insert(:edge, %{
        source_trigger: trigger,
        target_job: job,
        workflow: job.workflow
      })

      _disabled_cronjob =
        insert(:job, enabled: false, workflow: trigger.workflow)

      webhook_trigger = insert(:trigger, type: :webhook)

      _non_cron_job =
        insert(:job, enabled: true, workflow: webhook_trigger.workflow)

      jobs =
        Query.enabled_cron_jobs_by_edge()
        |> Repo.all()
        |> Enum.map(fn e -> e.target_job.id end)

      assert jobs == [job.id]
    end

    test "returns no jobs when trigger is disabled" do
      trigger =
        insert(:trigger, %{
          type: :cron,
          cron_expression: "* * * * *",
          enabled: false
        })

      job = insert(:job, enabled: true, workflow: trigger.workflow)

      insert(:edge, %{
        source_trigger: trigger,
        target_job: job,
        workflow: job.workflow
      })

      _disabled_cronjob =
        insert(:job, enabled: false, workflow: trigger.workflow)

      webhook_trigger = insert(:trigger, type: :webhook)

      _non_cron_job =
        insert(:job, enabled: true, workflow: webhook_trigger.workflow)

      jobs =
        Query.enabled_cron_jobs_by_edge()
        |> Repo.all()
        |> Enum.map(fn e -> e.target_job.id end)

      assert jobs == []
    end
  end
end
