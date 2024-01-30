defmodule LightningWeb.AttemptChannelTest do
  use LightningWeb.ChannelCase

  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Step
  alias Lightning.Workers

  import Ecto.Query
  import Lightning.Factories
  import Lightning.BypassHelpers

  describe "joining" do
    test "without providing a token" do
      assert LightningWeb.UserSocket
             |> socket("socket_id", %{})
             |> subscribe_and_join(LightningWeb.WorkerChannel, "worker:queue") ==
               {:error, %{reason: "unauthorized"}}
    end
  end

  describe "joining the attempt:* channel" do
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
               |> subscribe_and_join(LightningWeb.AttemptChannel, "attempt:123")

      assert {:error, %{reason: "unauthorized"}} =
               socket
               |> subscribe_and_join(
                 LightningWeb.AttemptChannel,
                 "attempt:123",
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
          Lightning.Config.attempt_token_signer()
        )

      Lightning.Stub.freeze_time(DateTime.utc_now())

      assert {:error, %{reason: "unauthorized"}} =
               socket
               |> subscribe_and_join(
                 LightningWeb.AttemptChannel,
                 "attempt:123",
                 %{"token" => bearer}
               )

      # A valid token, but the id doesn't match the channel name
      id = Ecto.UUID.generate()
      other_id = Ecto.UUID.generate()

      bearer = Workers.generate_attempt_token(%{id: id})

      assert {:error, %{reason: "unauthorized"}} =
               socket
               |> subscribe_and_join(
                 LightningWeb.AttemptChannel,
                 "attempt:#{other_id}",
                 %{"token" => bearer}
               )
    end

    test "joining with a valid token but attempt is not found", %{socket: socket} do
      id = Ecto.UUID.generate()

      bearer =
        Workers.generate_attempt_token(%{id: id})

      assert {:error, %{reason: "not_found"}} =
               socket
               |> subscribe_and_join(
                 LightningWeb.AttemptChannel,
                 "attempt:#{id}",
                 %{"token" => bearer}
               )
    end
  end

  describe "fetching attempt data" do
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

    setup :set_google_credential
    setup :create_socket_and_attempt

    test "fetch:attempt", %{
      socket: socket,
      attempt: attempt,
      workflow: workflow,
      credential: credential
    } do
      id = attempt.id
      ref = push(socket, "fetch:attempt", %{})

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
               "starting_node_id" => attempt.starting_trigger_id,
               "dataclip_id" => attempt.dataclip_id,
               "options" => %LightningWeb.RunOptions{output_dataclips: true}
             }
    end

    test "fetch:attempt for project with erase_all retention setting", %{
      credential: credential
    } do
      project = insert(:project, retention_policy: :erase_all)

      %{attempt: attempt, workflow: workflow} =
        create_attempt(%{project: project, credential: credential})

      %{socket: socket} = create_socket(%{attempt: attempt})

      id = attempt.id
      ref = push(socket, "fetch:attempt", %{})

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
               "starting_node_id" => attempt.starting_trigger_id,
               "dataclip_id" => attempt.dataclip_id,
               "options" => %LightningWeb.RunOptions{output_dataclips: false}
             }
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
    end

    test "fetch:dataclip wipes dataclip body for projects with erase_all retention policy",
         %{
           credential: credential
         } do
      # erase_all
      project = insert(:project, retention_policy: :erase_all)

      %{attempt: attempt, dataclip: dataclip} =
        create_attempt(%{project: project, credential: credential})

      %{socket: socket} = create_socket(%{attempt: attempt})

      ref = push(socket, "fetch:dataclip", %{})

      assert_reply ref, :ok, {:binary, _payload}

      # dataclip body is cleared
      dataclip_query = from(Dataclip, select: [:wiped_at, :body, :request])
      updated_dataclip = Lightning.Repo.get(dataclip_query, dataclip.id)

      assert updated_dataclip.wiped_at ==
               DateTime.utc_now() |> DateTime.truncate(:second)

      refute updated_dataclip.body

      # retain_all
      project = insert(:project, retention_policy: :retain_all)

      %{attempt: attempt, dataclip: dataclip} =
        create_attempt(%{project: project, credential: credential})

      %{socket: socket} = create_socket(%{attempt: attempt})

      ref = push(socket, "fetch:dataclip", %{})

      assert_reply ref, :ok, {:binary, _payload}

      # dataclip body is not cleared
      updated_dataclip = Lightning.Repo.get(dataclip_query, dataclip.id)
      refute updated_dataclip.wiped_at
      assert updated_dataclip.body
    end

    test "fetch:credential", %{socket: socket, credential: credential} do
      bypass = Bypass.open()

      Lightning.ApplicationHelpers.put_temporary_env(:lightning, :oauth_clients,
        google: [
          client_id: "foo",
          client_secret: "bar",
          wellknown_url: "http://localhost:#{bypass.port}/auth/.well-known"
        ]
      )

      expect_wellknown(bypass)

      new_expiry = credential.body["expires_at"] + 3600

      expect_token(
        bypass,
        Lightning.AuthProviders.Google.get_wellknown!(),
        Map.put(credential.body, "expires_at", new_expiry)
      )

      ref = push(socket, "fetch:credential", %{"id" => credential.id})

      assert_reply ref, :ok, %{
        "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
        "expires_at" => ^new_expiry,
        "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
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
        create_socket_and_attempt(%{credential: credential, user: user})

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
        create_socket_and_attempt(%{credential: credential, user: user})

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
    setup do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user_id: user.id}])

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

      attempt =
        insert(:attempt,
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
          LightningWeb.AttemptChannel,
          "attempt:#{attempt.id}",
          %{"token" => Workers.generate_attempt_token(attempt)}
        )

      %{
        socket: socket,
        attempt: attempt,
        user: user,
        workflow: workflow,
        credential: credential,
        project: project
      }
    end

    test "step:start", %{
      socket: socket,
      attempt: %{dataclip_id: dataclip_id},
      workflow: workflow,
      credential: %{id: credential_id} = credential,
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

      # input dataclip is not saved for projects with erase_all
      project = insert(:project, retention_policy: :erase_all)

      %{attempt: attempt, workflow: workflow} =
        create_attempt(%{project: project, credential: credential})

      %{socket: socket} = create_socket(%{attempt: attempt})

      step_id = Ecto.UUID.generate()
      [%{id: job_id}] = workflow.jobs

      ref =
        push(socket, "step:start", %{
          "step_id" => step_id,
          "credential_id" => credential_id,
          "job_id" => job_id,
          "input_dataclip_id" => attempt.dataclip_id
        })

      assert_reply ref, :ok, %{step_id: ^step_id}

      assert project.retention_policy == :erase_all

      assert %{
               credential_id: ^credential_id,
               job_id: ^job_id,
               input_dataclip_id: nil
             } =
               Repo.get!(Step, step_id)
    end

    test "run:start is converted to step:start for old workers", %{
      socket: socket,
      attempt: attempt,
      workflow: workflow,
      credential: %{id: credential_id}
    } do
      # { id, job_id, input_dataclip_id }
      step_id = Ecto.UUID.generate()
      [%{id: job_id}] = workflow.jobs

      ref =
        push(socket, "run:start", %{
          "run_id" => step_id,
          "credential_id" => credential_id,
          "job_id" => job_id,
          "input_dataclip_id" => attempt.dataclip_id
        })

      assert_reply ref, :ok, %{step_id: ^step_id}, 1_000

      assert %{credential_id: ^credential_id, job_id: ^job_id} =
               Repo.get!(Step, step_id)
    end

    test "run:complete is converted to step:complete for old workers", %{
      socket: socket,
      attempt: attempt,
      workflow: workflow
    } do
      [job] = workflow.jobs
      %{id: step_id} = step = insert(:step, attempts: [attempt], job: job)

      ref =
        push(socket, "run:complete", %{
          "run_id" => step.id,
          "output_dataclip_id" => Ecto.UUID.generate(),
          "output_dataclip" => ~s({"foo": "bar"}),
          "reason" => "normal"
        })

      assert_reply ref, :ok, %{step_id: ^step_id}
      assert %{exit_reason: "normal"} = Repo.get(Step, step.id)
    end

    test "step:complete succeeds with normal reason", %{
      socket: socket,
      attempt: attempt,
      workflow: workflow
    } do
      [job] = workflow.jobs
      %{id: step_id} = step = insert(:step, attempts: [attempt], job: job)

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
      attempt: attempt,
      workflow: workflow
    } do
      [job] = workflow.jobs
      %{id: step_id} = step = insert(:step, attempts: [attempt], job: job)

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

    test "step:complete does not save the dataclip if project retention policy is set to erase_all",
         %{
           socket: socket,
           attempt: attempt,
           workflow: workflow,
           project: project,
           credential: credential
         } do
      [job] = workflow.jobs
      %{id: step_id} = insert(:step, attempts: [attempt], job: job)
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
      assert project.retention_policy == :retain_all
      assert %{output_dataclip_id: ^dataclip_id} = Repo.get(Step, step_id)
      assert Repo.get(Dataclip, dataclip_id)

      # project with erase_all
      project = insert(:project, retention_policy: :erase_all)

      %{attempt: attempt, workflow: workflow} =
        create_attempt(%{project: project, credential: credential})

      %{socket: socket} = create_socket(%{attempt: attempt})

      [job] = workflow.jobs
      %{id: step_id} = insert(:step, attempts: [attempt], job: job)
      dataclip_id = Ecto.UUID.generate()

      ref =
        push(socket, "step:complete", %{
          "step_id" => step_id,
          "output_dataclip_id" => dataclip_id,
          "output_dataclip" => ~s({"foo": "bar"}),
          "reason" => "normal"
        })

      assert_reply ref, :ok, %{step_id: ^step_id}

      # dataclip is NOT saved
      assert project.retention_policy == :erase_all
      assert %{output_dataclip_id: nil} = Repo.get(Step, step_id)
      refute Repo.get(Dataclip, dataclip_id)
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

      attempt =
        insert(:attempt,
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
          LightningWeb.AttemptChannel,
          "attempt:#{attempt.id}",
          %{"token" => Workers.generate_attempt_token(attempt)}
        )

      %{socket: socket, attempt: attempt, workflow: workflow}
    end

    test "attempt:log missing message can't be blank", %{
      socket: socket,
      attempt: attempt,
      workflow: workflow
    } do
      # { id, job_id, input_dataclip_id }
      step_id = Ecto.UUID.generate()
      [job] = workflow.jobs

      ref =
        push(socket, "step:start", %{
          "step_id" => step_id,
          "job_id" => job.id,
          "input_dataclip_id" => attempt.dataclip_id
        })

      assert_reply ref, :ok, _

      ref =
        push(socket, "attempt:log", %{
          # we expect a 16 character string for microsecond resolution
          "timestamp" => "1699444653874088"
        })

      assert_reply ref, :error, errors

      assert errors == %{message: ["This field can't be blank."]}
    end

    test "attempt:log message can't be nil", %{
      socket: socket,
      attempt: attempt,
      workflow: workflow
    } do
      # { id, job_id, input_dataclip_id }
      step_id = Ecto.UUID.generate()
      [job] = workflow.jobs

      ref =
        push(socket, "step:start", %{
          "step_id" => step_id,
          "job_id" => job.id,
          "input_dataclip_id" => attempt.dataclip_id
        })

      assert_reply ref, :ok, _

      ref =
        push(socket, "attempt:log", %{
          # we expect a 16 character string for microsecond resolution
          "timestamp" => "1699444653874088",
          "message" => nil
        })

      assert_reply ref, :error, errors

      assert errors == %{message: ["This field can't be blank."]}
    end

    test "attempt:log message can't be [nil]", %{
      socket: socket,
      attempt: attempt,
      workflow: workflow
    } do
      # { id, job_id, input_dataclip_id }
      step_id = Ecto.UUID.generate()
      [job] = workflow.jobs

      ref =
        push(socket, "step:start", %{
          "step_id" => step_id,
          "job_id" => job.id,
          "input_dataclip_id" => attempt.dataclip_id
        })

      assert_reply ref, :ok, _

      ref =
        push(socket, "attempt:log", %{
          # we expect a 16 character string for microsecond resolution
          "timestamp" => "1699444653874088",
          "message" => [nil]
        })

      assert_reply ref, :error, errors

      assert errors == %{message: ["This field can't be blank."]}
    end

    test "attempt:log timestamp is handled at microsecond resolution", %{
      socket: socket,
      attempt: attempt,
      workflow: workflow
    } do
      # { id, job_id, input_dataclip_id }
      step_id = Ecto.UUID.generate()
      [job] = workflow.jobs

      ref =
        push(socket, "step:start", %{
          "step_id" => step_id,
          "job_id" => job.id,
          "input_dataclip_id" => attempt.dataclip_id
        })

      assert_reply ref, :ok, _

      ref =
        push(socket, "attempt:log", %{
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

  describe "marking attempts as started and finished" do
    setup context do
      attempt_state = Map.get(context, :attempt_state, :available)

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

      attempt =
        insert(:attempt,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: attempt_state
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
          LightningWeb.AttemptChannel,
          "attempt:#{attempt.id}",
          %{"token" => Workers.generate_attempt_token(attempt)}
        )

      %{
        socket: socket,
        attempt: attempt,
        workflow: workflow,
        work_order: work_order
      }
    end

    @tag attempt_state: :claimed
    test "attempt:start", %{
      socket: socket,
      attempt: attempt,
      work_order: work_order
    } do
      ref = push(socket, "attempt:start", %{})

      assert_reply ref, :ok, nil

      assert %{state: :started} = Lightning.Repo.reload!(attempt)
      assert %{state: :running} = Lightning.Repo.reload!(work_order)
    end

    @tag attempt_state: :claimed
    test "attempt:complete when claimed", %{socket: socket} do
      ref =
        push(socket, "attempt:complete", %{
          "reason" => "success",
          "error_type" => nil,
          "error_message" => nil
        })

      assert_reply ref, :ok, nil

      ref =
        push(socket, "attempt:complete", %{
          "reason" => "failed",
          "error_type" => nil,
          "error_message" => nil
        })

      assert_reply ref, :error, errors

      assert errors == %{
               state: ["already in completed state"]
             }
    end

    @tag attempt_state: :started
    test "attempt:complete when started", %{
      socket: socket,
      attempt: attempt,
      work_order: work_order
    } do
      ref =
        push(socket, "attempt:complete", %{
          "reason" => "success",
          "error_type" => nil,
          "error_message" => nil
        })

      assert_reply ref, :ok, nil

      assert %{state: :success} = Lightning.Repo.reload!(attempt)
      assert %{state: :success} = Lightning.Repo.reload!(work_order)
    end

    @tag attempt_state: :started
    test "attempt:complete when started and cancelled", %{
      socket: socket,
      attempt: attempt,
      work_order: work_order
    } do
      ref =
        push(socket, "attempt:complete", %{
          "reason" => "cancel",
          "error_type" => nil,
          "error_message" => nil
        })

      assert_reply ref, :ok, nil

      assert %{state: :cancelled} = Lightning.Repo.reload!(attempt)
      assert %{state: :cancelled} = Lightning.Repo.reload!(work_order)
    end

    @tag attempt_state: :started
    test "attempt:complete when started and fails", %{
      socket: socket,
      attempt: attempt,
      work_order: work_order
    } do
      ref =
        push(socket, "attempt:complete", %{
          "reason" => "fail",
          "error_type" => "UserError",
          "error_message" => nil
        })

      assert_reply ref, :ok, nil

      assert %{state: :failed} = Lightning.Repo.reload!(attempt)
      assert %{state: :failed} = Lightning.Repo.reload!(work_order)
    end

    @tag attempt_state: :started
    test "attempt:complete when started and crashes", %{
      socket: socket,
      attempt: attempt,
      work_order: work_order
    } do
      ref =
        push(socket, "attempt:complete", %{
          "reason" => "crash",
          "error_type" => "RuntimeCrash",
          "error_message" => nil
        })

      assert_reply ref, :ok, nil

      assert %{state: :crashed} = Lightning.Repo.reload!(attempt)
      assert %{state: :crashed} = Lightning.Repo.reload!(work_order)
    end

    @tag attempt_state: :started
    test "attempt:complete when started and gets a kill", %{
      socket: socket,
      attempt: attempt,
      work_order: work_order
    } do
      ref =
        push(socket, "attempt:complete", %{
          "reason" => "kill",
          "error_type" => "TimeoutError",
          "error_message" => nil
        })

      assert_reply ref, :ok, nil

      assert %{state: :killed} = Lightning.Repo.reload!(attempt)
      assert %{state: :killed} = Lightning.Repo.reload!(work_order)
    end
  end

  defp create_socket_and_attempt(%{credential: credential, user: user}) do
    project = insert(:project, project_users: [%{user: user}])

    attempt_result = create_attempt(%{project: project, credential: credential})

    socket_result = create_socket(attempt_result)

    Map.merge(attempt_result, socket_result)
  end

  defp create_attempt(%{project: project, credential: credential}) do
    dataclip =
      insert(:http_request_dataclip, project: project)

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

    work_order =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip
      )

    attempt =
      insert(:attempt,
        work_order: work_order,
        starting_trigger: trigger,
        dataclip: dataclip
      )

    %{
      attempt: attempt,
      workflow: workflow,
      credential: credential,
      dataclip: dataclip
    }
  end

  defp create_socket(%{attempt: attempt}) do
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
        LightningWeb.AttemptChannel,
        "attempt:#{attempt.id}",
        %{"token" => Workers.generate_attempt_token(attempt)}
      )

    %{socket: socket}
  end

  defp stringify_keys(map) do
    Enum.map(map, fn {k, v} -> {Atom.to_string(k), v} end)
    |> Enum.into(%{})
  end
end
