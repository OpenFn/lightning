defmodule Lightning.WebAndWorkerTest do
  use LightningWeb.ConnCase, async: false

  import Ecto.Query
  import Lightning.Factories
  import Mox

  alias Lightning.Runs
  alias Lightning.Runs.Events
  alias Lightning.Invocation
  alias Lightning.Repo
  alias Lightning.Runtime.RuntimeManager
  alias Lightning.WorkOrders
  alias Lightning.Workflows.Snapshot

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup_all do
    Mox.stub_with(Lightning.MockConfig, Lightning.Config.API)
    Mox.stub_with(LightningMock, Lightning.API)

    Mox.stub_with(
      Lightning.Extensions.MockUsageLimiter,
      Lightning.Extensions.UsageLimiter
    )

    start_runtime_manager()

    uri = LightningWeb.Endpoint.url()

    %{uri: uri}
  end

  describe "webhook triggered runs" do
    setup [:register_and_log_in_superuser, :stub_rate_limiter_ok]

    @tag :integration
    test "complete a run on a complex workflow with parallel jobs", %{uri: uri} do
      project = insert(:project)

      %{triggers: [%{id: webhook_trigger_id}], edges: edges} =
        workflow =
        insert(:complex_workflow, project: project)

      # ensure the workflow has parallel jobs. Eliminate the branching edge
      branching_edge =
        Enum.find(edges, fn edge -> edge.condition_type == :on_job_failure end)

      branching_edge
      |> Ecto.Changeset.change(%{condition_type: :on_job_success})
      |> Repo.update!()

      # Create snapshot only after we have made the edge changes
      Snapshot.create(workflow |> Repo.reload!())

      # Post to webhook
      webhook_body = %{"x" => 1}

      response =
        Tesla.client(
          [
            {Tesla.Middleware.BaseUrl, uri},
            Tesla.Middleware.JSON
          ],
          {Tesla.Adapter.Finch, name: Lightning.Finch}
        )
        |> Tesla.post!("/i/#{webhook_trigger_id}", webhook_body)

      assert response.status == 200
      assert %{"work_order_id" => workorder_id} = response.body

      assert %{runs: [run]} =
               WorkOrders.get(workorder_id, include: [:runs])

      # wait to complete
      Events.subscribe(run)

      assert %{id: run_id, steps: []} = Runs.get(run.id, include: [:steps])

      assert_receive %Events.RunUpdated{run: %{id: ^run_id, state: :success}},
                     115_000

      assert %{state: :success} = WorkOrders.get(workorder_id)

      %{entries: steps} = Invocation.list_steps_for_project(project)

      # steps with unique outputs and all succeed
      assert Enum.count(steps) == 7
      assert Enum.count(steps, & &1.output_dataclip_id) == 7
      assert Enum.all?(steps, fn step -> step.exit_reason == "success" end)

      # first step has the webhook body as input
      [first_step | steps] = Enum.reverse(steps)
      assert webhook_body == select_dataclip_body(first_step.input_dataclip_id)

      # the other 6 steps produce the same input and output on x twice
      # (2 branches that doubles x value three times)
      assert steps
             |> Enum.map(&select_dataclip_body(&1.input_dataclip_id)["x"])
             |> Enum.frequencies()
             |> Enum.all?(fn {_x, count} -> count == 2 end)

      assert steps
             |> Enum.map(&select_dataclip_body(&1.output_dataclip_id)["x"])
             |> Enum.frequencies()
             |> Enum.all?(fn {_x, count} -> count == 2 end)

      assert %{state: :success} = WorkOrders.get(workorder_id)

      # There was an initial http_request dataclip and 7 run_result dataclips
      assert Repo.all(Lightning.Invocation.Dataclip) |> Enum.count() == 8
    end

    @tag :integration
    @tag timeout: 20_000
    test "the whole thing", %{conn: conn, user: user} do
      project = insert(:project)

      # Create credential with body for main environment
      credential_1 =
        insert(:credential,
          name: "test credential",
          user: user,
          schema: "raw"
        )
        |> with_body(%{
          name: "main",
          body: %{"username" => "quux", "password" => "immasecret"}
        })

      project_credential =
        insert(:project_credential,
          credential: credential_1,
          project: project
        )

      # Create credential with body for main environment and external_id
      credential_2 =
        insert(:credential,
          name: "resolved by keychain",
          user: user,
          schema: "raw",
          external_id: "some_string"
        )
        |> with_body(%{
          name: "main",
          body: %{"username" => "foo", "password" => "immasecret"}
        })

      _project_credential_2 =
        insert(:project_credential,
          credential: credential_2,
          project: project
        )

      # Matches the webhook body, resolves to the project_credential_2
      keychain_credential =
        insert(:keychain_credential,
          project: project,
          path: "$.fieldTwo",
          default_credential: credential_2
        )

      # Doesn't match anything, resolves to `nil`
      keychain_credential_2 =
        insert(:keychain_credential, project: project, path: "$.noMatch")

      webhook_trigger = build(:trigger, type: :webhook, enabled: true)

      job_1 =
        build(:job,
          adaptor: "@openfn/language-http@latest",
          body: webhook_expression(),
          name: "1st-job",
          project_credential: project_credential
        )

      job_2 =
        build(:job,
          adaptor: "@openfn/language-http@latest",
          body: flow_expression(),
          name: "2nd-job",
          project_credential: project_credential
        )

      job_3 =
        build(:job,
          adaptor: "@openfn/language-http@7.2.0",
          body: catch_expression(),
          name: "3rd-job",
          keychain_credential: keychain_credential
        )

      job_4 =
        build(:job,
          adaptor: "@openfn/language-common@3.0.2",
          body: on_js_condition_body(),
          name: "4th-job",
          keychain_credential: keychain_credential_2
        )

      workflow =
        build(:workflow, project: project)
        |> with_trigger(webhook_trigger)
        |> with_job(job_1)
        |> with_edge({webhook_trigger, job_1}, condition_type: :always)
        |> with_job(job_2)
        |> with_edge({job_1, job_2}, condition_type: :on_job_success)
        |> with_job(job_3)
        |> with_edge({job_2, job_3}, condition_type: :on_job_failure)
        |> with_job(job_4)
        |> with_edge({job_3, job_4},
          condition_type: :js_expression,
          condition_label: "less_than_1000",
          condition_expression: "state.x < 1000"
        )
        |> insert()

      Snapshot.create(workflow)

      webhook_body = %{"fieldOne" => 123, "fieldTwo" => "some_string"}

      conn = post(conn, "/i/#{webhook_trigger.id}", webhook_body)

      assert %{"work_order_id" => workorder_id} = json_response(conn, 200)

      assert %{runs: [%{id: run_id} = run]} =
               WorkOrders.get(workorder_id, include: [:runs])

      assert %{steps: []} = Runs.get(run.id, include: [:steps])

      # wait to complete
      Events.subscribe(run)

      assert_receive %Events.RunUpdated{
                       run: %{id: ^run_id, state: :started}
                     },
                     115_000

      assert_receive %Events.RunUpdated{
                       run: %{id: ^run_id, state: :success}
                     },
                     115_000

      assert %{state: :success} = WorkOrders.get(workorder_id)

      run =
        Runs.get(run.id,
          include: [steps: [:job, :log_lines], work_order: :workflow]
        )

      assert run.work_order.workflow.project_id == project.id

      # Alls steps have consistent finish_at, exit_reason and dataclips
      for step <- run.steps do
        assert NaiveDateTime.after?(step.finished_at, run.claimed_at) and
                 NaiveDateTime.before?(step.finished_at, run.finished_at),
               "Expected step #{step.job.name} to finish between the run's claimed_at and finished_at"
      end

      for {a, b} <- Enum.zip(run.steps, Enum.slice(run.steps, 1..-1//1)) do
        assert NaiveDateTime.before?(a.finished_at, b.started_at), """
        Expected #{b.job.name} to start after #{a.job.name} finished.
        """
      end

      version_logs = pick_out_version_logs(run)
      assert version_logs["@openfn/language-http"] =~ "3.1.12"
      assert version_logs["worker"] =~ "1.17"
      assert version_logs["node.js"] =~ "22.12"
      assert version_logs["@openfn/language-common"] == "3.0.2"

      [step_1, step_2, step_3, step_4] = run.steps

      # ------------------------------------------------------------------------

      assert step_1.exit_reason == "success"
      assert step_1.job.name == "1st-job"

      expected_job_x_value = 123 * 2

      assert Enum.any?(
               step_1.log_lines,
               &(&1.source == "R/T" and &1.message =~ "Operation 1 complete in")
             )

      expected_lines =
        MapSet.new([
          {"R/T", "Starting operation 1"},
          {"JOB", "#{expected_job_x_value}"},
          {"JOB", "{\"name\":\"ศผ่องรี มมซึฆเ\"}"},
          {"R/T", "Expression complete!"}
        ])

      assert expected_lines ==
               MapSet.intersection(
                 expected_lines,
                 MapSet.new(step_1.log_lines, &{&1.source, &1.message})
               )

      # input: has only the webhook body
      assert webhook_body == select_dataclip_body(step_1.input_dataclip_id)

      # output: data unchanged by the job and x is updated
      assert %{"data" => ^webhook_body, "x" => ^expected_job_x_value} =
               select_dataclip_body(step_1.output_dataclip_id)

      # ------------------------------------------------------------------------

      # Step 2 should fail but not expose a secret
      assert step_2.exit_reason == "fail"
      assert step_2.job.name == "2nd-job"

      log = Invocation.assemble_logs_for_step(step_2)

      # Testing for how "empty" logs are handled
      # console.log();          => new line
      # console.log('');        => new line
      # console.log(null);      => null
      # console.log(undefined); => new line
      assert log =~ "Starting operation 1\n\nnull\n{"

      assert log =~ ~S[{"password":"***","username":"quux"}]
      assert log =~ ~S"Check state.errors"

      assert select_dataclip_body(step_1.output_dataclip_id) ==
               select_dataclip_body(step_2.input_dataclip_id),
             "Expected step 2 to have the same input as step 1's output"

      # ------------------------------------------------------------------------

      assert step_3.exit_reason == "success"
      assert step_3.job.name == "3rd-job"

      # Is set to use keychain_credential, which matches on the webhook body
      # and resolves to the project_credential_2
      # Get the credential body from the "main" environment
      credential_2_body =
        Lightning.Credentials.get_credential_body(credential_2.id, "main").body

      assert pick_out_config(step_3.log_lines) |> Jason.decode!() ==
               credential_2_body

      assert Enum.any?(
               step_3.log_lines,
               &(&1.source == "R/T" and &1.message =~ "Operation 1 complete in")
             )

      expected_job_x_value = 123 * 6

      expected_lines =
        MapSet.new([
          {"R/T", "Starting operation 1"},
          {"JOB", "#{expected_job_x_value}"},
          # Check to ensure that an inadvertantly exposed secret from job 2 is
          # still scrubbed properly in job 3.
          {"JOB", "quux is on the safelist"},
          {"JOB", "but *** should be scrubbed"},
          {"JOB", "along with its encoded form ***"},
          {"JOB", "and its basic auth form ***"},
          {"R/T", "Expression complete!"}
        ])

      assert expected_lines ==
               MapSet.intersection(
                 expected_lines,
                 MapSet.new(step_3.log_lines, &{&1.source, &1.message})
               )

      # ------------------------------------------------------------------------

      assert step_4.exit_reason == "success"
      assert step_4.job.name == "4th-job"

      # Is set to use keychain_credential_2, which doesn't match anything,
      # so it resolves to `nil`
      assert pick_out_config(step_4.log_lines) |> Jason.decode!() == %{}

      assert select_dataclip_body(step_3.input_dataclip_id) ==
               select_dataclip_body(step_2.output_dataclip_id),
             "Expected step 3 to have the same input as step 2's output"

      assert %{"data" => ^webhook_body, "x" => ^expected_job_x_value} =
               select_dataclip_body(step_3.output_dataclip_id),
             "Expected step 3 to have the same output as step 2's input"

      # Step 4 after the js condition should succeed and log the correct value of x
      expected_job_x_value = expected_job_x_value * 5

      assert Enum.any?(step_4.log_lines, fn line ->
               line.source == "JOB" and line.message =~ "#{expected_job_x_value}"
             end)
    end
  end

  describe "webhook with delayed response (after_completion)" do
    setup [:register_and_log_in_superuser, :stub_rate_limiter_ok]

    @tag :integration
    @tag timeout: 120_000
    test "returns final state to webhook caller after workflow completes", %{
      uri: uri
    } do
      project = insert(:project)

      # Create a simple workflow
      webhook_trigger = build(:trigger, type: :webhook, enabled: true)

      job =
        build(:job,
          adaptor: "@openfn/language-common@latest",
          body: """
          fn(state => {
            console.log("Processing data...");
            // Add a delay to ensure the webhook request is still waiting
            return new Promise(resolve => {
              setTimeout(() => {
                resolve({ result: "success", data: { value: state.data.x * 2 } });
              }, 1000);
            });
          });
          """,
          name: "process-job"
        )

      workflow =
        build(:workflow, project: project)
        |> with_trigger(webhook_trigger)
        |> with_job(job)
        |> with_edge({webhook_trigger, job}, condition_type: :always)
        |> insert()

      # Update trigger to use after_completion
      [trigger] = workflow.triggers

      trigger =
        trigger
        |> Ecto.Changeset.change(webhook_reply: :after_completion)
        |> Repo.update!()

      # Create snapshot
      Snapshot.create(workflow |> Repo.reload!())

      # Post to webhook - this should wait for completion
      webhook_body = %{"x" => 5}

      # Make request in a task so we can verify it waits
      task =
        Task.async(fn ->
          Tesla.client(
            [
              {Tesla.Middleware.BaseUrl, uri},
              Tesla.Middleware.JSON
            ],
            {Tesla.Adapter.Finch, name: Lightning.Finch}
          )
          |> Tesla.post!("/i/#{trigger.id}", webhook_body)
        end)

      # Give it a moment to create the work order
      Process.sleep(500)

      # Verify work order was created but response not yet returned
      refute Task.yield(task, 50),
             "Expected webhook request to still be waiting"

      # Wait for the workflow to complete (up to 10 seconds)
      response = Task.await(task, 10_000)

      # Should return 201 with the final state
      assert response.status == 201

      # The response body should be the final state from the job inside a "data"
      # key and the metadata inside a "meta" key.
      assert %{
               "data" => %{"data" => %{"value" => 10}, "result" => "success"},
               "meta" => meta
             } = response.body

      # Verify meta fields exist with correct types and values
      assert meta["error_type"] == nil
      assert meta["state"] == "success"
      assert is_binary(meta["run_id"])
      assert is_binary(meta["work_order_id"])

      # Verify datetime fields are present and valid ISO8601 strings
      assert is_binary(meta["claimed_at"])
      assert is_binary(meta["finished_at"])
      assert is_binary(meta["inserted_at"])
      assert is_binary(meta["started_at"])

      # Verify datetime fields match ISO8601 format
      assert meta["claimed_at"] =~ ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/
      assert meta["finished_at"] =~ ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/
      assert meta["inserted_at"] =~ ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/
      assert meta["started_at"] =~ ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/

      # Verify the work order completed successfully
      work_order =
        Lightning.Repo.one(
          from wo in Lightning.WorkOrder,
            where: wo.trigger_id == ^trigger.id,
            order_by: [desc: wo.inserted_at],
            limit: 1
        )

      assert work_order.state == :success
    end

    @tag :integration
    @tag timeout: 120_000
    test "returns error state when workflow fails", %{uri: uri} do
      project = insert(:project)

      webhook_trigger = build(:trigger, type: :webhook, enabled: true)

      job =
        build(:job,
          adaptor: "@openfn/language-common@latest",
          body: """
          fn(state => {
            console.log("About to fail...");
            throw new Error("Intentional failure");
          });
          """,
          name: "failing-job"
        )

      workflow =
        build(:workflow, project: project)
        |> with_trigger(webhook_trigger)
        |> with_job(job)
        |> with_edge({webhook_trigger, job}, condition_type: :always)
        |> insert()

      [trigger] = workflow.triggers

      trigger =
        trigger
        |> Ecto.Changeset.change(webhook_reply: :after_completion)
        |> Repo.update!()

      Snapshot.create(workflow |> Repo.reload!())

      webhook_body = %{"test" => "data"}

      response =
        Tesla.client(
          [
            {Tesla.Middleware.BaseUrl, uri},
            Tesla.Middleware.JSON
          ],
          {Tesla.Adapter.Finch, name: Lightning.Finch}
        )
        |> Tesla.post!("/i/#{trigger.id}", webhook_body)

      # Should return 201 for failed workflow
      assert response.status == 201

      # Response should include the final state
      assert is_map(response.body)

      # Verify the work order failed
      work_order =
        Lightning.Repo.one(
          from wo in Lightning.WorkOrder,
            where: wo.trigger_id == ^trigger.id,
            order_by: [desc: wo.inserted_at],
            limit: 1
        )

      assert work_order.state == :failed
    end
  end

  defp webhook_expression do
    """
    fn(state => {
      state.x = state.data.fieldOne * 2;
      console.log(state.x);
      console.log({name: 'ศผ่องรี มมซึฆเ'})
      return state;
    });
    """
  end

  defp flow_expression do
    """
    fn(state => {
      console.log();
      console.log('');
      console.log(null);
      console.log(undefined);
      console.log(state.configuration);
      throw 'fail!'
    });
    """
  end

  defp catch_expression do
    """
    fn(state => {
      console.log("config: " + util.encode(state.configuration));
      state.x = state.x * 3;
      console.log(state.x);
      console.log('quux is on the safelist')
      console.log('but immasecret should be scrubbed');
      console.log('along with its encoded form #{Base.encode64("immasecret")}');
      console.log('and its basic auth form #{Base.encode64("quux:immasecret")}');
      return state;
    });
    """
  end

  defp on_js_condition_body do
    """
    fn(state => {
      console.log("config: " + util.encode(state.configuration));
      state.x = state.x * 5;
      console.log(state.x);
      return state;
    });
    """
  end

  defp start_runtime_manager(_context \\ nil) do
    opts =
      Application.get_env(:lightning, RuntimeManager)
      |> Keyword.merge(
        name: E2ETestRuntimeManager,
        start: true,
        endpoint: LightningWeb.Endpoint,
        log: :debug,
        port: Enum.random(2223..3333),
        worker_secret: Lightning.Config.worker_secret()
      )

    start_supervised!({RuntimeManager, opts}, restart: :transient)
  end

  defp select_dataclip_body(uuid) do
    from(d in Lightning.Invocation.Dataclip,
      where: d.id == ^uuid,
      select: d.body
    )
    |> Repo.one!()
  end

  defp pick_out_version_logs(run) do
    {:ok, version_logs} =
      Repo.transaction(fn ->
        run
        |> Runs.get_log_lines()
        |> Enum.find(fn l -> l.source == "VER" end)
        |> then(fn %{message: message} ->
          ~r/▸ ([\@\/\-\w\.]+)\s+(\d+\.\d+(?:\.\d+))/
          |> Regex.scan(message)
          |> Enum.into(%{}, fn [_, dependency, version] ->
            {dependency, version}
          end)
        end)
      end)

    version_logs
  end

  # Used to sneakily get the config from the job log lines, so we can check
  # that the expected credential is resolved correctly - specifically
  # the keychain credentials where the credential id does not map 1:1 with the
  # credential body that is resolved.
  defp pick_out_config(log_lines) do
    Enum.reduce_while(log_lines, nil, fn line, _ ->
      if line.source == "JOB" do
        Regex.run(~r/config: (.+)/, line.message)
        |> case do
          nil ->
            {:cont, nil}

          [_, config] ->
            {:halt, config |> Base.decode64!()}
        end
      else
        {:cont, nil}
      end
    end)
    |> tap(fn config ->
      assert config,
             "Expected config to be present in the log lines as a base64 encoded string prefixed with 'config: '"
    end)
  end
end
