defmodule LightningWeb.WebhooksControllerTest do
  use LightningWeb.ConnCase, async: false
  use Mimic

  alias Lightning.{Invocation, Repo}

  import Lightning.JobsFixtures

  require Record
  @fields Record.extract(:span, from: "deps/opentelemetry/include/otel_span.hrl")
  Record.defrecordp(:span, @fields)

  describe "a POST request to '/i'" do
    setup %{conn: conn} do
      %{job: job, trigger: trigger, edge: _edge} = workflow_job_fixture()

      [conn: conn, job: job, trigger: trigger, message: %{"foo" => "bar"}]
    end

    test "with a valid trigger id instantiates a workorder", %{
      conn: conn,
      job: job,
      trigger: trigger,
      message: message
    } do
      Oban.Testing.with_testing_mode(:inline, fn ->
        expect(Lightning.Pipeline.Runner, :start, fn _run ->
          %Lightning.Runtime.Result{}
        end)

        conn = post(conn, "/i/#{trigger.id}", message)

        assert %{"work_order_id" => _, "run_id" => run_id} =
                 json_response(conn, 200)

        %{job_id: job_id, input_dataclip: %{body: body}} =
          Invocation.get_run!(run_id)
          |> Repo.preload(:input_dataclip)

        assert job_id == job.id
        assert body == message
      end)
    end

    test "triggers a custom telemetry event", %{
      conn: conn,
      trigger: trigger,
      message: message
    } do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:lightning, :workorder, :webhook, :stop]
        ])

      trigger_id = trigger.id

      post(conn, "/i/#{trigger.id}", message)

      assert_received {
        [:lightning, :workorder, :webhook, :stop],
        ^ref,
        %{},
        %{source_trigger_id: ^trigger_id}
      }
    end

    test "executes a custom OpenTelemetry trace", %{
      conn: conn,
      trigger: trigger,
      message: message
    } do
      :otel_simple_processor.set_exporter(:otel_exporter_pid, self())

      attributes =
        :otel_attributes.new([source_trigger_id: trigger.id], 128, :infinity)

      post(conn, "/i/#{trigger.id}", message)

      assert_receive {:span,
                      span(
                        name: "lightning.api.webhook",
                        attributes: ^attributes
                      )}
    end

    test "with an invalid trigger id returns a 404", %{conn: conn} do
      conn = post(conn, "/i/bar")
      assert json_response(conn, 404) == %{}
    end
  end

  test "return 403 on a disabled message", %{conn: conn} do
    %{job: _job, trigger: trigger, edge: _edge} =
      workflow_job_fixture(enabled: false)

    conn = post(conn, "/i/#{trigger.id}", %{"foo" => "bar"})

    assert %{"message" => message} = json_response(conn, 403)

    assert message =~ "Unable to process request, trigger is disabled."
  end
end
