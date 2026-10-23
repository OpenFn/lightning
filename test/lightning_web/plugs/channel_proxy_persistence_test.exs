defmodule LightningWeb.ChannelProxyPersistenceTest do
  use LightningWeb.ConnCase, async: true

  alias Lightning.Channels.{ChannelRequest, ChannelEvent}

  import Ecto.Query
  import Lightning.Factories
  import LightningWeb.API.ChannelProxyHelpers
  import Plug.Test, only: [conn: 2, conn: 3]

  setup do
    bypass = Bypass.open()
    project = insert(:project)

    channel =
      insert(:channel,
        project: project,
        destination_url: "http://localhost:#{bypass.port}",
        enabled: true
      )

    disabled_channel =
      insert(:channel,
        project: project,
        destination_url: "http://localhost:#{bypass.port}",
        enabled: false
      )

    {:ok, bypass: bypass, channel: channel, disabled_channel: disabled_channel}
  end

  describe "handler persistence" do
    test "creates ChannelRequest and ChannelEvent on successful proxy", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/persisted", fn conn ->
        Plug.Conn.send_resp(conn, 200, "persisted response")
      end)

      resp = get(conn, "/channels/#{channel.id}/persisted")
      assert resp.status == 200

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.state == :success
      assert request.completed_at != nil

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent, where: e.channel_request_id == ^request.id)
        )

      assert event.type == :destination_response
      assert event.response_status == 200
      assert event.latency_us != nil
      assert event.request_method == "GET"
      assert event.request_path == "/persisted"
    end

    test "creates error-state request on connection failure", %{
      conn: conn,
      channel: channel
    } do
      port = Enum.random(59_000..59_999)

      channel
      |> Ecto.Changeset.change(destination_url: "http://localhost:#{port}")
      |> Lightning.Repo.update!()

      resp = get(conn, "/channels/#{channel.id}/fail")
      assert resp.status in [502, 504]

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.state in [:error, :timeout]
      assert request.completed_at != nil
    end
  end

  describe "query string persistence" do
    test "persists query string on channel event", %{
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/search", fn conn ->
        Plug.Conn.send_resp(conn, 200, "results")
      end)

      conn(:get, "/channels/#{channel.id}/search?q=foo&page=2")
      |> send_to_endpoint()

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent,
            join: r in ChannelRequest,
            on: r.id == e.channel_request_id,
            where: r.channel_id == ^channel.id
          )
        )

      assert event.request_query_string == "q=foo&page=2"
    end

    test "empty query string when no params", %{
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/plain", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      conn(:get, "/channels/#{channel.id}/plain")
      |> send_to_endpoint()

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent,
            join: r in ChannelRequest,
            on: r.id == e.channel_request_id,
            where: r.channel_id == ^channel.id
          )
        )

      assert event.request_query_string == ""
    end
  end

  describe "client auth tracking" do
    test "persists auth method ID and type for API key auth", %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :api, api_key: "track-me"}
        ])

      auth_method =
        channel
        |> Lightning.Repo.preload(client_webhook_auth_methods: [])
        |> Map.get(:client_webhook_auth_methods)
        |> hd()

      Bypass.expect_once(bypass, "GET", "/tracked", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      conn(:get, "/channels/#{channel.id}/tracked")
      |> put_req_header("x-api-key", "track-me")
      |> send_to_endpoint()

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.client_webhook_auth_method_id == auth_method.id
      assert request.client_auth_type == "api"
    end

    test "persists auth method ID and type for Basic auth", %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :basic, username: "user", password: "pass"}
        ])

      auth_method =
        channel
        |> Lightning.Repo.preload(client_webhook_auth_methods: [])
        |> Map.get(:client_webhook_auth_methods)
        |> hd()

      Bypass.expect_once(bypass, "GET", "/tracked", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      encoded = Base.encode64("user:pass")

      conn(:get, "/channels/#{channel.id}/tracked")
      |> put_req_header("authorization", "Basic #{encoded}")
      |> send_to_endpoint()

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.client_webhook_auth_method_id == auth_method.id
      assert request.client_auth_type == "basic"
    end

    test "nil auth method when no client auth configured", %{
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/open", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      conn(:get, "/channels/#{channel.id}/open")
      |> send_to_endpoint()

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.client_webhook_auth_method_id == nil
      assert request.client_auth_type == nil
    end
  end

  describe "destination auth tracking" do
    test "persists destination_credential_id on successful proxy with destination auth",
         %{bypass: bypass} do
      channel =
        create_destination_auth_channel(bypass, "@openfn/language-http", %{
          "access_token" => "tok-123"
        })

      project_credential_id =
        channel
        |> Lightning.Repo.preload(destination_auth_method: :project_credential)
        |> get_in([
          Access.key(:destination_auth_method),
          Access.key(:project_credential_id)
        ])

      Bypass.expect_once(bypass, "GET", "/dest-track", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      conn(:get, "/channels/#{channel.id}/dest-track")
      |> send_to_endpoint()

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.destination_credential_id == project_credential_id
      refute is_nil(project_credential_id)
    end

    test "persists destination_credential_id even when credential resolution fails",
         %{bypass: _bypass} do
      # Channel with a destination auth method but credential missing auth
      # fields — destination auth resolution fails, but we still know which
      # credential was configured.
      project = insert(:project)
      user = insert(:user)

      credential =
        insert(:credential,
          schema: "@openfn/language-http",
          name: "bad-cred",
          user: user
        )
        |> with_body(%{body: %{"baseUrl" => "https://example.com"}})

      project_credential =
        insert(:project_credential, project: project, credential: credential)

      channel =
        insert(:channel,
          project: project,
          destination_url: "http://localhost:9999",
          enabled: true,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :destination,
              webhook_auth_method: nil,
              project_credential: project_credential
            )
          ]
        )

      resp =
        conn(:get, "/channels/#{channel.id}/test")
        |> send_to_endpoint()

      assert resp.status == 502

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.destination_credential_id == project_credential.id
      assert request.state == :error
    end

    test "destination_credential_id is nil when no destination auth configured",
         %{bypass: bypass, channel: channel} do
      Bypass.expect_once(bypass, "GET", "/no-dest-auth", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      conn(:get, "/channels/#{channel.id}/no-dest-auth")
      |> send_to_endpoint()

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.destination_credential_id == nil
    end
  end

  describe "collect_timing integration" do
    test "persists per-direction timing after successful proxy", %{
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/timed", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      conn(:get, "/channels/#{channel.id}/timed")
      |> send_to_endpoint()

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent,
            join: r in ChannelRequest,
            on: r.id == e.channel_request_id,
            where: r.channel_id == ^channel.id
          )
        )

      # With collect_timing: true, Philter populates timing.send_us
      # which the handler persists as request_send_us
      assert is_integer(event.request_send_us)
      assert event.request_send_us >= 0
    end
  end

  describe "zero-persistence scrubbing" do
    test "happy path: scrubs PII fields and sets is_wiped: true under :erase_all",
         %{bypass: bypass} do
      project = insert(:project, retention_policy: :erase_all)

      channel =
        insert(:channel,
          project: project,
          destination_url: "http://localhost:#{bypass.port}",
          enabled: true
        )

      body = Jason.encode!(%{"hello" => "world"})

      Bypass.expect_once(bypass, "POST", "/erase/path", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-custom-header", "value")
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, ~s({"ok":true}))
      end)

      resp =
        conn(:post, "/channels/#{channel.id}/erase/path?secret=abc", body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("content-length", "#{byte_size(body)}")
        |> put_req_header("x-api-key", "some-key")
        |> send_to_endpoint()

      assert resp.status == 200

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert %ChannelRequest{
               state: :success,
               client_identity: nil,
               is_wiped: true
             } = request

      assert request.started_at != nil
      assert request.completed_at != nil
      assert is_binary(request.request_id)

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent, where: e.channel_request_id == ^request.id)
        )

      # All eight scrubbed fields are nil on the event; is_wiped lives on the request.
      assert %ChannelEvent{
               request_path: nil,
               request_query_string: nil,
               request_headers: nil,
               request_body_preview: nil,
               request_body_hash: nil,
               response_headers: nil,
               response_body_preview: nil,
               response_body_hash: nil
             } = event

      # Observability fields remain populated.
      assert event.request_method == "POST"
      assert event.response_status == 200
      assert is_integer(event.latency_us) and event.latency_us > 0
      assert event.request_body_size == byte_size(body)

      assert is_integer(event.response_body_size) and
               event.response_body_size > 0
    end

    test "happy path: retains all PII fields and sets is_wiped: false under :retain_all",
         %{bypass: bypass} do
      project = insert(:project, retention_policy: :retain_all)

      channel =
        insert(:channel,
          project: project,
          destination_url: "http://localhost:#{bypass.port}",
          enabled: true
        )

      body = Jason.encode!(%{"hello" => "world"})

      Bypass.expect_once(bypass, "POST", "/retain/path", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-custom-header", "value")
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, ~s({"ok":true}))
      end)

      resp =
        conn(:post, "/channels/#{channel.id}/retain/path?secret=abc", body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("content-length", "#{byte_size(body)}")
        |> put_req_header("x-api-key", "some-key")
        |> send_to_endpoint()

      assert resp.status == 200

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.state == :success
      assert request.completed_at != nil
      assert request.is_wiped == false
      refute is_nil(request.client_identity)

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent, where: e.channel_request_id == ^request.id)
        )

      assert event.request_method == "POST"
      assert event.request_path == "/retain/path"
      assert event.request_query_string == "secret=abc"
      assert event.response_status == 200
      assert is_list(event.request_headers) and event.request_headers != []
      assert is_list(event.response_headers) and event.response_headers != []
      assert is_binary(event.request_body_preview)
      assert is_binary(event.request_body_hash)
      assert is_binary(event.response_body_preview)
      assert is_binary(event.response_body_hash)
      assert is_integer(event.latency_us) and event.latency_us > 0
      assert event.request_body_size == byte_size(body)
    end

    test "credential-error path: scrubs request_path and client_identity, sets is_wiped: true, but keeps request_method and error_message",
         %{bypass: bypass} do
      project = insert(:project, retention_policy: :erase_all)
      user = insert(:user)

      credential =
        insert(:credential,
          schema: "@openfn/language-http",
          name: "no-body",
          user: user
        )

      # Don't call with_body — no CredentialBody exists, so credential
      # resolution will fail and `record_credential_error/3` is invoked.

      project_credential =
        insert(:project_credential,
          project: project,
          credential: credential
        )

      channel =
        insert(:channel,
          project: project,
          destination_url: "http://localhost:#{bypass.port}",
          enabled: true,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :destination,
              webhook_auth_method: nil,
              project_credential: project_credential
            )
          ]
        )

      resp =
        conn(:get, "/channels/#{channel.id}/secret-path")
        |> send_to_endpoint()

      assert resp.status == 502

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert %ChannelRequest{
               state: :error,
               client_identity: nil,
               is_wiped: true
             } = request

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent, where: e.channel_request_id == ^request.id)
        )

      assert %ChannelEvent{
               type: :error,
               request_path: nil,
               request_method: "GET",
               error_message: "credential_environment_not_found"
             } = event
    end

    test "credential-error path: leaves request_path populated and request.is_wiped: false under :retain_all (default)",
         %{bypass: bypass} do
      project = insert(:project, retention_policy: :retain_all)
      user = insert(:user)

      credential =
        insert(:credential,
          schema: "@openfn/language-http",
          name: "no-body",
          user: user
        )

      project_credential =
        insert(:project_credential,
          project: project,
          credential: credential
        )

      channel =
        insert(:channel,
          project: project,
          destination_url: "http://localhost:#{bypass.port}",
          enabled: true,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :destination,
              webhook_auth_method: nil,
              project_credential: project_credential
            )
          ]
        )

      resp =
        conn(:get, "/channels/#{channel.id}/keep-path")
        |> send_to_endpoint()

      assert resp.status == 502

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.state == :error
      assert request.is_wiped == false
      refute is_nil(request.client_identity)

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent, where: e.channel_request_id == ^request.id)
        )

      assert %ChannelEvent{
               type: :error,
               request_path: "/channels/" <> _,
               request_method: "GET",
               error_message: "credential_environment_not_found"
             } = event
    end
  end

  describe "request telemetry" do
    setup do
      test_pid = self()
      handler_id = "channel-proxy-test-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach_many(
          handler_id,
          [
            [:lightning, :channel_proxy, :inbound, :stop],
            [:lightning, :channel_proxy, :request, :start],
            [:lightning, :channel_proxy, :request, :stop]
          ],
          fn event, measurements, metadata, _config ->
            if self() == test_pid do
              send(test_pid, {:telemetry, event, measurements, metadata})
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      :ok
    end

    test "resolved channel: outer :inbound :stop and inner :request :start/:stop fire with real UUIDs",
         %{bypass: bypass, channel: channel} do
      Bypass.expect_once(bypass, "GET", "/observed", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/observed")
        |> send_to_endpoint()

      assert resp.status == 200

      expected_channel_id = channel.id
      expected_project_id = channel.project_id

      # Outer span carries outcome + resolved IDs (real UUIDs, never "unknown").
      assert_receive {:telemetry, [:lightning, :channel_proxy, :inbound, :stop],
                      _measurements, inbound_meta}

      assert %{
               outcome: :resolved,
               status: 200,
               channel_id: ^expected_channel_id,
               project_id: ^expected_project_id
             } = inbound_meta

      # Inner span fires only on the resolved path. :start metadata already
      # carries the resolved project_id (the whole point of the split).
      assert_receive {:telemetry, [:lightning, :channel_proxy, :request, :start],
                      _measurements, start_meta}

      assert %{
               channel_id: ^expected_channel_id,
               project_id: ^expected_project_id
             } = start_meta

      assert_receive {:telemetry, [:lightning, :channel_proxy, :request, :stop],
                      %{duration: duration}, stop_meta}

      assert is_integer(duration) and duration > 0

      assert %{
               channel_id: ^expected_channel_id,
               project_id: ^expected_project_id,
               status: 200
             } = stop_meta
    end

    test "unknown channel: outer :inbound :stop fires with :unknown_channel and no inner events",
         %{conn: conn} do
      missing_id = "00000000-0000-0000-0000-000000000000"

      resp = get(conn, "/channels/#{missing_id}/whatever")

      assert resp.status == 404

      assert_receive {:telemetry, [:lightning, :channel_proxy, :inbound, :stop],
                      _measurements, inbound_meta}

      assert %{outcome: :unknown_channel, status: 404} = inbound_meta
      refute Map.has_key?(inbound_meta, :channel_id)
      refute Map.has_key?(inbound_meta, :project_id)

      # The inner :request span never opens for unknown channels.
      refute_receive {:telemetry, [:lightning, :channel_proxy, :request, :start],
                      _, _}

      refute_receive {:telemetry, [:lightning, :channel_proxy, :request, :stop],
                      _, _}
    end

    test "invalid UUID: outer :inbound :stop fires with :invalid_uuid and no inner events",
         %{conn: conn} do
      resp = get(conn, "/channels/not-a-uuid/whatever")

      assert resp.status == 404

      assert_receive {:telemetry, [:lightning, :channel_proxy, :inbound, :stop],
                      _measurements, inbound_meta}

      assert %{outcome: :invalid_uuid, status: 404} = inbound_meta
      refute Map.has_key?(inbound_meta, :channel_id)
      refute Map.has_key?(inbound_meta, :project_id)

      refute_receive {:telemetry, [:lightning, :channel_proxy, :request, :start],
                      _, _}

      refute_receive {:telemetry, [:lightning, :channel_proxy, :request, :stop],
                      _, _}
    end

    test "401 unauthorized: outer :inbound and inner :request both fire (auth lives inside inner span)",
         %{bypass: bypass} do
      project = insert(:project)

      channel =
        insert(:channel,
          project: project,
          destination_url: "http://localhost:#{bypass.port}",
          enabled: true,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :client,
              webhook_auth_method:
                build(:webhook_auth_method,
                  project: project,
                  auth_type: :api,
                  api_key: "correct-key"
                )
            )
          ]
        )

      resp =
        conn(:get, "/channels/#{channel.id}/protected")
        |> put_req_header("x-api-key", "wrong-key")
        |> send_to_endpoint()

      assert resp.status == 401

      expected_channel_id = channel.id
      expected_project_id = channel.project_id

      assert_receive {:telemetry, [:lightning, :channel_proxy, :inbound, :stop],
                      _measurements, inbound_meta}

      assert %{
               outcome: :resolved,
               status: 401,
               channel_id: ^expected_channel_id,
               project_id: ^expected_project_id
             } = inbound_meta

      assert_receive {:telemetry, [:lightning, :channel_proxy, :request, :start],
                      _measurements, start_meta}

      assert %{
               channel_id: ^expected_channel_id,
               project_id: ^expected_project_id
             } = start_meta

      assert_receive {:telemetry, [:lightning, :channel_proxy, :request, :stop],
                      _measurements, stop_meta}

      assert %{
               channel_id: ^expected_channel_id,
               project_id: ^expected_project_id,
               status: 401
             } = stop_meta
    end
  end
end
