defmodule Lightning.Jobs.JobFormTest do
  use Lightning.DataCase, async: true

  alias Lightning.Jobs.JobForm
  import Lightning.ProjectsFixtures
  import Lightning.JobsFixtures
  import Lightning.WorkflowsFixtures

  test "new everything" do
    project = project_fixture()

    attrs = %{
      "trigger" => %{"type" => "webhook"},
      "workflow" => %{},
      "job" => %{
        "name" => "my job",
        "adaptor" => "adaptor name",
        "body" => "{}"
      }
    }

    job_form = JobForm.changeset(%JobForm{project_id: project.id}, attrs)

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
      "trigger" => %{"type" => "on_job_success"},
      # "workflow" => %{},
      "job" => %{
        "name" => "my on success job",
        "adaptor" => "adaptor name",
        "body" => "{}"
      },
      "project_id" => project.id
    }

    job_form =
      JobForm.changeset(
        %JobForm{workflow: workflow, project_id: project.id},
        attrs
      )

    assert job_form.valid?

    # {:ok, attrs} = job_form |> JobForm.attributes()

    {:ok, %{job: job, trigger: trigger, workflow: ^workflow}} =
      JobForm.to_multi(job_form, attrs) |> Repo.transaction()

    # assert workflow.id == workflow.id
    assert trigger.workflow_id == workflow.id
    assert job.workflow_id == workflow.id
    assert job.trigger_id == trigger.id
  end

  test "updating a job" do
    project = project_fixture()
    job = job_fixture()

    attrs = %{
      # "trigger" => %{"type" => "on_job_success"},
      # "workflow" => %{},
      "job" => %{
        "id" => job.id,
        "name" => "my on success job",
        "adaptor" => "adaptor name",
        "body" => "{}"
      }
    }

    job_form =
      JobForm.changeset(
        %JobForm{workflow: job.workflow, job: job, project_id: project.id},
        attrs
      )

    assert job_form.valid?

    {:ok, %{job: updated_job, trigger: trigger, workflow: workflow}} =
      JobForm.to_multi(job_form, attrs) |> Repo.transaction()

    assert updated_job.workflow.id == workflow.id
    assert updated_job.trigger.workflow_id == workflow.id
    assert updated_job.trigger_id == trigger.id
  end

  test "updating a job's trigger" do
    project = project_fixture()
    job = job_fixture()

    attrs = %{
      "trigger" => %{"type" => "on_job_failure", "id" => job.trigger_id},
      "job" => %{"id" => job.id}
    }

    job_form =
      JobForm.changeset(
        %JobForm{
          workflow: job.workflow,
          trigger: job.trigger,
          job: job,
          project_id: project.id
        },
        attrs
      )

    assert job_form.valid?

    {:ok, %{job: updated_job, trigger: trigger, workflow: workflow}} =
      JobForm.to_multi(job_form, attrs) |> Repo.transaction()

    assert updated_job.workflow.id == workflow.id
    assert updated_job.trigger.workflow_id == workflow.id
    assert updated_job.trigger_id == trigger.id
    assert trigger.type == :on_job_failure
  end
end
