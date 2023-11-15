# This module will be re-introduced in https://github.com/OpenFn/Lightning/issues/1143
defmodule LightningWeb.EndToEndTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.JobsFixtures
  import Lightning.Factories

  alias Lightning.Attempts
  alias Lightning.Invocation
  alias Lightning.Repo
  alias Lightning.WorkOrders
  alias Lightning.Runtime.RuntimeManager

  setup_all context do
    start_runtime_manager(context)
  end

  describe "webhook triggered attempts" do
    setup :register_and_log_in_superuser

    test "complete an attempt on a simple workflow", %{conn: conn} do
      project = insert(:project)

      %{triggers: [%{id: webhook_trigger_id}]} =
        insert(:simple_workflow, project: project)

      # Post to webhook
      conn = post(conn, "/i/#{webhook_trigger_id}", %{"a" => 1})

      assert %{"work_order_id" => wo_id} = json_response(conn, 200)

      assert %{attempts: [%{id: attempt_id}]} =
               WorkOrders.get(wo_id, include: [:attempts])

      assert %{runs: []} = Attempts.get(attempt_id, include: [:runs])

      assert %{attempts: [%{id: attempt_id}]} =
               WorkOrders.get(wo_id, include: [:attempts])

      # wait to complete
      assert Enum.any?(1..100, fn _i ->
               Process.sleep(50)
               %{state: state} = Attempts.get(attempt_id)
               state == :success
             end)

      assert %{state: :success, attempts: [%{runs: [run]}]} =
               WorkOrders.get(wo_id, include: [attempts: [:runs]])

      assert run.exit_reason == "success"
    end

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
        condition: :on_job_success
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
        condition: :on_job_failure
      })

      webhook_body = %{"fieldOne" => 123, "fieldTwo" => "some string"}

      conn = post(conn, "/i/#{webhook_trigger.id}", webhook_body)

      assert %{"work_order_id" => wo_id} = json_response(conn, 200)

      assert %{attempts: [%{id: attempt_id}]} =
               WorkOrders.get(wo_id, include: [:attempts])

      assert %{runs: []} = Attempts.get(attempt_id, include: [:runs])

      # wait to complete
      assert Enum.any?(1..100, fn _i ->
               Process.sleep(50)
               %{state: state} = Attempts.get(attempt_id)
               state == :success
             end)

      # All runs are associated with the same project and attempt and proper job
      %{runs: runs} = Attempts.get(attempt_id, include: [:runs])

      %{entries: [run_3, run_2, run_1]} =
        Invocation.list_runs_for_project(project)

      assert MapSet.new(runs, & &1.id) ==
               MapSet.new([run_1, run_2, run_3], & &1.id)

      # Alls runs have consistent finish_at, exit_reason and dataclips
      %{claimed_at: claimed_at, finished_at: finished_at} =
        Attempts.get(attempt_id)

      # Run 1 succeeds with webhook_body as input
      assert NaiveDateTime.diff(run_1.finished_at, claimed_at, :microsecond) > 0
      assert NaiveDateTime.diff(run_1.finished_at, finished_at, :microsecond) < 0
      assert run_1.exit_reason == "success"

      lines =
        Invocation.logs_for_run(run_1)
        |> Enum.with_index()
        |> Map.new(fn {line, i} -> {i, line} end)

      expected_job_x_value = 123 * 2
      assert lines[0].source == "R/T"
      assert lines[0].message == "Starting operation 1"
      assert lines[1].source == "JOB"
      assert lines[1].message == "#{expected_job_x_value}"
      assert lines[2].source == "JOB"
      assert lines[2].message == "{\"name\":\"ศผ่องรี มมซึฆเ\"}"
      assert lines[3].source == "R/T"
      assert lines[3].message =~ "Operation 1 complete in"
      assert lines[4].source == "R/T"
      assert lines[4].message == "Expression complete!"

      # input: has only the webhook body
      assert webhook_body == select_dataclip_body(run_1.input_dataclip_id)

      # output: data unchanged by the job and x is updated
      assert %{"data" => ^webhook_body, "x" => ^expected_job_x_value} =
               select_dataclip_body(run_1.output_dataclip_id)

      # #  Run 2 should fail but not expose a secret
      assert NaiveDateTime.diff(run_2.finished_at, claimed_at, :microsecond) > 0
      assert NaiveDateTime.diff(run_2.finished_at, finished_at, :microsecond) < 0
      assert run_2.exit_reason == "failed"

      log = Invocation.assemble_logs_for_run(run_2)

      assert log =~ ~S[{"password":"***","username":"quux"}]
      assert log =~ ~S"Check state.errors"

      assert select_dataclip_body(run_1.output_dataclip_id) ==
               select_dataclip_body(run_2.input_dataclip_id)

      #  Run 3 should succeed and log "6"
      assert NaiveDateTime.diff(run_3.finished_at, claimed_at, :microsecond) > 0
      assert NaiveDateTime.diff(run_3.finished_at, finished_at, :microsecond) < 0
      assert run_3.exit_reason == "success"

      lines =
        Invocation.logs_for_run(run_3)
        |> Enum.with_index()
        |> Map.new(fn {line, i} -> {i, line} end)

      expected_job_x_value = 123 * 6

      assert lines[0].source == "R/T"
      assert lines[0].message == "Starting operation 1"
      assert lines[1].source == "JOB"
      assert lines[1].message == "#{expected_job_x_value}"
      assert lines[2].source == "R/T"
      assert lines[2].message =~ "Operation 1 complete in"
      assert lines[3].source == "R/T"
      assert lines[3].message == "Expression complete!"

      assert select_dataclip_body(run_2.output_dataclip_id) ==
               select_dataclip_body(run_3.input_dataclip_id)

      assert %{"data" => ^webhook_body, "x" => ^expected_job_x_value} =
               select_dataclip_body(run_3.output_dataclip_id)
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
      return state;
    });"
  end

  defp start_runtime_manager(_context) do
    rtm_args = "node ./node_modules/.bin/worker -- --backoff 0.5/5"

    Application.put_env(:lightning, RuntimeManager,
      start: true,
      args: String.split(rtm_args),
      cd: Path.expand("../../assets", __DIR__)
    )

    {:ok, rtm_server} = RuntimeManager.start_link(name: TestRuntimeManager)

    Enum.any?(1..10, fn _i ->
      Process.sleep(100)
      %{runtime_port: port} = :sys.get_state(rtm_server)
      port != nil
    end)

    :ok
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
