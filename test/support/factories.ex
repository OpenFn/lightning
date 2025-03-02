defmodule Lightning.Factories do
  use ExMachina.Ecto, repo: Lightning.Repo
  alias Lightning.Workflows.Snapshot

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
      repo: "some/repo",
      branch: "branch",
      github_installation_id: "some-id",
      access_token: sequence(:token, &"prc_sometoken#{&1}")
    }
  end

  def project_factory do
    %Lightning.Projects.Project{
      name: sequence(:project_name, &"project-#{&1}")
    }
  end

  def project_file_factory do
    %Lightning.Projects.File{
      path: nil,
      size: 123,
      status: :enqueued,
      type: :export,
      created_by: build(:user),
      project: build(:project)
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
    %Lightning.Workflows.Edge{
      id: fn -> Ecto.UUID.generate() end,
      workflow: build(:workflow),
      condition_type: :always
    }
  end

  def dataclip_factory do
    %Lightning.Invocation.Dataclip{
      project: build(:project),
      body: %{},
      type: :http_request
    }
  end

  def http_request_dataclip_factory do
    %Lightning.Invocation.Dataclip{
      project: build(:project),
      body: %{"foo" => "bar"},
      request: %{"headers" => %{"content-type" => "application/json"}},
      type: :http_request
    }
  end

  def step_factory do
    %Lightning.Invocation.Step{
      id: fn -> Ecto.UUID.generate() end,
      job: build(:job),
      input_dataclip: build(:dataclip),
      snapshot: build(:snapshot)
    }
  end

  def snapshot_factory do
    %Lightning.Workflows.Snapshot{
      name: sequence(:name, &"snapshot-#{&1}"),
      lock_version: 1,
      workflow: build(:workflow),
      jobs: build_list(3, :snapshot_job),
      triggers: build_list(2, :snapshot_trigger),
      edges: build_list(2, :snapshot_edge)
    }
  end

  def snapshot_job_factory do
    %Lightning.Workflows.Snapshot.Job{
      id: Ecto.UUID.generate(),
      name: sequence(:job_name, &"job-#{&1}"),
      body: "console.log('hello!');",
      adaptor: "some_adaptor",
      project_credential_id: Ecto.UUID.generate(),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  def snapshot_trigger_factory do
    %Lightning.Workflows.Snapshot.Trigger{
      id: Ecto.UUID.generate(),
      comment: "A sample trigger",
      custom_path: "some/path",
      cron_expression: "* * * * *",
      enabled: true,
      type: :webhook,
      has_auth_method: false,
      webhook_auth_methods: build_list(1, :webhook_auth_method),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  def snapshot_edge_factory do
    %Lightning.Workflows.Snapshot.Edge{
      id: Ecto.UUID.generate(),
      source_job_id: Ecto.UUID.generate(),
      source_trigger_id: Ecto.UUID.generate(),
      target_job_id: Ecto.UUID.generate(),
      condition_type: :always,
      condition_expression: "true",
      condition_label: "Always",
      enabled: true,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  def log_line_factory do
    %Lightning.Invocation.LogLine{
      id: fn -> Ecto.UUID.generate() end,
      message: sequence(:log_line, &"somelog#{&1}"),
      timestamp: build(:timestamp)
    }
  end

  def run_factory do
    %Lightning.Run{
      id: fn -> Ecto.UUID.generate() end,
      snapshot: build(:snapshot),
      options: %Lightning.Runs.RunOptions{}
    }
  end

  def run_step_factory do
    %Lightning.RunStep{
      id: fn -> Ecto.UUID.generate() end
    }
  end

  def oauth_token_factory(attrs \\ %{}) do
    scopes = Map.get(attrs, :scope, ["read", "write"])
    unique_id = System.unique_integer([:positive])

    default_token_body = %{
      "access_token" => "access_token_#{unique_id}",
      "refresh_token" => "refresh_token_#{unique_id}",
      "token_type" => "bearer",
      "expires_in" => 3600
    }

    %Lightning.Credentials.OauthToken{
      body:
        attrs
        |> Map.get(:body, default_token_body)
        |> Lightning.Credentials.normalize_keys(),
      user: Map.get(attrs, :user, build(:user)),
      oauth_client: Map.get(attrs, :oauth_client),
      scopes: Enum.sort(scopes),
      updated_at: DateTime.utc_now()
    }
  end

  def credential_factory(attrs \\ %{}) do
    schema = Map.get(attrs, :schema, "raw")

    oauth_token =
      if schema == "oauth" do
        create_oauth_token(attrs)
      else
        nil
      end

    attrs = attrs |> Map.delete(:oauth_token) |> Map.delete(:oauth_client)

    %Lightning.Credentials.Credential{
      body: %{},
      schema: schema,
      name: sequence(:credential_name, &"credential#{&1}")
    }
    |> add_oauth_token(schema, oauth_token)
    |> Map.merge(attrs)
  end

  defp create_oauth_token(attrs) do
    user = determine_user(attrs)
    client = determine_client(attrs)
    token_body = Map.get(attrs, :oauth_token, %{})

    oauth_token_attrs = %{
      body: token_body,
      user_id: user.id,
      user: user,
      oauth_client_id: client && client.id,
      oauth_client: client
    }

    oauth_token_attrs =
      case Lightning.Credentials.OauthToken.extract_scopes(token_body) do
        {:ok, scopes} -> Map.put(oauth_token_attrs, :scope, scopes)
        :error -> oauth_token_attrs
      end

    insert(:oauth_token, oauth_token_attrs)
  end

  defp determine_user(%{user: %Lightning.Accounts.User{id: nil} = _user}),
    do: insert(:user)

  defp determine_user(%{user: %Lightning.Accounts.User{} = user}), do: user

  defp determine_user(%{user_id: id}) when not is_nil(id),
    do: Lightning.Repo.get!(Lightning.Accounts.User, id)

  defp determine_user(_), do: insert(:user)

  defp determine_client(%{
         oauth_client: %Lightning.Credentials.OauthClient{id: nil} = _client
       }),
       do: insert(:oauth_client)

  defp determine_client(%{
         oauth_client: %Lightning.Credentials.OauthClient{} = client
       }),
       do: client

  defp determine_client(%{oauth_client_id: id}) when not is_nil(id),
    do: Lightning.Repo.get!(Lightning.Credentials.OauthClient, id)

  defp determine_client(_), do: nil

  defp add_oauth_token(credential, "oauth", oauth_token) do
    Map.put(
      credential,
      :oauth_token,
      Lightning.Repo.preload(oauth_token, :oauth_client)
    )
  end

  defp add_oauth_token(credential, _, _), do: credential

  def project_credential_factory do
    %Lightning.Projects.ProjectCredential{
      project: build(:project),
      credential: build(:credential)
    }
  end

  def oauth_client_factory do
    %Lightning.Credentials.OauthClient{
      name: sequence(:oauth_client_name, &"oauth-client#{&1}"),
      client_id: sequence(:client_id, &"client-id-#{&1}"),
      client_secret: sequence(:client_secret, &"client-secret-#{&1}"),
      authorization_endpoint: "http://example.com/oauth2/authorize",
      token_endpoint: "http://example.com/oauth2/token",
      userinfo_endpoint: "http://example.com/oauth2/userinfo",
      revocation_endpoint: "http://example.com/oauth2/revoke",
      global: false,
      mandatory_scopes: "scope_1,scope_2",
      optional_scopes: "scope_3,scope_4",
      scopes_doc_url: "http://example.com/scopes/doc",
      user: build(:user)
    }
  end

  def project_oauth_client_factory do
    %Lightning.Projects.ProjectOauthClient{
      project: build(:project),
      oauth_client: build(:oauth_client)
    }
  end

  def workorder_factory do
    %Lightning.WorkOrder{
      id: fn -> Ecto.UUID.generate() end,
      workflow: build(:workflow),
      snapshot: build(:snapshot)
    }
  end

  def user_factory do
    %Lightning.Accounts.User{
      email: sequence(:email, &"email-#{&1}@example.com"),
      password: "hello world!",
      first_name: "anna",
      last_name: sequence(:name, &"last-name-#{&1}"),
      hashed_password: Bcrypt.hash_pwd_salt("hello world!")
    }
  end

  def user_totp_factory do
    %Lightning.Accounts.UserTOTP{
      secret: NimbleTOTP.secret()
    }
  end

  def user_token_factory do
    %Lightning.Accounts.UserToken{
      token: fn -> Ecto.UUID.generate() end
    }
  end

  def backup_code_factory do
    %Lightning.Accounts.UserBackupCode{
      code: Lightning.Accounts.UserBackupCode.generate_backup_code()
    }
  end

  def usage_tracking_daily_report_configuration_factory do
    %Lightning.UsageTracking.DailyReportConfiguration{}
  end

  def usage_tracking_report_factory do
    now = DateTime.utc_now()

    %Lightning.UsageTracking.Report{
      data: %{},
      submitted: true,
      submitted_at: now,
      report_date: DateTime.to_date(now)
    }
  end

  def triggers_kafka_configuration_factory do
    %Lightning.Workflows.Triggers.KafkaConfiguration{
      group_id: "arb_group_id",
      hosts: [
        ["localhost", "9096"],
        ["localhost", "9095"],
        ["localhost", "9094"]
      ],
      initial_offset_reset_policy: "earliest",
      ssl: false,
      topics: ["arb_topic"]
    }
  end

  def trigger_kafka_message_record_factory do
    %Lightning.KafkaTriggers.TriggerKafkaMessageRecord{
      topic_partition_offset: "foo_1_1001"
    }
  end

  def chat_session_factory do
    %Lightning.AiAssistant.ChatSession{
      id: fn -> Ecto.UUID.generate() end,
      expression: "fn()",
      adaptor: "@openfn/language-common@latest",
      title: "Some session title",
      messages: []
    }
  end

  def chat_message_factory do
    %Lightning.AiAssistant.ChatMessage{
      content: "Hello, world!",
      role: :user
    }
  end

  def collection_factory do
    %Lightning.Collections.Collection{
      project: build(:project),
      name: sequence(:name, &"collection-#{&1}"),
      byte_size_sum: 0
    }
  end

  def collection_item_factory do
    %Lightning.Collections.Item{
      id: sequence(:id, & &1),
      key: sequence(:key, &"key-#{&1}", start_at: 100),
      value: sequence(:value, &"value-#{&1}", start_at: 100),
      collection: build(:collection),
      inserted_at:
        sequence(
          :inserted_at,
          &DateTime.add(DateTime.utc_now(), &1, :microsecond)
        )
    }
  end

  def audit_factory do
    %Lightning.Auditing.Audit{
      item_type: "item_type",
      item_id: fn -> Ecto.UUID.generate() end,
      event: "something_happened",
      changes: %{before: %{"stuff" => "bad"}, after: %{"stuff" => "good"}}
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
      |> DateTime.add(i * gap, scale)
    end)
  end

  @doc """
  Inserts a run and associates it two-way with an work order.
  ```
  work_order =
    insert(:workorder, workflow: workflow)
    |> with_run(run)

  > **NOTE** The work order must be inserted before calling this function.
  ```
  """
  def with_run(work_order, run_or_args) do
    if work_order.__meta__.state == :built do
      raise "Cannot associate a run with a work order that has not been inserted"
    end

    run =
      case run_or_args do
        %Lightning.Run{} = run ->
          if run.__meta__.state != :built do
            raise "The run must be built, not inserted"
          end

          run
          |> merge_attributes(%{work_order: work_order})
          |> insert()

        run_args ->
          build(:run, run_args)
          |> merge_attributes(%{work_order: work_order})
          |> insert()
      end

    %{
      work_order
      | runs: merge_assoc(work_order.runs, run)
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
    edge_params =
      params_for(
        :edge,
        %{
          id: Ecto.UUID.generate(),
          source_job_id: source_job.id,
          target_job_id: target_job.id,
          condition_type: :always
        }
        |> Map.merge(extra |> Enum.into(%{}))
      )

    %{workflow | edges: merge_assoc(workflow.edges, edge_params)}
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
              source_job_id: nil,
              target_job_id: job.id,
              condition_type: :always,
              enabled: true
            })
          )
    }
  end

  def simple_workflow_factory(attrs) do
    trigger =
      build(:trigger,
        type: :webhook,
        enabled: true
      )

    job =
      build(:job,
        body: ~s[fn(state => { return {...state, extra: "data"} })]
      )

    build(:workflow, attrs)
    |> with_trigger(trigger)
    |> with_job(job)
    |> with_edge({trigger, job}, condition_type: :always)
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
    |> with_edge({trigger, jobs |> Enum.at(0)}, condition_type: :always)
    |> with_edge({jobs |> Enum.at(0), jobs |> Enum.at(1)},
      condition_type: :on_job_success
    )
    |> with_edge({jobs |> Enum.at(1), jobs |> Enum.at(2)},
      condition_type: :always
    )
    |> with_edge({jobs |> Enum.at(2), jobs |> Enum.at(3)},
      condition_type: :always
    )
    |> with_edge({jobs |> Enum.at(0), jobs |> Enum.at(4)},
      condition_type: :on_job_failure
    )
    |> with_edge({jobs |> Enum.at(4), jobs |> Enum.at(5)},
      condition_type: :always
    )
    |> with_edge({jobs |> Enum.at(5), jobs |> Enum.at(6)},
      condition_type: :always
    )
  end

  def work_order_for(trigger_or_job, attrs) do
    attrs = Map.new(attrs)
    workflow = Map.fetch!(attrs, :workflow)

    snapshot =
      Snapshot.get_current_for(workflow) ||
        Snapshot.create(workflow) |> then(fn {:ok, snapshot} -> snapshot end)

    Lightning.WorkOrders.build_for(
      trigger_or_job,
      Map.merge(attrs, %{actor: insert(:user), snapshot: snapshot})
    )
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

  def with_snapshot(workflow) do
    workflow |> tap(&Lightning.Workflows.Snapshot.create/1)
  end
end
