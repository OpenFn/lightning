defmodule Lightning.Factories do
  use ExMachina.Ecto, repo: Lightning.Repo

  def project_repo_connection_factory do
    %Lightning.VersionControl.ProjectRepoConnection{
      project: build(:project),
      user: build(:user),
      repo: "some/repo",
      branch: "branch",
      github_installation_id: "some-id"
    }
  end

  def project_factory do
    %Lightning.Projects.Project{
      name: sequence(:project_name, &"project-#{&1}")
    }
  end

  def workflow_factory do
    %Lightning.Workflows.Workflow{
      project: build(:project),
      name: sequence(:workflow_name, &"workflow-#{&1}")
    }
  end

  def job_factory do
    %Lightning.Jobs.Job{
      id: fn -> Ecto.UUID.generate() end,
      name: sequence(:job_name, &"job-#{&1}"),
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
    %Lightning.Invocation.Dataclip{
      project: build(:project),
      body: %{},
      type: :http_request
    }
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

  def user_totp_factory do
    %Lightning.Accounts.UserTOTP{
      secret: NimbleTOTP.secret()
    }
  end

  def backup_code_factory do
    %Lightning.Accounts.UserBackupCode{
      code: Lightning.Accounts.UserBackupCode.generate_backup_code()
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
      | jobs: merge_assoc(workflow.jobs, merge_attributes(job, %{workflow: nil}))
    }
  end

  def with_trigger(workflow, trigger) do
    %{
      workflow
      | triggers: merge_assoc(workflow.triggers, %{trigger | workflow: nil})
    }
  end

  def with_edge(workflow, source_target, extra \\ %{})

  def with_edge(
        workflow,
        {%Lightning.Jobs.Job{} = source_job, target_job},
        extra
      ) do
    %{
      workflow
      | edges:
          merge_assoc(
            workflow.edges,
            Enum.into(extra, %{
              id: Ecto.UUID.generate(),
              source_job_id: source_job.id,
              target_job_id: target_job.id
            })
          )
    }
  end

  def with_edge(workflow, {%Lightning.Jobs.Trigger{} = trigger, job}, extra) do
    %{
      workflow
      | edges:
          merge_assoc(
            workflow.edges,
            Enum.into(extra, %{
              id: Ecto.UUID.generate(),
              source_trigger_id: trigger.id,
              target_job_id: job.id
            })
          )
    }
  end

  def with_project_user(%Lightning.Projects.Project{} = project, user, role) do
    %{project | project_users: [%{user: user, role: role}]}
  end

  def for_project(%Lightning.Jobs.Job{} = job, project) do
    %{job | workflow: build(:workflow, %{project: project})}
  end

  defp merge_assoc(left, right) do
    case left do
      %Ecto.Association.NotLoaded{} ->
        [right]

      left when is_list(left) ->
        Enum.concat(left, List.wrap(right))
    end
  end
end
