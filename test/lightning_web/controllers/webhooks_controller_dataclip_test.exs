defmodule LightningWeb.WebhooksControllerDataclipTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.Factories
  import Mox

  alias Lightning.Repo
  alias Lightning.Runs
  alias Lightning.WorkOrders

  @moduletag capture_log: true

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Mox.stub(Lightning.MockConfig, :cors_origin, fn -> "*" end)
    :ok
  end

  describe "the request stored with the dataclip" do
    setup [:stub_rate_limiter_ok, :stub_usage_limiter_ok]

    test "creates a pending workorder with a valid trigger and an additional path",
         %{conn: conn} do
      %{triggers: [%{id: trigger_id}]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      message = %{"foo" => "bar"}
      conn = post(conn, "/i/#{trigger_id}/Patient", message)

      assert %{"work_order_id" => work_order_id} =
               json_response(conn, 200)

      assert %{trigger: %{id: ^trigger_id}, runs: [run], state: :pending} =
               WorkOrders.get(work_order_id,
                 include: [:runs, :dataclip, :trigger]
               )

      assert %{starting_trigger_id: ^trigger_id} = run

      assert Repo.all(Lightning.Invocation.Dataclip) |> Enum.count() == 1

      assert Runs.get_dataclip_body(run) == ~s({"foo": "bar"})

      assert Runs.get_dataclip_request(run) ==
               ~s({\"path\": [\"i\", \"#{trigger_id}\", \"Patient\"], \"method\": \"POST\", \"headers\": {\"content-type\": \"multipart/mixed; boundary=plug_conn_test\"}, \"query_params\": {}})
    end

    test "creates a pending workorder with a valid trigger and some query params",
         %{conn: conn} do
      %{triggers: [%{id: trigger_id}]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      message = %{"foo" => "bar"}
      conn = post(conn, "/i/#{trigger_id}?extra=stuff&moar=things", message)

      assert %{"work_order_id" => work_order_id} =
               json_response(conn, 200)

      assert %{trigger: %{id: ^trigger_id}, runs: [run], state: :pending} =
               WorkOrders.get(work_order_id,
                 include: [:runs, :dataclip, :trigger]
               )

      assert %{starting_trigger_id: ^trigger_id} = run

      assert Repo.all(Lightning.Invocation.Dataclip) |> Enum.count() == 1

      assert Runs.get_dataclip_body(run) == ~s({"foo": "bar"})

      assert Runs.get_dataclip_request(run) ==
               ~s({\"path\": [\"i\", \"#{trigger_id}\"], \"method\": \"POST\", \"headers\": {\"content-type\": \"multipart/mixed; boundary=plug_conn_test\"}, \"query_params\": {\"moar\": \"things\", \"extra\": \"stuff\"}})
    end
  end

  describe "sensitive request headers" do
    setup [:stub_rate_limiter_ok, :stub_usage_limiter_ok]

    test "the x-api-key consumed by webhook auth is not persisted in dataclip.request",
         %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      auth_method =
        insert(:webhook_auth_method,
          auth_type: :api,
          api_key: "sup3r-s3cret-api-key"
        )

      associate_auth_methods(trigger, [auth_method])

      conn =
        conn
        |> put_req_header("x-api-key", "sup3r-s3cret-api-key")
        |> post("/i/#{trigger.id}", %{"foo" => "bar"})

      assert %{"work_order_id" => work_order_id} = json_response(conn, 200)

      %{runs: [run]} = WorkOrders.get(work_order_id, include: [:runs])

      request = Runs.get_dataclip_request(run) |> Jason.decode!()

      assert request["headers"]["x-api-key"] == "[REDACTED]",
             "the api key Lightning already consumed to authenticate must not be retained"

      refute Runs.get_dataclip_request(run) =~ "sup3r-s3cret-api-key"
    end

    test "the Basic Authorization consumed by webhook auth is redacted from dataclip.request",
         %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      auth_method =
        insert(:webhook_auth_method,
          auth_type: :basic,
          username: "caller",
          password: "sup3r-s3cret-password"
        )

      associate_auth_methods(trigger, [auth_method])

      credentials = Base.encode64("caller:sup3r-s3cret-password")

      conn =
        conn
        |> put_req_header("authorization", "Basic #{credentials}")
        |> post("/i/#{trigger.id}", %{"foo" => "bar"})

      assert %{"work_order_id" => work_order_id} = json_response(conn, 200)

      %{runs: [run]} = WorkOrders.get(work_order_id, include: [:runs])

      request = Runs.get_dataclip_request(run) |> Jason.decode!()

      assert request["headers"]["authorization"] == "Basic [REDACTED]",
             "the Basic credentials Lightning already consumed must not be " <>
               "retained; the scheme is not a secret, so it stays legible"

      raw = Runs.get_dataclip_request(run)
      refute raw =~ credentials
      refute raw =~ "sup3r-s3cret-password"
    end

    test "a caller's own x-api-key survives when it is not the trigger's secret",
         %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      auth_method =
        insert(:webhook_auth_method,
          auth_type: :basic,
          username: "caller",
          password: "sup3r-s3cret-password"
        )

      associate_auth_methods(trigger, [auth_method])

      credentials = Base.encode64("caller:sup3r-s3cret-password")

      conn =
        conn
        |> put_req_header("authorization", "Basic #{credentials}")
        |> put_req_header("x-api-key", "a-token-for-the-job-to-forward")
        |> post("/i/#{trigger.id}", %{"foo" => "bar"})

      assert %{"work_order_id" => work_order_id} = json_response(conn, 200)

      %{runs: [run]} = WorkOrders.get(work_order_id, include: [:runs])

      request = Runs.get_dataclip_request(run) |> Jason.decode!()

      assert request["headers"]["authorization"] == "Basic [REDACTED]"

      assert request["headers"]["x-api-key"] ==
               "a-token-for-the-job-to-forward",
             "redaction is by value, not by header name: a token Lightning " <>
               "never consumed belongs to the caller and their job"
    end

    test "our api key is redacted from both headers webhook auth reads",
         %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      auth_method =
        insert(:webhook_auth_method,
          auth_type: :api,
          api_key: "sup3r-s3cret-api-key"
        )

      associate_auth_methods(trigger, [auth_method])

      conn =
        conn
        |> put_req_header("x-api-key", "sup3r-s3cret-api-key")
        |> put_req_header("authorization", "Bearer sup3r-s3cret-api-key")
        |> put_req_header("x-copy-of-it", "sup3r-s3cret-api-key")
        |> post("/i/#{trigger.id}", %{"foo" => "bar"})

      assert %{"work_order_id" => work_order_id} = json_response(conn, 200)

      %{runs: [run]} = WorkOrders.get(work_order_id, include: [:runs])

      request = Runs.get_dataclip_request(run) |> Jason.decode!()

      assert request["headers"]["x-api-key"] == "[REDACTED]"

      assert request["headers"]["authorization"] == "Bearer [REDACTED]",
             "auth matched on x-api-key, but the copy in the other header we " <>
               "read would otherwise be persisted intact"

      assert request["headers"]["x-copy-of-it"] == "sup3r-s3cret-api-key",
             "a header webhook auth does not read is passed through verbatim, " <>
               "secret-shaped or not"
    end

    test "cookie and proxy-authorization are redacted from dataclip.request",
         %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      conn =
        conn
        |> put_req_header("cookie", "session=a-third-party-session-cookie")
        |> put_req_header("proxy-authorization", "Basic cHJveHk6c2VjcmV0")
        |> post("/i/#{trigger.id}", %{"foo" => "bar"})

      assert %{"work_order_id" => work_order_id} = json_response(conn, 200)

      %{runs: [run]} = WorkOrders.get(work_order_id, include: [:runs])

      request = Runs.get_dataclip_request(run) |> Jason.decode!()

      assert request["headers"]["cookie"] == "[REDACTED]",
             "caller session cookies are a load-balancer/front-end concern, not run state"

      assert request["headers"]["proxy-authorization"] == "[REDACTED]"

      raw = Runs.get_dataclip_request(run)
      refute raw =~ "a-third-party-session-cookie"
      refute raw =~ "cHJveHk6c2VjcmV0"
    end

    test "non-sensitive caller headers are still passed through verbatim", %{
      conn: conn
    } do
      %{triggers: [trigger]} =
        insert(:simple_workflow)
        |> Lightning.Repo.preload(:triggers)
        |> with_snapshot()

      conn =
        conn
        |> put_req_header("x-request-id", "caller-supplied-id")
        |> put_req_header("user-agent", "acme-integration/1.2")
        |> post("/i/#{trigger.id}", %{"foo" => "bar"})

      assert %{"work_order_id" => work_order_id} = json_response(conn, 200)

      %{runs: [run]} = WorkOrders.get(work_order_id, include: [:runs])

      request = Runs.get_dataclip_request(run) |> Jason.decode!()

      assert request["headers"]["x-request-id"] == "caller-supplied-id"
      assert request["headers"]["user-agent"] == "acme-integration/1.2"
    end
  end

  defp associate_auth_methods(trigger, auth_methods) do
    trigger
    |> Repo.preload(:webhook_auth_methods)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:webhook_auth_methods, auth_methods)
    |> Repo.update!()
  end
end
