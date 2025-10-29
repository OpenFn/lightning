defmodule LightningWeb.RunChannelTest do
  use LightningWeb.ChannelCase, async: true

  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Step
  alias Lightning.Workers
  alias Lightning.Workflows

  import Ecto.Query
  import Lightning.Factories
  import Lightning.TestUtils
  import Lightning.Utils.Maps, only: [stringify_keys: 1]

  setup do
    Mox.verify_on_exit!()

    Mox.stub(Lightning.Extensions.MockUsageLimiter, :check_limits, fn _context ->
      :ok
    end)

    Mox.stub(
      Lightning.Extensions.MockUsageLimiter,
      :limit_action,
      fn _action, _context ->
        :ok
      end
    )

    Mox.stub(Lightning.MockConfig, :default_max_run_duration, fn -> 1 end)

    :ok
  end

  describe "joining" do
    test "without providing a token" do
      assert LightningWeb.WorkerSocket
             |> socket("socket_id", %{})
             |> subscribe_and_join(LightningWeb.WorkerChannel, "worker:queue") ==
               {:error, %{reason: "unauthorized"}}
    end
  end

  describe "joining the run:* channel" do
    setup :create_socket

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
        Workers.WorkerToken.generate_and_sign(
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

      bearer =
        Workers.generate_run_token(%{id: id}, %{
          run_timeout_ms: 1000
        })

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
        Workers.generate_run_token(%{id: id}, %{run_timeout_ms: 1000})

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
               "options" => %{
                 output_dataclips: true,
                 run_timeout_ms: 1000
               }
             }
    end

    @tag project_retention_policy: :erase_all
    test "fetch:plan for project with erase_all retention setting", %{
      credential: credential,
      socket: socket,
      run: run,
      workflow: workflow
    } do
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
               "options" => %{
                 output_dataclips: false,
                 run_timeout_ms: run.options.run_timeout_ms
               }
             }
    end

    @tag project_retention_policy: :erase_all
    test "fetch:plan includes options from usage limiter", context do
      project_id = context.project.id

      extra_options = [
        run_timeout_ms: 5000,
        save_dataclips: false,
        run_memory_limit_mb: 1024
      ]

      expected_worker_options = %{
        run_timeout_ms: 5000,
        output_dataclips: false,
        run_memory_limit_mb: 1024
      }

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :get_run_options,
        fn %{project_id: ^project_id} -> extra_options end
      )

      %{socket: socket} =
        merge_setups(context, [
          :create_run,
          :create_socket,
          :join_run_channel
        ])

      ref = push(socket, "fetch:plan", %{})

      assert_reply ref, :ok, payload

      assert match?(%{"options" => ^expected_worker_options}, payload)
    end

    @tag project_retention_policy: :erase_all
    test "fetch:plan does not include options from usage limiter with nil values",
         context do
      project_id = context.project.id

      extra_options = [
        run_timeout_ms: 5000,
        save_dataclips: false,
        run_memory_limit_mb: nil
      ]

      expected_worker_options = %{run_timeout_ms: 5000, output_dataclips: false}

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :get_run_options,
        fn %{project_id: ^project_id} -> extra_options end
      )

      %{socket: socket} =
        merge_setups(context, [
          :create_run,
          :create_socket,
          :join_run_channel
        ])

      ref = push(socket, "fetch:plan", %{})

      assert_reply ref, :ok, payload

      assert match?(%{"options" => ^expected_worker_options}, payload)
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
         %{socket: socket, dataclip: dataclip} do
      Lightning.Stub.freeze_time(DateTime.utc_now())

      ref = push(socket, "fetch:dataclip", %{})

      assert_reply ref, :ok, {:binary, _payload}

      %{wiped_at: wiped_at, body: body} = get_dataclip_with_body(dataclip.id)

      # dataclip body is cleared
      assert wiped_at == Lightning.current_time() |> DateTime.truncate(:second)

      refute body
    end

    @tag project_retention_policy: :retain_all
    test "fetch:dataclip wipes dataclip body for projects with retain_all retention policy",
         context do
      %{socket: socket, dataclip: dataclip} = context

      ref = push(socket, "fetch:dataclip", %{})

      assert_reply ref, :ok, {:binary, _payload}

      dataclip_query = from(Dataclip, select: [:wiped_at, :body, :request])
      updated_dataclip = Lightning.Repo.get(dataclip_query, dataclip.id)
      refute updated_dataclip.wiped_at
      assert updated_dataclip.body
    end

    test "fetch:credential", %{socket: socket, credential: credential} do
      credential = Repo.preload(credential, :oauth_client)
      oauth_client = credential.oauth_client

      credential_body =
        Lightning.Credentials.get_credential_body(credential.id, "main")

      current_expires_at = credential_body.body["expires_at"]
      new_expiry = current_expires_at + 3600

      endpoint = oauth_client.token_endpoint

      Mox.expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        %Tesla.Env{
          method: :post,
          url: ^endpoint
        } = env,
        _opts ->
          {:ok,
           %Tesla.Env{
             env
             | status: 200,
               body:
                 Jason.encode!(%{
                   "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
                   "expires_at" => new_expiry,
                   "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
                   "scope" => "https://www.googleapis.com/auth/spreadsheets",
                   "token_type" => "Bearer"
                 })
           }}
      end)

      ref = push(socket, "fetch:credential", %{"id" => credential.id})

      assert_receive %Phoenix.Socket.Reply{
        ref: ^ref,
        status: :ok,
        payload: payload
      }

      assert payload["access_token"] == "ya29.a0AWY7CknfkidjXaoDTuNi"

      assert payload["expires_at"] >= current_expires_at

      assert payload["refresh_token"] == "1//03dATMQTmE5NSCgYIARAAGAMSNwF"
      assert payload["sandbox"] == false
      assert payload["scope"] == "https://www.googleapis.com/auth/spreadsheets"
      assert Map.has_key?(payload, "token_type")
      assert Map.has_key?(payload, "updated_at")
    end
  end

  describe "fetch:credential" do
    setup :set_google_credential

    test "doesn't cast credential body fields" do
      user = insert(:user)

      credential =
        insert(:credential,
          name: "Test Postgres",
          schema: "postgresql",
          user: user
        )
        |> with_body(%{
          name: "main",
          body: %{
            "user" => "user1",
            "password" => "pass1",
            "host" => "https://dbhost",
            "port" => "5000",
            "database" => "test_db",
            "ssl" => "true",
            "allowSelfSignedCert" => "false"
          }
        })

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
          schema: "postgresql",
          user: user
        )
        |> with_body(%{
          name: "main",
          body: %{
            "user" => "user1",
            "password" => "pass1",
            "host" => "https://dbhost",
            "database" => "test_db",
            "port" => 5000,
            "ssl" => true,
            "allowSelfSignedCert" => false
          }
        })

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

    test "does not send keys with empty strings" do
      user = insert(:user)

      credential =
        insert(:credential,
          name: "Test Commcare",
          schema: "commcare",
          user: user
        )
        |> with_body(%{
          name: "main",
          body: %{
            "apiKey" => "",
            "appId" => "12345",
            "domain" => "localhost",
            "hostUrl" => "http://localhost:2500",
            "password" => "test",
            "username" => "test"
          }
        })

      %{socket: socket} =
        create_socket_and_run(%{credential: credential, user: user})

      ref = push(socket, "fetch:credential", %{"id" => credential.id})

      assert_reply ref,
                   :ok,
                   %{
                     "appId" => "12345",
                     "domain" => "localhost",
                     "hostUrl" => "http://localhost:2500",
                     "password" => "test",
                     "username" => "test"
                   }
    end

    test "fetch:credential for OAuth credential merges body with oauth_token body" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      credential =
        insert(:credential,
          name: "OAuth Test",
          schema: "oauth",
          oauth_client: oauth_client,
          user: user
        )
        |> with_body(%{
          name: "main",
          body: %{
            "apiVersion" => 23,
            "sandbox" => true,
            "access_token" => "test_access_token",
            "refresh_token" => "test_refresh_token",
            "expires_at" =>
              DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix()
          }
        })

      %{socket: socket} =
        create_socket_and_run(%{credential: credential, user: user})

      ref = push(socket, "fetch:credential", %{"id" => credential.id})

      assert_reply ref, :ok, response

      assert response["apiVersion"] == 23
      assert response["sandbox"] == true
      assert response["access_token"] == "test_access_token"
      assert response["refresh_token"] == "test_refresh_token"
      assert Map.has_key?(response, "expires_at")
    end

    @tag capture_log: true
    test "translates error messages properly", %{
      credential: credential,
      user: user
    } do
      credential = Repo.preload(credential, :oauth_client)
      oauth_client = credential.oauth_client

      endpoint = oauth_client.token_endpoint

      Lightning.AuthProviders.OauthHTTPClient.Mock
      |> Mox.expect(:call, fn
        %Tesla.Env{
          method: :post,
          url: ^endpoint
        } = env,
        _opts ->
          {:ok,
           %Tesla.Env{
             env
             | status: 400,
               body: Jason.encode!(%{"error" => "invalid_grant"})
           }}
      end)
      |> Mox.expect(:call, fn
        %Tesla.Env{
          method: :post,
          url: ^endpoint
        } = env,
        _opts ->
          {:ok,
           %Tesla.Env{
             env
             | status: 429,
               body: Jason.encode!(%{"error" => "rate limit"})
           }}
      end)

      %{socket: socket} =
        create_socket_and_run(%{credential: credential, user: user})

      # token expiry
      ref = push(socket, "fetch:credential", %{"id" => credential.id})

      assert_reply ref, :error, error_msg

      assert error_msg =~ credential.name
      assert error_msg =~ "Reauthorize with your external system"

      assert error_msg =~
               "If this is not your credential, send this link to the owner and ask them to reauthorize"

      # temporary failure
      ref = push(socket, "fetch:credential", %{"id" => credential.id})

      assert_reply ref,
                   :error,
                   "Could not reach the oauth provider. Try again later"
    end
  end

  describe "marking steps as started and finished" do
    setup :create_socket

    setup context do
      user = insert(:user)

      %{project: project} = create_project(%{user: user} |> Map.merge(context))

      credential =
        insert(:credential,
          name: "My Credential",
          user: user
        )
        |> with_body(%{
          name: "main",
          body: %{"pin" => "1234"}
        })

      %{id: project_credential_id} =
        insert(:project_credential, credential: credential, project: project)

      dataclip = insert(:dataclip, body: %{"foo" => "bar"}, project: project)

      %{triggers: [trigger], jobs: [job]} =
        workflow = insert(:simple_workflow, project: project)

      {:ok, snapshot} = Workflows.Snapshot.create(workflow)

      Repo.update(
        Ecto.Changeset.change(job, project_credential_id: project_credential_id)
      )

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot
        )

      run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot,
          options:
            Lightning.Extensions.MockUsageLimiter.get_run_options(%Context{
              project_id: project.id
            })
            |> Map.new()
        )

      run_options =
        Lightning.Extensions.MockUsageLimiter.get_run_options(%Context{
          project_id: project.id
        })
        |> Enum.into(%{})

      {:ok, _, socket} =
        context.socket
        |> subscribe_and_join(
          LightningWeb.RunChannel,
          "run:#{run.id}",
          %{"token" => Workers.generate_run_token(run, run_options)}
        )

      %{
        socket: socket,
        run: run,
        user: user,
        workflow: workflow,
        credential: credential,
        project: project,
        trigger: trigger,
        snapshot: snapshot
      }
    end

    @tag api_version: "1.2"
    test "step:start with API v1.2", %{
      socket: socket,
      run: %{dataclip_id: dataclip_id},
      workflow: workflow,
      credential: %{id: credential_id},
      project: project
    } do
      # { id, job_id, input_dataclip_id }
      step_id = Ecto.UUID.generate()
      [%{id: job_id}] = workflow.jobs

      timestamp = 1_727_423_491_748_984

      ref =
        push(socket, "step:start", %{
          "step_id" => step_id,
          "credential_id" => credential_id,
          "job_id" => job_id,
          "input_dataclip_id" => dataclip_id,
          "timestamp" => to_string(timestamp)
        })

      assert_reply ref, :ok, %{step_id: ^step_id}, 1_000

      assert project.retention_policy == :retain_all

      assert %{
               credential_id: ^credential_id,
               job_id: ^job_id,
               input_dataclip_id: ^dataclip_id,
               started_at: started_at
             } =
               Repo.get!(Step, step_id)

      assert DateTime.to_unix(started_at, :microsecond) == timestamp
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
    test "step:start providing a dataclip for a project with erase_all retention policy",
         context do
      %{
        socket: socket,
        run: %{dataclip_id: dataclip_id},
        credential: %{id: credential_id},
        project: project,
        workflow: workflow
      } = context

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
    end

    @tag project_retention_policy: :erase_all
    test "step:start without a dataclip for a project with erase_all retention policy",
         context do
      %{
        socket: socket,
        credential: %{id: credential_id},
        workflow: workflow
      } = context

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

    @tag api_version: "1.2"
    test "step:complete succeeds with API v1.2", %{
      socket: socket,
      run: run,
      workflow: workflow
    } do
      [job] = workflow.jobs
      %{id: step_id} = step = insert(:step, runs: [run], job: job)

      timestamp = 1_727_423_491_748_984

      ref =
        push(socket, "step:complete", %{
          "step_id" => step.id,
          "output_dataclip_id" => Ecto.UUID.generate(),
          "output_dataclip" => ~s({"foo": "bar"}),
          "reason" => "normal",
          "timestamp" => to_string(timestamp)
        })

      assert_reply ref, :ok, %{step_id: ^step_id}

      assert %{exit_reason: "normal", finished_at: finished_at} =
               Repo.get(Step, step.id)

      assert DateTime.to_unix(finished_at, :microsecond) == timestamp
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
      assert run.work_order.workflow.project_id == project.id

      run_from_socket = socket.assigns.run
      options = run_from_socket.options

      assert %Lightning.Runs.RunOptions{save_dataclips: false} = options

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

      %{socket: socket} =
        context
        |> merge_setups([
          :create_run,
          :create_socket,
          :join_run_channel
        ])

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

      {:ok, snapshot} = Workflows.Snapshot.create(workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot
        )

      run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot,
          options:
            Lightning.Extensions.MockUsageLimiter.get_run_options(%Context{
              project_id: project.id
            })
            |> Map.new()
        )

      %{run: run, workflow: workflow}
    end

    setup [:create_socket, :join_run_channel]

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

      assert_reply ref, :ok, %{log_line_id: _}
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

  describe "run:start" do
    setup [:create_user, :create_project]

    setup context do
      run_state = Map.get(context, :run_state, :available)

      project = context.project
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
          state: run_state,
          options:
            Lightning.Extensions.MockUsageLimiter.get_run_options(%Context{
              project_id: project.id
            })
            |> Map.new()
        )

      %{
        run: run,
        workflow: workflow,
        work_order: work_order
      }
    end

    setup [:create_socket, :join_run_channel]

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

    @tag run_state: :claimed, api_version: "1.2"
    test "run:start with API v1.2", %{
      socket: socket,
      run: run,
      work_order: work_order
    } do
      timestamp = 1_727_423_491_748_984

      ref = push(socket, "run:start", %{"timestamp" => to_string(timestamp)})

      assert_reply ref, :ok, nil

      assert %{state: :started, started_at: started_at} =
               Lightning.Repo.reload!(run)

      assert DateTime.to_unix(started_at, :microsecond) == timestamp
      assert %{state: :running} = Lightning.Repo.reload!(work_order)
    end
  end

  describe "run:complete" do
    setup [:create_user, :create_project]

    setup context do
      run_state = Map.get(context, :run_state, :available)

      project = context.project
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
          state: run_state,
          options:
            Lightning.Extensions.MockUsageLimiter.get_run_options(%Context{
              project_id: project.id
            })
            |> Map.new()
        )

      %{
        run: run,
        workflow: workflow,
        work_order: work_order
      }
    end

    setup [:create_socket, :join_run_channel]

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

    @tag run_state: :started, api_version: "1.2"
    test "run:complete with API v1.2", %{
      socket: socket,
      run: run
    } do
      timestamp = 1_727_423_491_748_984

      ref =
        push(socket, "run:complete", %{
          "timestamp" => to_string(timestamp),
          "reason" => "success",
          "error_type" => nil,
          "error_message" => nil
        })

      assert_reply ref, :ok, nil

      assert %{state: :success, finished_at: finished_at} =
               Lightning.Repo.reload!(run)

      assert DateTime.to_unix(finished_at, :microsecond) == timestamp
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

      assert_reply ref, :ok, nil, 1_000

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
    merge_setups(context, [
      :create_project,
      :create_workflow,
      :create_run,
      :create_socket,
      :join_run_channel
    ])
  end

  defp create_user(_context) do
    %{user: insert(:user)}
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

    {:ok, snapshot} = Workflows.Snapshot.create(workflow)

    %{workflow: workflow, job: job, trigger: trigger, snapshot: snapshot}
  end

  defp create_run(context) do
    assert_context_keys(context, [
      :project,
      :credential,
      :workflow,
      :trigger,
      :snapshot
    ])

    %{
      project: project,
      credential: credential,
      workflow: workflow,
      trigger: trigger,
      snapshot: snapshot
    } = context

    dataclip =
      insert(:http_request_dataclip, project: project)

    work_order =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip,
        snapshot: snapshot
      )

    run =
      insert(:run,
        work_order: work_order,
        starting_trigger: trigger,
        dataclip: dataclip,
        snapshot: snapshot,
        options:
          Lightning.Extensions.MockUsageLimiter.get_run_options(%Context{
            project_id: project.id
          })
          |> Map.new()
      )

    %{
      run: run,
      workflow: workflow,
      credential: credential,
      dataclip: dataclip
    }
  end

  defp create_socket(context) do
    {:ok, bearer, claims} =
      Workers.WorkerToken.generate_and_sign(
        %{},
        Lightning.Config.worker_token_signer()
      )

    assigns = %{
      token: bearer,
      claims: claims,
      api_version: context[:api_version]
    }

    socket =
      LightningWeb.WorkerSocket
      |> socket("socket_id", assigns)

    %{socket: socket}
  end

  defp join_run_channel(%{run: run, socket: socket}) do
    {:ok, _, socket} =
      socket
      |> subscribe_and_join(
        LightningWeb.RunChannel,
        "run:#{run.id}",
        %{
          "token" =>
            Workers.generate_run_token(run, %Lightning.Runs.RunOptions{
              run_timeout_ms: 2
            })
        }
      )

    %{socket: socket}
  end

  # ✅ Updated to use credential_bodies structure
  defp set_google_credential(_context) do
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(-299, :second)
      |> DateTime.to_unix()

    user = insert(:user)
    oauth_client = insert(:oauth_client)

    credential =
      insert(:credential,
        name: "Test Googlesheets Credential",
        user: user,
        schema: "oauth",
        oauth_client: oauth_client
      )
      |> with_body(%{
        name: "main",
        body: %{
          "sandbox" => false,
          "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
          "expires_at" => expires_at,
          "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
          "scope" => "https://www.googleapis.com/auth/spreadsheets",
          "token_type" => "Bearer"
        }
      })

    {:ok, credential: credential, user: user}
  end

  defp get_dataclip_with_body(dataclip_id) do
    from(d in Dataclip, select: %{d | body: d.body})
    |> Repo.get(dataclip_id)
  end

  # Browser client tests
  describe "joining the run:* channel as browser client" do
    setup do
      user = insert(:user)
      project = insert(:project)
      insert(:project_user, user: user, project: project)
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow, type: :webhook)
      dataclip = insert(:dataclip, project: project)
      snapshot = insert(:snapshot, workflow: workflow)

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot
        )

      run =
        insert(:run,
          work_order: workorder,
          starting_trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot
        )

      token = Phoenix.Token.sign(@endpoint, "user socket", user.id)
      {:ok, socket} = connect(LightningWeb.UserSocket, %{"token" => token})

      %{
        socket: socket,
        run: run,
        user: user,
        project: project,
        workflow: workflow
      }
    end

    test "allows authorized user to join", %{socket: socket, run: run} do
      assert {:ok, _reply, _socket} =
               subscribe_and_join(socket, "run:#{run.id}", %{})
    end

    test "rejects unauthorized user", %{socket: socket} do
      other_project = insert(:project)
      other_workflow = insert(:workflow, project: other_project)
      other_trigger = insert(:trigger, workflow: other_workflow, type: :webhook)
      other_dataclip = insert(:dataclip, project: other_project)
      other_snapshot = insert(:snapshot, workflow: other_workflow)

      other_workorder =
        insert(:workorder,
          workflow: other_workflow,
          trigger: other_trigger,
          dataclip: other_dataclip,
          snapshot: other_snapshot
        )

      other_run =
        insert(:run,
          work_order: other_workorder,
          starting_trigger: other_trigger,
          dataclip: other_dataclip,
          snapshot: other_snapshot
        )

      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, "run:#{other_run.id}", %{})
    end

    test "rejects non-existent run", %{socket: socket} do
      fake_id = Ecto.UUID.generate()

      assert {:error, %{reason: "not_found"}} =
               subscribe_and_join(socket, "run:#{fake_id}", %{})
    end
  end

  describe "handle_in fetch:run for browser clients" do
    setup do
      user = insert(:user)
      project = insert(:project)
      insert(:project_user, user: user, project: project)
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)
      trigger = insert(:trigger, workflow: workflow, type: :webhook)
      dataclip = insert(:dataclip, project: project)
      snapshot = insert(:snapshot, workflow: workflow)

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot
        )

      run =
        insert(:run,
          work_order: workorder,
          starting_job: job,
          created_by: user,
          dataclip: dataclip,
          snapshot: snapshot
        )

      step = insert(:step, job: job, runs: [run])

      token = Phoenix.Token.sign(@endpoint, "user socket", user.id)
      {:ok, socket} = connect(LightningWeb.UserSocket, %{"token" => token})

      {:ok, _reply, socket} =
        subscribe_and_join(socket, "run:#{run.id}", %{})

      %{socket: socket, run: run, step: step, job: job}
    end

    test "returns run with associations", %{
      socket: socket,
      run: run,
      step: step
    } do
      ref = push(socket, "fetch:run", %{})

      assert_reply ref, :ok, %{run: returned_run}

      # In test environment, data is returned as structs not JSON
      assert returned_run.id == run.id
      assert is_list(returned_run.steps)
      assert length(returned_run.steps) == 1
      assert List.first(returned_run.steps).id == step.id
      assert List.first(returned_run.steps).job.id == step.job_id
    end
  end

  describe "handle_in fetch:logs for browser clients" do
    setup do
      user = insert(:user)
      project = insert(:project)
      insert(:project_user, user: user, project: project)
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow, type: :webhook)
      dataclip = insert(:dataclip, project: project)
      snapshot = insert(:snapshot, workflow: workflow)

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot
        )

      run =
        insert(:run,
          work_order: workorder,
          starting_trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot
        )

      insert(:log_line,
        run: run,
        message: "Test log message 1",
        timestamp: DateTime.utc_now()
      )

      insert(:log_line,
        run: run,
        message: "Test log message 2",
        timestamp: DateTime.utc_now()
      )

      token = Phoenix.Token.sign(@endpoint, "user socket", user.id)
      {:ok, socket} = connect(LightningWeb.UserSocket, %{"token" => token})

      {:ok, _reply, socket} =
        subscribe_and_join(socket, "run:#{run.id}", %{})

      %{socket: socket, run: run}
    end

    test "returns log lines for run", %{socket: socket} do
      ref = push(socket, "fetch:logs", %{})

      assert_reply ref, :ok, %{logs: logs}

      assert is_list(logs)
      assert length(logs) == 2
    end
  end

  describe "handle_info for browser client events" do
    setup do
      user = insert(:user)
      project = insert(:project)
      insert(:project_user, user: user, project: project)
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)
      trigger = insert(:trigger, workflow: workflow, type: :webhook)
      dataclip = insert(:dataclip, project: project)

      # Create snapshot with the job included
      {:ok, snapshot} = Workflows.Snapshot.create(workflow)

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot
        )

      run =
        insert(:run,
          work_order: workorder,
          starting_trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot,
          state: :started
        )

      token = Phoenix.Token.sign(@endpoint, "user socket", user.id)
      {:ok, socket} = connect(LightningWeb.UserSocket, %{"token" => token})

      {:ok, _reply, socket} =
        subscribe_and_join(socket, "run:#{run.id}", %{})

      %{socket: socket, run: run, job: job, project: project, snapshot: snapshot}
    end

    test "forwards run updated event", %{socket: _socket, run: run} do
      {:ok, updated_run} =
        run
        |> Lightning.Run.complete(%{
          state: :success,
          finished_at: DateTime.utc_now()
        })
        |> Lightning.Repo.update()

      Lightning.Runs.Events.run_updated(updated_run)

      assert_push "run:updated", %{run: pushed_run}
      assert pushed_run.state == :success
    end

    test "forwards step started event", %{
      socket: _socket,
      run: run,
      job: job,
      project: project
    } do
      input_dataclip = insert(:dataclip, project: project)

      {:ok, step} =
        Lightning.Runs.start_step(run, %{
          step_id: Ecto.UUID.generate(),
          job_id: job.id,
          input_dataclip_id: input_dataclip.id,
          started_at: DateTime.utc_now()
        })

      assert_push "step:started", %{step: pushed_step}
      assert pushed_step.id == step.id
      assert pushed_step.job.id == job.id
    end

    test "forwards step completed event", %{
      socket: _socket,
      run: run,
      job: job,
      project: project
    } do
      input_dataclip = insert(:dataclip, project: project)

      {:ok, step} =
        Lightning.Runs.start_step(run, %{
          step_id: Ecto.UUID.generate(),
          job_id: job.id,
          input_dataclip_id: input_dataclip.id,
          started_at: DateTime.utc_now()
        })

      {:ok, completed_step} =
        Lightning.Runs.complete_step(
          %{
            "step_id" => step.id,
            "output_dataclip" => Jason.encode!(%{"foo" => "bar"}),
            "output_dataclip_id" => Ecto.UUID.generate(),
            "reason" => "success",
            "finished_at" => DateTime.utc_now(),
            "run_id" => run.id,
            "project_id" => project.id
          },
          %Lightning.Runs.RunOptions{}
        )

      assert_push "step:completed", %{step: pushed_step}
      assert pushed_step.id == completed_step.id
      assert pushed_step.exit_reason == "success"
    end

    test "forwards log appended event", %{socket: _socket, run: run} do
      {:ok, log_line} =
        Lightning.Runs.append_run_log(run, %{
          message: "test message",
          level: :info,
          source: "TEST",
          timestamp: DateTime.utc_now()
        })

      assert_push "logs", %{logs: [pushed_log]}
      assert pushed_log.id == log_line.id
      assert pushed_log.message == "test message"
    end
  end
end
