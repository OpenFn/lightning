defmodule Lightning.Factories do
  use ExMachina.Ecto, repo: Lightning.Repo

  def webhook_auth_method_factory do
    %Lightning.Workflows.WebhookAuthMethod{
      project: build(:project),
      auth_type: :basic,
      name: sequence(:name, &"webhok-auth-method-#{&1}"),
      username: sequence(:username, &"username-#{&1}"),
      password: "password"
    }
  end

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

  def project_user_factory do
    %Lightning.Projects.ProjectUser{}
  end

  def workflow_factory do
    %Lightning.Workflows.Workflow{
      project: build(:project),
      name: sequence(:workflow_name, &"workflow-#{&1}")
    }
  end

  def job_factory do
    %Lightning.Workflows.Job{
      id: fn -> Ecto.UUID.generate() end,
      name: sequence(:job_name, &"job-#{&1}"),
      workflow: build(:workflow),
      body: "console.log('hello!');"
    }
  end

  def trigger_factory do
    %Lightning.Workflows.Trigger{
      id: fn -> Ecto.UUID.generate() end,
      workflow: build(:workflow),
      enabled: true
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
      id: fn -> Ecto.UUID.generate() end,
      job: build(:job),
      input_dataclip: build(:dataclip)
    }
  end

  def log_line_factory do
    %Lightning.Invocation.LogLine{
      id: Ecto.UUID.generate(),
      message: sequence(:log_line, &"somelog#{&1}"),
      timestamp: build(:timestamp)
    }
  end

  def attempt_factory do
    %Lightning.Attempt{
      id: fn -> Ecto.UUID.generate() end
    }
  end

  def attempt_with_dependencies_factory do
    struct!(
      attempt_factory(),
      %{
        created_by: build(:user),
        work_order: build(:workorder),
        dataclip: build(:dataclip),
        starting_job: build(:job)
      }
    )
  end

  def attempt_run_factory do
    %Lightning.AttemptRun{
      id: fn -> Ecto.UUID.generate() end
    }
  end

  def attempt_run_with_run_factory do
    struct!(
      attempt_run_factory(),
      %{
        run: build(:run)
      }
    )
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
    %Lightning.WorkOrder{
      id: fn -> Ecto.UUID.generate() end,
      workflow: build(:workflow)
    }
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

  @doc """
  Generate an incrementing timestamp.

  By default, it starts 5 minutes in the past and increments by 5 seconds with
  each call.

  If you want to change the initial offset, pass `from: {offset, :second}` for
  example. Where `offset` can be any integer. The default is `-300` (5 minutes).

  To change the gap for the next timestamp, pass `gap: 10` for example. Where
  the next result will be `num_invocations * gap` seconds from the start.

  NOTE: By changing the gap, you won't get exactly `n` seconds after the
  previous timestamp. It changes the stepping, and internally we don't know the
  last timestamp.
  """
  def timestamp_factory(attrs) do
    gap = Map.get(attrs, :gap, 5)
    {ago, scale} = Map.get(attrs, :from, {-300, :second})

    sequence(:timestamp, fn i ->
      DateTime.utc_now()
      |> DateTime.add(ago, scale)
      |> DateTime.add(i * gap, :second)
    end)
  end

  @doc """
  Inserts an attempt and associates it two-way with an work order.
  ```
  work_order =
    insert(:workorder, workflow: workflow, reason: reason)
    |> with_attempt(attempt)

  > **NOTE** The work order must be inserted before calling this function.
  ```
  """
  def with_attempt(work_order, attempt_args) do
    if work_order.__meta__.state == :built do
      raise "Cannot associate an attempt with a work order that has not been inserted"
    end

    attempt_args =
      Keyword.merge(
        [work_order: work_order],
        attempt_args
      )

    attempt = insert(:attempt, attempt_args)

    %{
      work_order
      | attempts: merge_assoc(work_order.attempts, attempt)
    }
  end

  @doc """
  Associates a job with a workflow appending it to the jobs list.
  ```
  workflow =
    build(:workflow, project: project)
    |> with_job(job)
    |> with_trigger(trigger)
    |> with_edge({trigger, job})
  ```
  """
  def with_job(workflow, job) do
    %{
      workflow
      | jobs: merge_assoc(workflow.jobs, merge_attributes(job, %{workflow: nil}))
    }
  end

  def with_trigger(workflow, trigger) do
    %{
      workflow
      | triggers:
          merge_assoc(
            workflow.triggers,
            merge_attributes(trigger, %{workflow: nil})
          )
    }
  end

  def with_edge(workflow, source_target, extra \\ %{})

  def with_edge(
        workflow,
        {%Lightning.Workflows.Job{} = source_job, target_job},
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

  def with_edge(
        workflow,
        {%Lightning.Workflows.Trigger{} = trigger, job},
        extra
      ) do
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

  def simple_workflow_factory(attrs) do
    trigger = build(:trigger, type: :webhook, enabled: true)

    job =
      build(:job,
        body: ~s[fn(state => { return {...state, extra: "data"} })]
      )

    build(:workflow, attrs)
    |> with_trigger(trigger)
    |> with_job(job)
    |> with_edge({trigger, job})
  end

  def complex_workflow_factory(attrs) do
    #
    #          +---+
    #          | T |
    #          +---+
    #            |
    #            |
    #          +---+
    #      +---- 0 ----+
    #      |   +---+   |
    #      |           |
    #      |           |
    #      |           |
    #    +-|-+       +-|-+
    #    | 1 |       | 4 |
    #    +-|-+       +-|-+
    #      |           |
    #      |           |
    #    +-+-+       +-+-+
    #    | 2 |       | 5 |
    #    +-|-+       +-|-+
    #      |           |
    #      |           |
    #    +-+-+       +-+-+
    #    | 3 |       | 6 |
    #    +---+       +---+
    #

    trigger = build(:trigger, type: :webhook)

    jobs =
      build_list(7, :job,
        name: fn -> sequence(:name, &"Job-#{&1}") end,
        body: fn ->
          sequence(
            :body,
            &"""
            fn(state => {
              state.x = (state.x || state.data.x) * 2;
              console.log({output: '#{&1}'});
              return {...state, extra: 'data'};
            });
            """
          )
        end,
        workflow: nil
      )

    build(:workflow, attrs)
    |> with_trigger(trigger)
    |> then(fn workflow ->
      Enum.reduce(jobs, workflow, fn job, workflow ->
        workflow |> with_job(job)
      end)
    end)
    |> with_edge({trigger, jobs |> Enum.at(0)})
    |> with_edge({jobs |> Enum.at(0), jobs |> Enum.at(1)})
    |> with_edge({jobs |> Enum.at(1), jobs |> Enum.at(2)})
    |> with_edge({jobs |> Enum.at(2), jobs |> Enum.at(3)})
    |> with_edge({jobs |> Enum.at(0), jobs |> Enum.at(4)})
    |> with_edge({jobs |> Enum.at(4), jobs |> Enum.at(5)})
    |> with_edge({jobs |> Enum.at(5), jobs |> Enum.at(6)})
  end

  def work_order_for(trigger_or_job, attrs) do
    Lightning.WorkOrders.build_for(trigger_or_job, attrs)
    |> Ecto.Changeset.apply_changes()
  end

  def with_project_user(%Lightning.Projects.Project{} = project, user, role) do
    %{project | project_users: [%{user: user, role: role}]}
  end

  def for_project(%Lightning.Workflows.Job{} = job, project) do
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
