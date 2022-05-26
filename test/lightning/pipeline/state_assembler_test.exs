defmodule Lightning.Pipeline.StateAssemblerTest do
  use Lightning.DataCase, async: true

  alias Lightning.Pipeline.StateAssembler
  import Lightning.InvocationFixtures
  import Lightning.JobsFixtures
  import Lightning.CredentialsFixtures

  describe "assemble/2" do
    test "event triggered by webhook" do
      %{run: run, dataclip: dataclip} = run_without_source_event()

      assert StateAssembler.assemble(run) |> Jason.decode!() == %{
               "configuration" => %{"my" => "credential"},
               "data" => %{"foo" => "bar"}
             }

      job = job_fixture(credential: nil)
      event = event_fixture(dataclip_id: dataclip.id, job_id: job.id)
      run = run_fixture(event_id: event.id)

      # When a Job doesn't have a credential
      assert StateAssembler.assemble(run) |> Jason.decode!() == %{
               "configuration" => nil,
               "data" => %{"foo" => "bar"}
             }
    end

    test "event triggered by a failed run" do
      %{run: run} = run_with_failed_source_event()

      assert StateAssembler.assemble(run) |> Jason.decode!() == %{
               "configuration" => %{"other" => "credential"},
               "error" => ["1", "2"],
               "data" => %{"foo" => "bar"}
             }
    end

    test "event triggered by a successful run" do
      %{run: run} = run_with_successful_source_event()

      assert StateAssembler.assemble(run) |> Jason.decode!() == %{
               "configuration" => %{"other" => "credential"},
               "data" => "I succeeded",
               "extra" => ["data"]
             }
    end
  end

  describe "context_query/1" do
    test "run without source event" do
      %{run: run} = run_without_source_event()

      assert StateAssembler.context_query(run) == %{
               dataclip_type: :http_request,
               trigger_type: :webhook
             }
    end

    test "run with successful source event" do
      %{run: run} = run_with_successful_source_event()

      assert StateAssembler.context_query(run) == %{
               dataclip_type: :run_result,
               trigger_type: :on_job_success
             }
    end

    test "run with failed source event" do
      %{run: run} = run_with_failed_source_event()

      assert StateAssembler.context_query(run) == %{
               dataclip_type: :http_request,
               trigger_type: :on_job_failure
             }
    end

    # failed source event
  end

  def webhook_event() do
    dataclip = dataclip_fixture(body: %{"foo" => "bar"})

    job =
      job_fixture(
        project_credential_id:
          project_credential_fixture(
            body: %{"my" => "credential"},
            name: "My Credential"
          ).id
      )

    event =
      event_fixture(type: :webhook, dataclip_id: dataclip.id, job_id: job.id)

    %{dataclip: dataclip, job: job, event: event}
  end

  def run_without_source_event() do
    %{dataclip: dataclip, job: job, event: event} = webhook_event()

    %{
      run: run_fixture(event_id: event.id),
      event: event,
      job: job,
      dataclip: dataclip
    }
  end

  def run_with_successful_source_event() do
    %{event: event} = webhook_event()

    dataclip_fixture(
      type: :run_result,
      source_event_id: event.id,
      body: %{"data" => "I succeeded", "extra" => ["data"]}
    )

    run =
      run_fixture(
        event_id: event.id,
        exit_code: 0,
        log: ["1", "2"]
      )
      |> Repo.preload(:result_dataclip)

    job =
      job_fixture(
        trigger: %{type: :on_job_success},
        project_credential_id:
          project_credential_fixture(
            body: %{"other" => "credential"},
            name: "other credential"
          ).id
      )

    event =
      event_fixture(
        type: :flow,
        dataclip_id: run.result_dataclip.id,
        job_id: job.id,
        source_id: event.id
      )
      |> Repo.preload(:dataclip)

    run = run_fixture(event_id: event.id) |> Repo.preload(:result_dataclip)

    %{
      run: run,
      event: event,
      job: job,
      dataclip: event.dataclip
    }
  end

  def run_with_failed_source_event() do
    %{event: event} = webhook_event()

    run_fixture(
      event_id: event.id,
      exit_code: 1,
      log: ["1", "2"],
      result_dataclip: nil
    )

    job =
      job_fixture(
        trigger: %{type: :on_job_failure},
        project_credential_id:
          project_credential_fixture(
            body: %{"other" => "credential"},
            name: "other credential"
          ).id
      )

    event =
      event_fixture(
        type: :flow,
        dataclip_id: event.dataclip_id,
        job_id: job.id,
        source_id: event.id
      )
      |> Repo.preload(:dataclip)

    run = run_fixture(event_id: event.id)

    %{
      run: run,
      event: event,
      job: job,
      dataclip: event.dataclip
    }
  end
end
