defmodule LightningWeb.AttemptChannelTest do
  use LightningWeb.ChannelCase, async: true

  alias Lightning.Workers
  import Lightning.Factories

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

    test "fetch:attempt", %{
      socket: socket,
      attempt: attempt,
      workflow: workflow
    } do
      id = attempt.id
      ref = push(socket, "fetch:attempt", %{})

      # { id, triggers, jobs, edges, options ...etc }
      assert_reply ref, :ok, payload

      triggers =
        workflow.triggers
        |> Enum.map(&Map.take(&1, [:id]))
        |> Enum.map(&stringify_keys/1)

      jobs =
        workflow.jobs
        |> Enum.map(&Map.take(&1, [:id, :name]))
        |> Enum.map(&stringify_keys/1)

      edges =
        workflow.edges
        |> Enum.map(
          &Map.take(&1, [
            :id,
            :source_trigger_id,
            :source_job_id,
            :condition,
            :target_job_id
          ])
        )
        |> Enum.map(&stringify_keys/1)

      assert payload == %{
               "id" => id,
               "triggers" => triggers,
               "jobs" => jobs,
               "edges" => edges,
               "starting_node_id" => attempt.starting_trigger_id,
               "dataclip_id" => attempt.dataclip_id
             }
    end
  end

  describe "marking runs as started and finished" do
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

    test "run:start", %{socket: socket, attempt: attempt, workflow: workflow} do
      # { id, job_id, input_dataclip_id }
      run_id = Ecto.UUID.generate()
      [job] = workflow.jobs

      ref =
        push(socket, "run:start", %{
          "job_id" => job.id,
          "input_dataclip_id" => attempt.dataclip_id
        })

      assert_reply ref, :error, errors

      assert errors == %{run_id: ["This field can't be blank."]}

      ref =
        push(socket, "run:start", %{
          "run_id" => run_id,
          "job_id" => job.id,
          "input_dataclip_id" => attempt.dataclip_id
        })

      assert_reply ref, :ok, %{run_id: ^run_id}
    end

    test "run:complete", %{socket: socket, attempt: attempt, workflow: workflow} do
      [job] = workflow.jobs
      %{id: run_id} = run = insert(:run, attempts: [attempt], job: job)

      ref =
        push(socket, "run:complete", %{
          "run_id" => run.id,
          "output_dataclip" => ~s({"foo": "bar"})
        })

      assert_reply ref, :ok, %{run_id: ^run_id}
    end
  end

  defp stringify_keys(map) do
    Enum.map(map, fn {k, v} -> {Atom.to_string(k), v} end)
    |> Enum.into(%{})
  end
end
