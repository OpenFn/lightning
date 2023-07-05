defmodule Lightning.Factories do
  use ExMachina.Ecto, repo: Lightning.Repo

  def project_factory do
    %Lightning.Projects.Project{}
  end

  def workflow_factory do
    %Lightning.Workflows.Workflow{project: build(:project)}
  end

  def job_factory do
    %Lightning.Jobs.Job{
      id: fn -> Ecto.UUID.generate() end,
      workflow: build(:workflow),
      body: "console.log('hello!');"
    }
  end

  def trigger_factory do
    %Lightning.Jobs.Trigger{
      id: fn -> Ecto.UUID.generate() end,
      workflow: build(:workflow)
    }
  end

  def edge_factory do
    %Lightning.Workflows.Edge{workflow: build(:workflow)}
  end

  def dataclip_factory do
    %Lightning.Invocation.Dataclip{project: build(:project)}
  end

  def run_factory do
    %Lightning.Invocation.Run{
      job: build(:job),
      input_dataclip: build(:dataclip)
    }
  end

  def attempt_factory do
    %Lightning.Attempt{}
  end

  def reason_factory do
    %Lightning.InvocationReason{}
  end

  def credential_factory do
    %Lightning.Credentials.Credential{}
  end

  def project_credential_factory do
    %Lightning.Projects.ProjectCredential{
      project: build(:project),
      credential: build(:credential)
    }
  end

  def workorder_factory do
    %Lightning.WorkOrder{workflow: build(:workflow)}
  end

  def user_factory do
    %Lightning.Accounts.User{
      email: sequence(:email, &"email-#{&1}@example.com"),
      password: "hello world!",
      first_name: "anna",
      hashed_password: Bcrypt.hash_pwd_salt("hello world!")
    }
  end

  # ----------------------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------------------
  # Useful for building up a workflow in a test:
  #
  # ```
  # workflow =
  #   build(:workflow, project: project)
  #   |> with_job(job)
  #   |> with_trigger(trigger)
  #   |> with_edge({trigger, job})
  # ```

  def with_job(workflow, job) do
    %{
      workflow
      | jobs: [%{job | workflow: nil}]
    }
  end

  def with_trigger(workflow, trigger) do
    %{
      workflow
      | triggers: [%{trigger | workflow: nil}]
    }
  end

  def with_edge(workflow, {%Lightning.Jobs.Trigger{} = trigger, job}) do
    %{
      workflow
      | edges: [
          %{
            id: Ecto.UUID.generate(),
            source_trigger_id: trigger.id,
            target_job_id: job.id
          }
        ]
    }
  end

  def with_project_user(%Lightning.Projects.Project{} = project, user, role) do
    %{project | project_users: [%{user: user, role: role}]}
  end
end
