defmodule Lightning.WorkflowEdgeCasesTest do
  @moduledoc """
  Integration tests for "lost run" scenarios — single-step workflows where
  the job code exercises edge cases around run completion and state handling.

  To add a new test case, define a function that returns the job body string,
  then call `run_single_step_workflow/2` with your webhook input and job body.
  Assert against the returned `%{run: run, step: step, work_order: work_order}`.
  """
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

  setup [:register_and_log_in_superuser, :stub_rate_limiter_ok]

  # ---------------------------------------------------------------------------
  # Test cases — each one only needs to supply the job body and assertions.
  # ---------------------------------------------------------------------------

  @tag :integration
  @tag timeout: 10_000
  test "job that returns 42 completes successfully", %{uri: uri} do
    job_body = """
    fn(state => {
      // if you return a non-map, it used to cause lost
      // now it gets wrapped in a map ¯\_(ツ)_/¯
      return 42;
    });
    """

    result = run_single_step_workflow(uri, %{"x" => 1}, job_body)

    assert result.run.state == :success
    assert result.step.exit_reason == "success"

    assert %{"value" => 42} =
             select_dataclip_body(result.step.output_dataclip_id)
  end

  @tag :integration
  @tag timeout: 10_000
  test "job that uses too much memory very quickly is properly killed", %{
    uri: uri
  } do
    job_body = """
    fn(state => {
      const arr = [];
      while (true) { arr.push(new Array(1e6).fill('x')); }
      return state;
    });
    """

    result = run_single_step_workflow(uri, %{"x" => 1}, job_body)

    assert result.run.state == :killed
    assert result.run.error_type == "OOMError"
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  @doc """
  Creates a single-step webhook workflow, fires it, waits for completion,
  and returns a map with the fully-loaded run, step, and work_order.

  ## Parameters
    - `uri`          — the endpoint base URL (from setup_all)
    - `webhook_body` — the JSON map to POST to the webhook
    - `job_body`     — the JavaScript expression string for the job
    - `opts`         — keyword list of options:
      - `:adaptor`  — adaptor string (default `"@openfn/language-common@latest"`)
      - `:timeout`  — ms to wait for run completion (default `15_000`)

  ## Returns
    %{run: run, step: step, work_order: work_order}
  """
  def run_single_step_workflow(uri, webhook_body, job_body, opts \\ []) do
    adaptor = Keyword.get(opts, :adaptor, "@openfn/language-common@latest")
    timeout = Keyword.get(opts, :timeout, 15_000)

    project = insert(:project)

    webhook_trigger = build(:trigger, type: :webhook, enabled: true)

    job =
      build(:job,
        adaptor: adaptor,
        body: job_body,
        name: "test-job"
      )

    workflow =
      build(:workflow, project: project)
      |> with_trigger(webhook_trigger)
      |> with_job(job)
      |> with_edge({webhook_trigger, job}, condition_type: :always)
      |> insert()

    Snapshot.create(workflow)

    # Fire the webhook
    response =
      Tesla.client(
        [
          {Tesla.Middleware.BaseUrl, uri},
          Tesla.Middleware.JSON
        ],
        {Tesla.Adapter.Finch, name: Lightning.Finch}
      )
      |> Tesla.post!("/i/#{webhook_trigger.id}", webhook_body)

    assert response.status == 200
    assert %{"work_order_id" => workorder_id} = response.body

    assert %{runs: [run]} =
             WorkOrders.get(workorder_id, include: [:runs])

    # Subscribe and wait for completion
    Events.subscribe(run)
    run_id = run.id

    assert_receive %Events.RunUpdated{run: %{id: ^run_id, state: final_state}}
                   when final_state in [
                          :success,
                          :failed,
                          :crashed,
                          :killed,
                          :lost
                        ],
                   timeout

    # Reload with associations
    run =
      Runs.get(run.id,
        include: [steps: [:job, :log_lines], work_order: :workflow]
      )

    [step] = run.steps

    work_order = WorkOrders.get(workorder_id)

    %{run: run, step: step, work_order: work_order}
  end

  defp start_runtime_manager(_context \\ nil) do
    opts =
      Application.get_env(:lightning, RuntimeManager)
      |> Keyword.merge(
        name: LostRunRedTeamRuntimeManager,
        start: true,
        endpoint: LightningWeb.Endpoint,
        log: :debug,
        port: Enum.random(2223..3333),
        worker_secret: Lightning.Config.worker_secret()
      )

    start_supervised!({RuntimeManager, opts}, restart: :transient)
  end

  defp select_dataclip_body(uuid) do
    from(d in Invocation.Dataclip,
      where: d.id == ^uuid,
      select: d.body
    )
    |> Repo.one!()
  end
end
