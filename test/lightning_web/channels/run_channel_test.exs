defmodule LightningWeb.RunChannelTest do
  use LightningWeb.ChannelCase, async: true

  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Step
  alias Lightning.Workers

  import Ecto.Query
  import Lightning.TestUtils
  import Lightning.Factories
  import Lightning.BypassHelpers

  setup _ do
    Mox.stub_with(
      Lightning.Extensions.MockUsageLimiter,
      Lightning.Extensions.UsageLimiter
    )

    :ok
  end

  describe "joining" do
    test "without providing a token" do
      assert LightningWeb.UserSocket
             |> socket("socket_id", %{})
             |> subscribe_and_join(LightningWeb.WorkerChannel, "worker:queue") ==
               {:error, %{reason: "unauthorized"}}
    end
  end

  describe "joining the run:* channel" do
    setup do
      Lightning.Stub.reset_time()

      {:ok, bearer, _} =
        Workers.Token.generate_and_sign(
          %{},
          Lightning.Config.worker_token_signer()
        )

      Lightning.Stub.freeze_time(DateTime.utc_now() |> DateTime.add(5, :second))

      socket = LightningWeb.WorkerSocket |> socket("socket_id", %{token: bearer})

      %{socket: socket}
    end

    test "rejects joining when the token isn't valid", %{socket: socket} do
      assert {:error, %{reason: "unauthorized"}} =
               socket
               |> subscribe_and_join(LightningWeb.RunChannel, "run:123")

      assert {:error, %{reason: "unauthorized"}} =
               socket
               |> subscribe_and_join(
                 LightningWeb.RunChannel,
                 "run:123",
                 %{"token" => "invalid"}
               )

      # A valid token, but nbf hasn't been reached yet
      {:ok, bearer, _} =
        Workers.Token.generate_and_sign(
          %{
            "nbf" =>
              DateTime.utc_now()
              |> DateTime.add(5, :second)
              |> DateTime.to_unix()
          },
          Lightning.Config.run_token_signer()
        )

      Lightning.Stub.freeze_time(DateTime.utc_now())

      assert {:error, %{reason: "unauthorized"}} =
               socket
               |> subscribe_and_join(
                 LightningWeb.RunChannel,
                 "run:123",
                 %{"token" => bearer}
               )

      # A valid token, but the id doesn't match the channel name
      id = Ecto.UUID.generate()
      other_id = Ecto.UUID.generate()

      bearer = Workers.generate_run_token(%{id: id})

      assert {:error, %{reason: "unauthorized"}} =
               socket
               |> subscribe_and_join(
                 LightningWeb.RunChannel,
                 "run:#{other_id}",
                 %{"token" => bearer}
               )
    end

    test "joining with a valid token but run is not found", %{socket: socket} do
      id = Ecto.UUID.generate()

      bearer =
        Workers.generate_run_token(%{id: id})

      assert {:error, %{reason: "not_found"}} =
               socket
               |> subscribe_and_join(
                 LightningWeb.RunChannel,
                 "run:#{id}",
                 %{"token" => bearer}
               )
    end
  end

  describe "fetching run data" do
    setup :set_google_credential
    setup :create_socket_and_run

    test "fetch:plan success", %{
      socket: socket,
      run: run,
      workflow: workflow,
      credential: credential
    } do
      id = run.id
      ref = push(socket, "fetch:plan", %{})

      # { id, triggers, jobs, edges, options ...etc }
      assert_reply ref, :ok, payload

      triggers =
        workflow.triggers
        |> Enum.map(&Map.take(&1, [:id]))
        |> Enum.map(&stringify_keys/1)

      [job] = workflow.jobs

      jobs =
        [
          %{
            "id" => job.id,
            "name" => job.name,
            "body" => job.body,
            "credential_id" => credential.id,
            "adaptor" => "@openfn/language-common@1.6.2"
          }
        ]

      edges =
        workflow.edges
        |> Enum.map(
          &(Map.take(&1, [
              :id,
              :source_trigger_id,
              :source_job_id,
              :enabled,
              :target_job_id
            ])
            |> Map.put(:condition, "state.a == 33"))
        )
        |> Enum.map(&stringify_keys/1)

      assert payload == %{
               "id" => id,
               "triggers" => triggers,
               "jobs" => jobs,
               "edges" => edges,
               "starting_node_id" => run.starting_trigger_id,
               "dataclip_id" => run.dataclip_id,
               "options" => %{output_dataclips: true}
             }
    end

    test "fetch:plan for project with erase_all retention setting", %{
      credential: credential
    } do
      project = insert(:project, retention_policy: :erase_all)

      workflow_context =
        create_workflow(%{project: project, credential: credential})

      %{run: run, workflow: workflow} =
        create_run(
          %{project: project, credential: credential}
          |> Map.merge(workflow_context)
        )

      %{socket: socket} = create_socket(%{run: run})

      id = run.id
      ref = push(socket, "fetch:plan", %{})

      assert_reply ref, :ok, payload

      triggers =
        workflow.triggers
        |> Enum.map(&Map.take(&1, [:id]))
        |> Enum.map(&stringify_keys/1)

      [job] = workflow.jobs

      jobs =
        [
          %{
            "id" => job.id,
            "name" => job.name,
            "body" => job.body,
            "credential_id" => credential.id,
            "adaptor" => "@openfn/language-common@1.6.2"
          }
        ]

      edges =
        workflow.edges
        |> Enum.map(
          &(Map.take(&1, [
              :id,
              :source_trigger_id,
              :source_job_id,
              :enabled,
              :target_job_id
            ])
            |> Map.put(:condition, "state.a == 33"))
        )
        |> Enum.map(&stringify_keys/1)

      assert payload == %{
               "id" => id,
               "triggers" => triggers,
               "jobs" => jobs,
               "edges" => edges,
               "starting_node_id" => run.starting_trigger_id,
               "dataclip_id" => run.dataclip_id,
               "options" => %{output_dataclips: false}
             }
    end

    test "fetch:plan includes options from usage limiter", %{
      credential: credential
    } do
      project = insert(:project, retention_policy: :erase_all)

      workflow_context =
        create_workflow(%{project: project, credential: credential})

      %{run: run} =
        create_run(
          %{project: project, credential: credential}
          |> Map.merge(workflow_context)
        )

      %{socket: socket} = create_socket(%{run: run})
      project_id = project.id

      extra_options = [run_timeout_ms: 5000]

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :get_run_options,
        fn %{project_id: ^project_id} -> extra_options end
      )

      ref = push(socket, "fetch:plan", %{})

      assert_reply ref, :ok, payload

      expected_options =
        Map.merge(%{output_dataclips: false}, Map.new(extra_options))

      assert match?(%{"options" => ^expected_options}, payload)
    end

    test "fetch:dataclip handles all types", %{
      socket: socket,
      dataclip: dataclip
    } do
      ref = push(socket, "fetch:dataclip", %{})

      assert_reply ref,
                   :ok,
                   {:binary,
                    ~s<{"data": {"foo": "bar"}, "request": {"headers": {"content-type": "application/json"}}}>}

      Ecto.Changeset.change(dataclip, type: :step_result)
      |> Repo.update()

      ref = push(socket, "fetch:dataclip", %{})

      assert_reply ref, :ok, {:binary, ~s<{"foo": "bar"}>}

      Ecto.Changeset.change(dataclip, type: :saved_input)
      |> Repo.update()

      ref = push(socket, "fetch:dataclip", %{})

      assert_reply ref, :ok, {:binary, ~s<{"foo": "bar"}>}

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      dataclip
      |> Ecto.Changeset.change(body: nil, wiped_at: now)
      |> Repo.update()

      ref = push(socket, "fetch:dataclip", %{})
      assert_reply ref, :ok, {:binary, "null"}
    end

    @tag project_retention_policy: :erase_all
    test "fetch:dataclip wipes dataclip body for projects with erase_all retention policy",
         context do
      %{dataclip: dataclip, socket: socket} = context

      ref = push(socket, "fetch:dataclip", %{})

      assert_reply ref, :ok, {:binary, _payload}

      updated_dataclip = get_dataclip_with_body(dataclip.id)

      # dataclip body is cleared
      assert updated_dataclip.wiped_at ==
               DateTime.utc_now() |> DateTime.truncate(:second)

      refute updated_dataclip.body
    end

    @tag project_retention_policy: :retain_all
    test "fetch:dataclip wipes dataclip body for projects with retain_all retention policy",
         context do
      # retain_all
      %{run: run, dataclip: dataclip} = create_run(context)

      %{socket: socket} = create_socket(%{run: run})

      ref = push(socket, "fetch:dataclip", %{})

      assert_reply ref, :ok, {:binary, _payload}

      # dataclip body is not cleared
      dataclip_query = from(Dataclip, select: [:wiped_at, :body, :request])
      updated_dataclip = Lightning.Repo.get(dataclip_query, dataclip.id)
      refute updated_dataclip.wiped_at
      assert updated_dataclip.body
    end

    test "fetch:credential", %{socket: socket, credential: credential} do
      bypass = Bypass.open()

      wellknown_url = "http://localhost:#{bypass.port}/auth/.well-known"

      Lightning.ApplicationHelpers.put_temporary_env(:lightning, :oauth_clients,
        google: [
          client_id: "foo",
          client_secret: "bar",
          wellknown_url: wellknown_url
        ]
      )

      expect_wellknown(bypass)

      new_expiry = credential.body["expires_at"] + 3600

      expect_token(
        bypass,
        Lightning.AuthProviders.Common.get_wellknown!(wellknown_url),
        Map.put(credential.body, "expires_at", new_expiry)
      )

      ref = push(socket, "fetch:credential", %{"id" => credential.id})

      assert_reply ref, :ok, %{
        "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
        "expires_at" => ^new_expiry,
        "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
        "sandbox" => false,
        "scope" => "https://www.googleapis.com/auth/spreadsheets"
      }
    end
  end

  describe "fetch:credential" do
    test "doesn't cast credential body fields" do
      user = insert(:user)

      credential =
        insert(:credential,
          name: "Test Postgres",
          body: %{
            user: "user1",
            password: "pass1",
            host: "https://dbhost",
            port: "5000",
            database: "test_db",
            ssl: "true",
            allowSelfSignedCert: "false"
          },
          schema: "postgresql",
          user: user
        )

      %{socket: socket} =
        create_socket_and_run(%{credential: credential, user: user})

      ref = push(socket, "fetch:credential", %{"id" => credential.id})

      assert_reply ref,
                   :ok,
                   %{
                     "allowSelfSignedCert" => "false",
                     "database" => "test_db",
                     "host" => "https://dbhost",
                     "password" => "pass1",
                     "port" => "5000",
                     "ssl" => "true",
                     "user" => "user1"
                   }
    end

    test "returns saved credential body" do
      user = insert(:user)

      credential =
        insert(:credential,
          name: "Test Postgres",
          body: %{
            user: "user1",
            password: "pass1",
            host: "https://dbhost",
            database: "test_db",
            port: 5000,
            ssl: true,
            allowSelfSignedCert: false
          },
          schema: "postgresql",
          user: user
        )

      %{socket: socket} =
        create_socket_and_run(%{credential: credential, user: user})

      ref = push(socket, "fetch:credential", %{"id" => credential.id})

      assert_reply ref,
                   :ok,
                   %{
                     "allowSelfSignedCert" => false,
                     "database" => "test_db",
                     "host" => "https://dbhost",
                     "password" => "pass1",
                     "port" => 5000,
                     "ssl" => true,
                     "user" => "user1"
                   }
    end
  end

  describe "marking steps as started and finished" do
    setup context do
      user = insert(:user)

      %{project: project} = create_project(%{user: user} |> Map.merge(context))

      credential =
        insert(:credential,
          name: "My Credential",
          body: %{pin: "1234"},
          user: user
        )

      %{id: project_credential_id} =
        insert(:project_credential, credential: credential, project: project)

      dataclip = insert(:dataclip, body: %{"foo" => "bar"}, project: project)

      %{triggers: [trigger], jobs: [job]} =
        workflow = insert(:simple_workflow, project: project)

      Repo.update(
        Ecto.Changeset.change(job, project_credential_id: project_credential_id)
      )

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip
        )

      Lightning.Stub.reset_time()

      {:ok, bearer, _} =
        Workers.Token.generate_and_sign(
          %{},
          Lightning.Config.worker_token_signer()
        )

      {:ok, %{}, socket} =
        LightningWeb.WorkerSocket
        |> socket("socket_id", %{token: bearer})
        |> subscribe_and_join(
          LightningWeb.RunChannel,
          "run:#{run.id}",
          %{"token" => Workers.generate_run_token(run)}
        )

      %{
        socket: socket,
        run: run,
        user: user,
        workflow: workflow,
        credential: credential,
        project: project,
        trigger: trigger
      }
    end

    test "step:start", %{
      socket: socket,
      run: %{dataclip_id: dataclip_id},
      workflow: workflow,
      credential: %{id: credential_id},
      project: project
    } do
      # { id, job_id, input_dataclip_id }
      step_id = Ecto.UUID.generate()
      [%{id: job_id}] = workflow.jobs

      ref =
        push(socket, "step:start", %{
          "step_id" => step_id,
          "credential_id" => credential_id,
          "job_id" => job_id,
          "input_dataclip_id" => dataclip_id
        })

      assert_reply ref, :ok, %{step_id: ^step_id}, 1_000

      assert project.retention_policy == :retain_all

      assert %{
               credential_id: ^credential_id,
               job_id: ^job_id,
               input_dataclip_id: ^dataclip_id
             } =
               Repo.get!(Step, step_id)
    end

    @tag project_retention_policy: :erase_all
    test "step:start for a project with erase_all retention policy",
         %{
           credential: %{id: credential_id},
           project: project,
           workflow: workflow
         } = context do
      %{socket: socket, run: %{dataclip_id: dataclip_id}} = context
      # input dataclip is saved if provided by the worker
      assert project.retention_policy == :erase_all

      step_id = Ecto.UUID.generate()
      [%{id: job_id}] = workflow.jobs

      ref =
        push(socket, "step:start", %{
          "step_id" => step_id,
          "credential_id" => credential_id,
          "job_id" => job_id,
          "input_dataclip_id" => dataclip_id
        })

      assert_reply ref, :ok, %{step_id: ^step_id}

      assert %{
               credential_id: ^credential_id,
               job_id: ^job_id,
               input_dataclip_id: ^dataclip_id
             } =
               Repo.get!(Step, step_id),
             "dataclip is saved if provided"

      %{run: run} = create_run(context)
      %{socket: socket} = create_socket(%{context | run: run})

      step_id = Ecto.UUID.generate()
      [%{id: job_id}] = workflow.jobs

      ref =
        push(socket, "step:start", %{
          "step_id" => step_id,
          "credential_id" => credential_id,
          "job_id" => job_id
        })

      assert_reply ref, :ok, %{step_id: ^step_id}

      assert %{
               credential_id: ^credential_id,
               job_id: ^job_id,
               input_dataclip_id: nil
             } = Repo.get!(Step, step_id)
    end

    test "step:complete succeeds with normal reason", %{
      socket: socket,
      run: run,
      workflow: workflow
    } do
      [job] = workflow.jobs
      %{id: step_id} = step = insert(:step, runs: [run], job: job)

      ref =
        push(socket, "step:complete", %{
          "step_id" => step.id,
          "output_dataclip_id" => Ecto.UUID.generate(),
          "output_dataclip" => ~s({"foo": "bar"}),
          "reason" => "normal"
        })

      assert_reply ref, :ok, %{step_id: ^step_id}
      assert %{exit_reason: "normal"} = Repo.get(Step, step.id)
    end

    test "step:complete succeeds preserving present tense reason", %{
      socket: socket,
      run: run,
      workflow: workflow
    } do
      [job] = workflow.jobs
      %{id: step_id} = step = insert(:step, runs: [run], job: job)

      ref =
        push(socket, "step:complete", %{
          "step_id" => step.id,
          "output_dataclip_id" => Ecto.UUID.generate(),
          "output_dataclip" => ~s({"foo": "bar"}),
          "reason" => "fail"
        })

      assert_reply ref, :ok, %{step_id: ^step_id}
      assert %{exit_reason: "fail"} = Repo.get(Step, step.id)
    end

    @tag project_retention_policy: :retain_all
    test "step:complete saves the dataclip if project retention policy is set to retain_all",
         context do
      %{socket: socket, run: run, workflow: workflow, project: project} = context

      assert project.retention_policy == :retain_all
      [job] = workflow.jobs
      %{id: step_id} = insert(:step, runs: [run], job: job)
      dataclip_id = Ecto.UUID.generate()

      ref =
        push(socket, "step:complete", %{
          "step_id" => step_id,
          "output_dataclip_id" => dataclip_id,
          "output_dataclip" => ~s({"foo": "bar"}),
          "reason" => "normal"
        })

      assert_reply ref, :ok, %{step_id: ^step_id}

      # dataclip is saved
      assert %{output_dataclip_id: ^dataclip_id} = Repo.get(Step, step_id)
      assert dataclip = get_dataclip_with_body(dataclip_id)
      assert dataclip.body, "body is not wiped"
      assert is_nil(dataclip.wiped_at)
    end

    @tag project_retention_policy: :erase_all
    test "step:complete saves the dataclip but wipes it if project retention policy is set to erase_all",
         context do
      %{socket: socket, run: run, workflow: workflow, project: project} = context

      # dataclip is saved but wiped
      assert project.retention_policy == :erase_all

      [job] = workflow.jobs
      %{id: step_id} = insert(:step, runs: [run], job: job)
      dataclip_id = Ecto.UUID.generate()

      ref =
        push(socket, "step:complete", %{
          "step_id" => step_id,
          "output_dataclip_id" => dataclip_id,
          "output_dataclip" => ~s({"foo": "bar"}),
          "reason" => "normal"
        })

      assert_reply ref, :ok, %{step_id: ^step_id}

      assert %{output_dataclip_id: ^dataclip_id} = Repo.get(Step, step_id)
      assert dataclip = get_dataclip_with_body(dataclip_id)
      assert is_nil(dataclip.body), "body is wiped"
      assert is_struct(dataclip.wiped_at, DateTime)

      %{run: run} = create_run(context)
      %{socket: socket} = create_socket(%{run: run})

      [job] = workflow.jobs
      %{id: step_id} = insert(:step, runs: [run], job: job)
      dataclip_id = Ecto.UUID.generate()

      # do not include output_dataclip_id
      ref =
        push(socket, "step:complete", %{
          "step_id" => step_id,
          "output_dataclip" => ~s({"foo": "bar"}),
          "reason" => "normal"
        })

      assert_reply ref, :ok, %{step_id: ^step_id}

      assert %{output_dataclip_id: nil} = Repo.get(Step, step_id)
      refute get_dataclip_with_body(dataclip_id)
    end
  end

  describe "logging" do
    setup do
      project = insert(:project)
      dataclip = insert(:dataclip, body: %{"foo" => "bar"}, project: project)

      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow, project: project)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip
        )

      Lightning.Stub.reset_time()

      {:ok, bearer, _} =
        Workers.Token.generate_and_sign(
          %{},
          Lightning.Config.worker_token_signer()
        )

      {:ok, %{}, socket} =
        LightningWeb.WorkerSocket
        |> socket("socket_id", %{token: bearer})
        |> subscribe_and_join(
          LightningWeb.RunChannel,
          "run:#{run.id}",
          %{"token" => Workers.generate_run_token(run)}
        )

      %{socket: socket, run: run, workflow: workflow}
    end

    test "run:log missing message can't be blank", %{
      socket: socket,
      run: run,
      workflow: workflow
    } do
      step_id = Ecto.UUID.generate()
      [job] = workflow.jobs

      ref =
        push(socket, "step:start", %{
          "step_id" => step_id,
          "job_id" => job.id,
          "input_dataclip_id" => run.dataclip_id
        })

      assert_reply ref, :ok, _

      ref =
        push(socket, "run:log", %{
          # we expect a 16 character string for microsecond resolution
          "timestamp" => "1699444653874088"
        })

      assert_reply ref, :error, errors

      assert errors == %{message: ["This field can't be blank."]}
    end

    test "run:log message can't be nil", %{
      socket: socket,
      run: run,
      workflow: workflow
    } do
      # { id, job_id, input_dataclip_id }
      step_id = Ecto.UUID.generate()
      [job] = workflow.jobs

      ref =
        push(socket, "step:start", %{
          "step_id" => step_id,
          "job_id" => job.id,
          "input_dataclip_id" => run.dataclip_id
        })

      assert_reply ref, :ok, _

      ref =
        push(socket, "run:log", %{
          # we expect a 16 character string for microsecond resolution
          "timestamp" => "1699444653874088",
          "message" => nil
        })

      assert_reply ref, :error, errors

      assert errors == %{message: ["This field can't be blank."]}

      ref =
        push(socket, "run:log", %{
          # we expect a 16 character string for microsecond resolution
          "timestamp" => "1699444653874088",
          "message" => [nil]
        })

      assert_reply ref, :error, errors

      assert errors == %{message: ["This field can't be blank."]}
    end

    test "run:log timestamp is handled at microsecond resolution", %{
      socket: socket,
      run: run,
      workflow: workflow
    } do
      step_id = Ecto.UUID.generate()
      [job] = workflow.jobs

      ref =
        push(socket, "step:start", %{
          "step_id" => step_id,
          "job_id" => job.id,
          "input_dataclip_id" => run.dataclip_id
        })

      assert_reply ref, :ok, _

      ref =
        push(socket, "run:log", %{
          "level" => "debug",
          "message" => ["Intialising pipeline"],
          "source" => "R/T",
          "timestamp" => "1699444653874083"
        })

      assert_reply ref, :ok, _

      persisted_log_line = Lightning.Repo.one(Lightning.Invocation.LogLine)
      assert persisted_log_line.timestamp == ~U[2023-11-08 11:57:33.874083Z]
    end
  end

  describe "marking runs as started and finished" do
    setup context do
      run_state = Map.get(context, :run_state, :available)

      project = insert(:project)
      dataclip = insert(:http_request_dataclip, project: project)

      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow, project: project)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: run_state
        )

      Lightning.Stub.reset_time()

      {:ok, bearer, _} =
        Workers.Token.generate_and_sign(
          %{},
          Lightning.Config.worker_token_signer()
        )

      {:ok, %{}, socket} =
        LightningWeb.WorkerSocket
        |> socket("socket_id", %{token: bearer})
        |> subscribe_and_join(
          LightningWeb.RunChannel,
          "run:#{run.id}",
          %{"token" => Workers.generate_run_token(run)}
        )

      %{
        socket: socket,
        run: run,
        workflow: workflow,
        work_order: work_order
      }
    end

    @tag run_state: :claimed
    test "run:start", %{
      socket: socket,
      run: run,
      work_order: work_order
    } do
      ref = push(socket, "run:start", %{})

      assert_reply ref, :ok, nil

      assert %{state: :started} = Lightning.Repo.reload!(run)
      assert %{state: :running} = Lightning.Repo.reload!(work_order)
    end

    @tag run_state: :claimed
    test "run:complete when claimed", %{socket: socket} do
      ref =
        push(socket, "run:complete", %{
          "reason" => "success",
          "error_type" => nil,
          "error_message" => nil
        })

      assert_reply ref, :ok, nil

      ref =
        push(socket, "run:complete", %{
          "reason" => "failed",
          "error_type" => nil,
          "error_message" => nil
        })

      assert_reply ref, :error, errors

      assert errors == %{
               state: ["already in completed state"]
             }
    end

    @tag run_state: :started
    test "run:complete when started", %{
      socket: socket,
      run: run,
      work_order: work_order
    } do
      ref =
        push(socket, "run:complete", %{
          "reason" => "success",
          "error_type" => nil,
          "error_message" => nil
        })

      assert_reply ref, :ok, nil

      assert %{state: :success} = Lightning.Repo.reload!(run)
      assert %{state: :success} = Lightning.Repo.reload!(work_order)
    end

    @tag run_state: :started
    test "run:complete when started and cancelled", %{
      socket: socket,
      run: run,
      work_order: work_order
    } do
      ref =
        push(socket, "run:complete", %{
          "reason" => "cancel",
          "error_type" => nil,
          "error_message" => nil
        })

      assert_reply ref, :ok, nil

      assert %{state: :cancelled} = Lightning.Repo.reload!(run)
      assert %{state: :cancelled} = Lightning.Repo.reload!(work_order)
    end

    @tag run_state: :started
    test "run:complete when started and fails", %{
      socket: socket,
      run: run,
      work_order: work_order
    } do
      ref =
        push(socket, "run:complete", %{
          "reason" => "fail",
          "error_type" => "UserError",
          "error_message" => nil
        })

      assert_reply ref, :ok, nil

      assert %{state: :failed} = Lightning.Repo.reload!(run)
      assert %{state: :failed} = Lightning.Repo.reload!(work_order)
    end

    @tag run_state: :started
    test "run:complete when started and crashes", %{
      socket: socket,
      run: run,
      work_order: work_order
    } do
      ref =
        push(socket, "run:complete", %{
          "reason" => "crash",
          "error_type" => "RuntimeCrash",
          "error_message" => nil
        })

      assert_reply ref, :ok, nil

      assert %{state: :crashed} = Lightning.Repo.reload!(run)
      assert %{state: :crashed} = Lightning.Repo.reload!(work_order)
    end

    @tag run_state: :started
    test "run:complete when started and gets a kill", %{
      socket: socket,
      run: run,
      work_order: work_order
    } do
      ref =
        push(socket, "run:complete", %{
          "reason" => "kill",
          "error_type" => "TimeoutError",
          "error_message" => nil
        })

      assert_reply ref, :ok, nil

      assert %{state: :killed} = Lightning.Repo.reload!(run)
      assert %{state: :killed} = Lightning.Repo.reload!(work_order)
    end
  end

  defp create_socket_and_run(context) do
    [&create_project/1, &create_workflow/1, &create_run/1, &create_socket/1]
    |> Enum.reduce(context, fn f, context ->
      Map.merge(context, f.(context))
    end)
  end

  defp create_project(%{user: user} = context) do
    %{
      project:
        insert(:project,
          project_users: [%{user: user}],
          retention_policy: fn ->
            context[:project_retention_policy] ||
              %Lightning.Projects.Project{}.retention_policy
          end
        )
    }
  end

  defp create_workflow(context) do
    assert_context_keys(context, [:project, :credential])

    %{credential: credential, project: project} = context
    trigger = build(:trigger, type: :webhook, enabled: true)

    job =
      build(:job,
        body: ~s[fn(state => { return {...state, extra: "data"} })],
        project_credential: %{credential: credential}
      )

    workflow =
      %{triggers: [trigger]} =
      build(:workflow, project: project)
      |> with_trigger(trigger)
      |> with_job(job)
      |> with_edge({trigger, job}, %{
        condition_type: :js_expression,
        condition_expression: "state.a == 33"
      })
      |> insert()

    %{workflow: workflow, job: job, trigger: trigger}
  end

  defp create_run(context) do
    assert_context_keys(context, [:project, :credential, :workflow, :trigger])

    %{
      project: project,
      credential: credential,
      workflow: workflow,
      trigger: trigger
    } = context

    dataclip =
      insert(:http_request_dataclip, project: project)

    work_order =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip
      )

    run =
      insert(:run,
        work_order: work_order,
        starting_trigger: trigger,
        dataclip: dataclip
      )

    %{
      run: run,
      workflow: workflow,
      credential: credential,
      dataclip: dataclip
    }
  end

  defp create_socket(%{run: run}) do
    Lightning.Stub.reset_time()

    {:ok, bearer, _} =
      Workers.Token.generate_and_sign(
        %{},
        Lightning.Config.worker_token_signer()
      )

    {:ok, %{}, socket} =
      LightningWeb.WorkerSocket
      |> socket("socket_id", %{token: bearer})
      |> subscribe_and_join(
        LightningWeb.RunChannel,
        "run:#{run.id}",
        %{"token" => Workers.generate_run_token(run)}
      )

    %{socket: socket}
  end

  defp stringify_keys(map) do
    Enum.map(map, fn {k, v} -> {Atom.to_string(k), v} end)
    |> Enum.into(%{})
  end

  defp set_google_credential(_context) do
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(-299, :second)
      |> DateTime.to_unix()

    credential_body = %{
      "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
      "expires_at" => expires_at,
      "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
      "scope" => "https://www.googleapis.com/auth/spreadsheets"
    }

    user = insert(:user)

    credential =
      insert(:credential,
        name: "Test Googlesheets Credential",
        user: user,
        body: credential_body,
        schema: "googlesheets"
      )

    {:ok, credential: credential, user: user}
  end

  defp get_dataclip_with_body(dataclip_id) do
    from(d in Dataclip, select: %{d | body: d.body})
    |> Repo.get(dataclip_id)
  end
end
