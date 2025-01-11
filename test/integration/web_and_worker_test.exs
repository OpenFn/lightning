# This module will be re-introduced in https://github.com/OpenFn/Lightning/issues/1143
defmodule Lightning.WebAndWorkerTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.JobsFixtures
  import Lightning.Factories
  import Mox

  alias Lightning.Run
  alias Lightning.Runs
  alias Lightning.Runs.Events
  alias Lightning.Invocation
  alias Lightning.Repo
  alias Lightning.Runtime.RuntimeManager
  alias Lightning.WorkOrders
  alias Lightning.Workflows.Snapshot

  require Run

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup_all context do
    Mox.stub_with(Lightning.MockConfig, Lightning.Config.API)
    Mox.stub_with(LightningMock, Lightning.API)
    Mox.stub_with(Lightning.Tesla.Mock, Tesla.Adapter.Hackney)

    Mox.stub_with(
      Lightning.Extensions.MockUsageLimiter,
      Lightning.Extensions.UsageLimiter
    )

    start_runtime_manager(context)
  end

  describe "webhook triggered runs" do
    setup [:register_and_log_in_superuser, :stub_rate_limiter_ok]

    @tag :integration
    @tag timeout: 20_000
    test "complete a run on a complex workflow with parallel jobs", %{
      conn: conn
    } do
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
      conn = post(conn, "/i/#{webhook_trigger_id}", webhook_body)

      assert %{"work_order_id" => wo_id} =
               json_response(conn, 200)

      assert %{runs: [run]} =
               WorkOrders.get(wo_id, include: [:runs])

      assert %{steps: []} = Runs.get(run.id, include: [:steps])

      # wait to complete
      Events.subscribe(run)

      run_id = run.id

      assert_receive %Events.RunUpdated{
                       run: %{id: ^run_id, state: :success}
                     },
                     115_000

      assert %{state: :success} = WorkOrders.get(wo_id)

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

      assert %{state: :success} = WorkOrders.get(wo_id)

      # There was an initial http_request dataclip and 7 run_result dataclips
      assert Repo.all(Lightning.Invocation.Dataclip) |> Enum.count() == 8
    end

    @tag :integration
    @tag timeout: 20_000
    test "the whole thing", %{conn: conn} do
      project = insert(:project)

      project_credential =
        insert(:project_credential,
          credential: %{
            name: "test credential",
            body: %{"username" => "quux", "password" => "immasecret"}
          },
          project: project
        )

      %{
        job: first_job = %{workflow: workflow},
        trigger: webhook_trigger,
        edge: _edge
      } =
        workflow_job_fixture(
          project: project,
          name: "1st-job",
          adaptor: "@openfn/language-http@latest",
          body: webhook_expression(),
          project_credential: project_credential
        )

      flow_job =
        insert(:job,
          name: "2nd-job",
          adaptor: "@openfn/language-http@latest",
          body: flow_expression(),
          workflow: workflow,
          project_credential: project_credential
        )

      insert(:edge, %{
        workflow: workflow,
        source_job_id: first_job.id,
        target_job_id: flow_job.id,
        condition_type: :on_job_success
      })

      catch_job =
        insert(:job,
          name: "3rd-job",
          adaptor: "@openfn/language-http@latest",
          body: catch_expression(),
          workflow: workflow,
          project_credential: project_credential
        )

      insert(:edge, %{
        source_job_id: flow_job.id,
        workflow: workflow,
        target_job_id: catch_job.id,
        condition_type: :on_job_failure
      })

      expression1_job =
        insert(:job,
          name: "4th-job",
          adaptor: "@openfn/language-http@latest",
          body: on_js_condition_body(),
          workflow: workflow,
          project_credential: project_credential
        )

      insert(:edge, %{
        source_job_id: catch_job.id,
        workflow: workflow,
        target_job_id: expression1_job.id,
        condition_type: :js_expression,
        condition_label: "less_than_1000",
        condition_expression: "state.x < 1000"
      })

      Snapshot.create(workflow)

      webhook_body = %{"fieldOne" => 123, "fieldTwo" => "some string"}

      conn = post(conn, "/i/#{webhook_trigger.id}", webhook_body)

      assert %{"work_order_id" => wo_id} = json_response(conn, 200)

      assert %{runs: [%{id: run_id} = run]} =
               WorkOrders.get(wo_id, include: [:runs])

      assert %{steps: []} = Runs.get(run.id, include: [:steps])

      # wait to complete
      Events.subscribe(run)

      assert_receive %Events.RunUpdated{
                       run: %{id: ^run_id, state: :success}
                     },
                     115_000

      assert %{state: :success} = WorkOrders.get(wo_id)

      # All steps are associated with the same project and run and proper job
      %{steps: steps} = Runs.get(run.id, include: [:steps])

      assert %{
               total_entries: 4,
               entries: [step_4, step_3, step_2, step_1] = entries_steps
             } =
               Invocation.list_steps_for_project(project)

      assert MapSet.new(steps, & &1.id) ==
               MapSet.new(entries_steps, & &1.id)

      # Alls steps have consistent finish_at, exit_reason and dataclips
      %{claimed_at: claimed_at, finished_at: finished_at} =
        Runs.get(run.id)

      assert Enum.all?(steps, fn step ->
               NaiveDateTime.after?(step_2.finished_at, claimed_at) and
                 NaiveDateTime.before?(step_2.finished_at, finished_at)
             end)

      # Step 1 succeeds with webhook_body as input
      assert step_1.exit_reason == "success"

      expected_job_x_value = 123 * 2

      lines = Invocation.logs_for_step(step_1)

      assert Enum.any?(
               lines,
               &(&1.source == "R/T" and &1.message =~ "Operation 1 complete in")
             )

      {:ok, version_logs} =
        Repo.transaction(fn ->
          run
          |> Runs.get_log_lines()
          |> Enum.find(fn l -> l.source == "VER" end)
          |> Map.get(:message)
        end)

      assert version_logs =~ "▸ node.js                  18.17"
      assert version_logs =~ "▸ worker                   1.8"
      assert version_logs =~ "▸ @openfn/language-http    3.1.12"

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
                 MapSet.new(lines, &{&1.source, &1.message})
               )

      # input: has only the webhook body
      assert webhook_body == select_dataclip_body(step_1.input_dataclip_id)

      # output: data unchanged by the job and x is updated
      assert %{"data" => ^webhook_body, "x" => ^expected_job_x_value} =
               select_dataclip_body(step_1.output_dataclip_id)

      # #  Step 2 should fail but not expose a secret
      assert step_2.exit_reason == "fail"

      log = Invocation.assemble_logs_for_step(step_2)

      assert log =~ ~S[{"password":"***","username":"quux"}]
      assert log =~ ~S"Check state.errors"

      assert select_dataclip_body(step_1.output_dataclip_id) ==
               select_dataclip_body(step_2.input_dataclip_id)

      #  Step 3 should succeed and log the correct value of x
      assert step_3.exit_reason == "success"

      lines = Invocation.logs_for_step(step_3)

      assert Enum.any?(
               lines,
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
                 MapSet.new(lines, &{&1.source, &1.message})
               )

      assert select_dataclip_body(step_2.output_dataclip_id) ==
               select_dataclip_body(step_3.input_dataclip_id)

      assert %{"data" => ^webhook_body, "x" => ^expected_job_x_value} =
               select_dataclip_body(step_3.output_dataclip_id)

      # Step 4 after the js condition should succeed and log the correct value of x
      expected_job_x_value = expected_job_x_value * 5
      assert step_4.exit_reason == "success"

      assert Enum.any?(Invocation.logs_for_step(step_4), fn line ->
               line.source == "JOB" and line.message =~ "#{expected_job_x_value}"
             end)
    end
  end

  defp webhook_expression do
    "fn(state => {
      state.x = state.data.fieldOne * 2;
      console.log(state.x);
      console.log({name: 'ศผ่องรี มมซึฆเ'})
      return state;
    });"
  end

  defp flow_expression do
    "fn(state => {
      console.log(state.configuration);
      throw 'fail!'
    });"
  end

  defp catch_expression do
    "fn(state => {
      state.x = state.x * 3;
      console.log(state.x);
      console.log('quux is on the safelist')
      console.log('but immasecret should be scrubbed');
      console.log('along with its encoded form #{Base.encode64("immasecret")}');
      console.log('and its basic auth form #{Base.encode64("quux:immasecret")}');
      return state;
    });"
  end

  defp on_js_condition_body do
    "fn(state => {
      state.x = state.x * 5;
      console.log(state.x);
      return state;
    });"
  end

  defp start_runtime_manager(_context) do
    opts =
      Application.get_env(:lightning, RuntimeManager)
      |> Keyword.merge(
        name: E2ETestRuntimeManager,
        start: true,
        worker_secret: Lightning.Config.worker_secret(),
        port: Enum.random(2223..3333)
      )

    {:ok, rtm_server} = RuntimeManager.start_link(opts)

    running =
      Enum.any?(1..20, fn _i ->
        Process.sleep(50)
        %{runtime_port: port} = :sys.get_state(rtm_server)
        port != nil
      end)

    if running, do: :ok, else: :error
  end

  defp select_dataclip_body(uuid) do
    {:ok, %{rows: [[body]]}} =
      Ecto.Adapters.SQL.query(
        Repo,
        "SELECT BODY FROM DATACLIPS WHERE ID=$1",
        [
          Ecto.UUID.dump!(uuid)
        ]
      )

    body
  end
end
