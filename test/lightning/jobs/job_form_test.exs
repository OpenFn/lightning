defmodule Lightning.Jobs.JobFormTest do
  use Lightning.DataCase, async: true

  alias Lightning.Jobs.JobForm
  import Lightning.ProjectsFixtures
  import Lightning.JobsFixtures
  import Lightning.WorkflowsFixtures

  test "from_job/1" do
    job = workflow_job_fixture()

    form = JobForm.from_job(job)

    assert form.adaptor == job.adaptor
    assert form.body == job.body
    assert form.id == job.id
    assert form.trigger_id == job.trigger.id
    assert form.trigger_type == job.trigger.type
    assert form.trigger_upstream_job_id == job.trigger.upstream_job_id
    assert form.workflow_id == job.trigger.workflow_id
    assert form.project_id == job.workflow.project_id
  end

  test "new everything" do
    project = project_fixture()

    attrs = %{
      "trigger_type" => "webhook",
      "name" => "my job",
      "adaptor" => "adaptor name",
      "body" => "{}",
      "project_id" => project.id
    }

    job_form = JobForm.changeset(%JobForm{}, attrs)

    assert job_form.valid?

    # {:ok, attrs} = job_form |> JobForm.attributes()

    {:ok, %{job: job, trigger: trigger, workflow: workflow}} =
      JobForm.to_multi(job_form, attrs) |> Repo.transaction()

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
      JobForm.changeset(
        %JobForm{workflow_id: workflow.id, project_id: project.id},
        attrs
      )

    assert job_form.valid?

    # {:ok, attrs} = job_form |> JobForm.attributes()

    {:ok, result} = JobForm.to_multi(job_form, attrs) |> Repo.transaction()

    # assert workflow.id == workflow.id
    assert result.trigger.workflow_id == workflow.id
    assert result.job.workflow_id == workflow.id
    assert result.job.trigger_id == result.trigger.id
  end

  test "updating a job" do
    project = project_fixture()
    job = workflow_job_fixture()

    attrs = %{
      "name" => "my on success job",
      "adaptor" => "adaptor name",
      "body" => "{}"
    }

    job_form =
      JobForm.changeset(
        %JobForm{
          workflow_id: job.workflow.id,
          trigger_id: job.trigger_id,
          id: job.id,
          project_id: project.id
        },
        attrs
      )

    assert job_form.valid?

    {:ok, result} = JobForm.to_multi(job_form, attrs) |> Repo.transaction()

    assert result.job.workflow_id == job.workflow.id
    assert result.trigger.workflow_id == job.workflow.id
    assert result.job.trigger_id == job.trigger_id
  end

  test "updating a job's trigger" do
    # project = project_fixture()
    job = job_fixture()

    attrs = %{"trigger_type" => "on_job_failure"}

    job_form =
      JobForm.changeset(
        job |> JobForm.from_job(),
        attrs
      )

    assert job_form.valid?,
           "Expected to be valid: #{job_form.errors |> inspect(pretty: true)}"

    {:ok, result} = JobForm.to_multi(job_form, attrs) |> Repo.transaction()

    assert result.job.trigger_id == job.trigger_id
    assert result.trigger.type == :on_job_failure
  end
end
