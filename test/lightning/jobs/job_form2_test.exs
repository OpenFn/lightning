defmodule Lightning.Jobs.JobForm2Test do
  use Lightning.DataCase, async: true

  alias Lightning.Jobs.JobForm2
  import Lightning.ProjectsFixtures
  import Lightning.JobsFixtures
  import Lightning.WorkflowsFixtures

  test "new everything" do
    project = project_fixture()

    attrs = %{
      "trigger_type" => "webhook",
      "name" => "my job",
      "adaptor" => "adaptor name",
      "body" => "{}",
      "project_id" => project.id
    }

    job_form = JobForm2.changeset(%JobForm2{}, attrs)

    assert job_form.valid?

    # {:ok, attrs} = job_form |> JobForm2.attributes()

    {:ok, %{job: job, trigger: trigger, workflow: workflow}} =
      JobForm2.to_multi(job_form, attrs) |> Repo.transaction()

    assert workflow.id
    assert trigger.workflow_id == workflow.id
    assert job.workflow_id == workflow.id
    assert job.trigger_id == trigger.id
  end

  test "new job within an existing workflow" do
    project = project_fixture()
    workflow = workflow_fixture(project_id: project.id)

    attrs = %{
      "trigger_type" => "on_job_success",
      "workflow_id" => workflow.id,
      "name" => "my on success job",
      "adaptor" => "adaptor name",
      "body" => "{}",
      "project_id" => project.id
    }

    job_form =
      JobForm2.changeset(
        %JobForm2{workflow_id: workflow.id, project_id: project.id},
        attrs
      )

    assert job_form.valid?

    # {:ok, attrs} = job_form |> JobForm2.attributes()

    {:ok, result} = JobForm2.to_multi(job_form, attrs) |> Repo.transaction()

    # assert workflow.id == workflow.id
    assert result.trigger.workflow_id == workflow.id
    assert result.job.workflow_id == workflow.id
    assert result.job.trigger_id == result.trigger.id
  end

  test "updating a job" do
    project = project_fixture()
    job = job_fixture()

    attrs = %{
      "job_id" => job.id,
      "name" => "my on success job",
      "adaptor" => "adaptor name",
      "body" => "{}"
    }

    job_form =
      JobForm2.changeset(
        %JobForm2{
          workflow_id: job.workflow.id,
          trigger_id: job.trigger_id,
          job_id: job.id,
          project_id: project.id
        },
        attrs
      )

    IO.inspect(job_form)
    assert job_form.valid?

    {:ok, result} = JobForm2.to_multi(job_form, attrs) |> Repo.transaction()

    assert result.job.workflow_id == job.workflow.id
    assert result.trigger.workflow_id == job.workflow.id
    assert result.job.trigger_id == job.trigger_id
  end

  # test "updating a job's trigger" do
  #   project = project_fixture()
  #   job = job_fixture()

  #   attrs = %{
  #     "trigger" => %{"type" => "on_job_failure", "id" => job.trigger_id},
  #     "job" => %{"id" => job.id}
  #   }

  #   job_form =
  #     JobForm2.changeset(
  #       %JobForm2{
  #         workflow: job.workflow,
  #         trigger: job.trigger,
  #         job: job,
  #         project_id: project.id
  #       },
  #       attrs
  #     )

  #   assert job_form.valid?

  #   {:ok, %{job: updated_job, trigger: trigger, workflow: workflow}} =
  #     JobForm2.to_multi(job_form, attrs) |> Repo.transaction()

  #   assert updated_job.workflow.id == workflow.id
  #   assert updated_job.trigger.workflow_id == workflow.id
  #   assert updated_job.trigger_id == trigger.id
  #   assert trigger.type == :on_job_failure
  # end
end
