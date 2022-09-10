defmodule Lightning.FullProjectsFixtures do
  @moduledoc """
  This module generates full projects for testing purpose
  """

  @doc """
  Generate a project with 2 workflows with all kind of jobs
  """

  import Lightning.ProjectsFixtures
  import Lightning.CredentialsFixtures
  import Lightning.WorkflowsFixtures
  import Lightning.JobsFixtures

  def full_project_fixture() do
    project = project_fixture()
    w1 = workflow_fixture(project_id: project.id, name: "workflow 1")
    w2 = workflow_fixture(project_id: project.id, name: "workflow 2")

    project_credential =
      project_credential_fixture(
        name: "new credential",
        body: %{"foo" => "manchu"}
      )

    w1_job =
      job_fixture(
        name: "webhook job",
        project_id: project.id,
        workflow_id: w1.id,
        project_credential_id: project_credential.id,
        trigger: %{type: :webhook},
        body: "console.log('webhook job')\nfn(state => state)"
      )

    job_fixture(
      name: "on fail",
      project_id: project.id,
      workflow_id: w1.id,
      trigger: %{type: :on_job_failure, upstream_job_id: w1_job.id},
      body: "console.log('on fail')\nfn(state => state)"
    )

    job_fixture(
      name: "on success",
      project_id: project.id,
      workflow_id: w1.id,
      trigger: %{type: :on_job_success, upstream_job_id: w1_job.id}
    )

    w2_job =
      job_fixture(
        name: "other workflow",
        project_id: project.id,
        workflow_id: w2.id,
        trigger: %{type: :webhook}
      )

    job_fixture(
      name: "on fail",
      project_id: project.id,
      workflow_id: w2.id,
      trigger: %{type: :on_job_failure, upstream_job_id: w2_job.id}
    )

    job_fixture(
      name: "unrelated job",
      trigger: %{type: :webhook}
    )

    %{project: project, w1: w1, w2: w2}
  end
end
