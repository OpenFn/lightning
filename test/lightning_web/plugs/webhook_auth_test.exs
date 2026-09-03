defmodule LightningWeb.Plugs.WebhookAuthTest do
  use LightningWeb.ConnCase, async: true

  import Plug.Test
  import Lightning.Factories

  alias Lightning.Repo
  alias Lightning.WebhookAuthMethods
  alias LightningWeb.Plugs.WebhookAuth

  @moduletag capture_log: true

  setup do
    {:ok, trigger: insert(:trigger), auth_method: insert(:webhook_auth_method)}
  end

  test "OPTIONS preflight is a no-op" do
    conn = conn(:options, "/i/whatever") |> WebhookAuth.call([])
    refute conn.halted
    assert conn.status == nil
    assert conn.assigns[:trigger] == nil
  end

  test "non-/i path passes through unchanged" do
    conn = conn(:post, "/api/things") |> WebhookAuth.call([])
    refute conn.halted
    assert conn.status == nil
    assert conn.assigns[:trigger] == nil
  end

  test "responds 404 for wrong x-api-key on protected trigger", %{
    trigger: trigger
  } do
    api_method = insert(:webhook_auth_method, auth_type: :api, api_key: "secret")
    associate_auth_method(trigger, api_method)

    conn =
      conn(:post, "/i/#{trigger.id}")
      |> put_req_header("x-api-key", "nope")
      |> WebhookAuth.call([])

    assert conn.halted
    assert conn.status == 404
    assert Jason.decode!(conn.resp_body) == %{"error" => "Webhook not found"}
  end

  test "assigns trigger for matching x-api-key", %{trigger: trigger} do
    api_method = insert(:webhook_auth_method, auth_type: :api, api_key: "secret")
    associate_auth_method(trigger, api_method)

    conn =
      conn(:post, "/i/#{trigger.id}")
      |> put_req_header("x-api-key", "secret")
      |> WebhookAuth.call([])

    expected_trigger =
      trigger
      |> unload_relation(:workflow)
      |> Repo.preload([:workflow, :edges, :webhook_auth_methods])

    refute conn.halted
    assert conn.assigns[:trigger] == expected_trigger
  end

  test "returns 503 with Retry-After when DB lookup errors are exhausted" do
    Mimic.copy(Lightning.Retry)

    Mimic.expect(Lightning.Retry, :with_webhook_retry, fn _fun, _opts ->
      {:error, %DBConnection.ConnectionError{message: "db down"}}
    end)

    Mox.stub(Lightning.MockConfig, :webhook_retry, fn
      :timeout_ms -> 1_000
      _ -> nil
    end)

    conn = conn(:post, "/i/anything") |> WebhookAuth.call([])

    assert conn.halted
    assert conn.status == 503
    assert get_resp_header(conn, "retry-after") == ["1"]

    body = Jason.decode!(conn.resp_body)
    assert body["error"] == "service_unavailable"
    assert body["retry_after"] == 1
    assert String.contains?(body["message"], "retry in 1s")
  end

  test "responds with 404 when trigger doesn't exist", _context do
    conn = conn(:post, "/i/non_existent_trigger") |> WebhookAuth.call([])

    assert conn.status == 404
    assert Jason.decode!(conn.resp_body) == %{"error" => "Webhook not found"}
  end

  test "assigns the trigger when no auth method is configured", %{
    trigger: trigger
  } do
    conn = conn(:post, "/i/#{trigger.id}") |> WebhookAuth.call([])

    expected_trigger =
      trigger
      |> unload_relation(:workflow)
      |> Repo.preload([:workflow, :edges, :webhook_auth_methods])

    assert conn.assigns[:trigger] == expected_trigger
  end

  test "responds with 401 for an unauthenticated request to a protected trigger",
       %{trigger: trigger, auth_method: auth_method} do
    associate_auth_method(trigger, auth_method)

    conn = conn(:post, "/i/#{trigger.id}") |> WebhookAuth.call([])

    assert conn.status == 401
    assert Jason.decode!(conn.resp_body) == %{"error" => "Unauthorized"}
  end

  test "responds with 404 for authenticated request with non-matching auth_method",
       %{trigger: trigger, auth_method: auth_method} do
    associate_auth_method(trigger, auth_method)

    conn =
      conn(:post, "/i/#{trigger.id}")
      |> put_req_header("authorization", "Basic wrong_encoded_auth_method")
      |> WebhookAuth.call([])

    assert conn.status == 404
    assert Jason.decode!(conn.resp_body) == %{"error" => "Webhook not found"}
  end

  test "assigns the trigger for authenticated request with matching auth_method",
       %{trigger: trigger, auth_method: auth_method} do
    associate_auth_method(trigger, auth_method)

    correct_auth_method =
      "Basic " <>
        Base.encode64("#{auth_method.username}:#{auth_method.password}")

    conn =
      conn(:post, "/i/#{trigger.id}")
      |> put_req_header("authorization", correct_auth_method)
      |> WebhookAuth.call([])

    expected_trigger =
      trigger
      |> unload_relation(:workflow)
      |> Repo.preload([:workflow, :edges, :webhook_auth_methods])

    assert conn.assigns[:trigger] == expected_trigger
  end

  describe "auth methods scheduled for deletion" do
    setup %{trigger: trigger} do
      live = insert(:webhook_auth_method, auth_type: :api, api_key: "live-key")

      revoked_api =
        insert(:webhook_auth_method, auth_type: :api, api_key: "revoked-key")

      revoked_basic =
        insert(:webhook_auth_method,
          auth_type: :basic,
          username: "partner",
          password: "revoked-password"
        )

      associate_auth_methods(trigger, [live, revoked_api, revoked_basic])

      user = insert(:user)

      {:ok, _} =
        WebhookAuthMethods.schedule_for_deletion(revoked_api, actor: user)

      {:ok, _} =
        WebhookAuthMethods.schedule_for_deletion(revoked_basic, actor: user)

      :ok
    end

    test "rejects a revoked API key", %{trigger: trigger} do
      conn =
        conn(:post, "/i/#{trigger.id}")
        |> put_req_header("x-api-key", "revoked-key")
        |> WebhookAuth.call([])

      assert conn.halted
      assert conn.status == 404
      refute conn.assigns[:trigger]
    end

    test "rejects revoked basic credentials", %{trigger: trigger} do
      encoded = Base.encode64("partner:revoked-password")

      conn =
        conn(:post, "/i/#{trigger.id}")
        |> put_req_header("authorization", "Basic #{encoded}")
        |> WebhookAuth.call([])

      assert conn.halted
      assert conn.status == 404
      refute conn.assigns[:trigger]
    end

    test "the remaining live API key still authenticates", %{trigger: trigger} do
      conn =
        conn(:post, "/i/#{trigger.id}")
        |> put_req_header("x-api-key", "live-key")
        |> WebhookAuth.call([])

      refute conn.halted
      assert conn.assigns[:trigger].id == trigger.id
    end
  end

  # The trigger-side counterpart of the channel test in
  # channel_proxy_plug_test.exs: cutting the last join row revokes the
  # credential and leaves an open webhook. The delete modal warns about this
  # before the operator confirms, so it is the intended trade rather than a
  # bug, but it should be visible in the suite.
  test "revoking a trigger's only auth method leaves the webhook open", %{
    trigger: trigger
  } do
    only = insert(:webhook_auth_method, auth_type: :api, api_key: "only-key")
    associate_auth_method(trigger, only)

    {:ok, _} =
      WebhookAuthMethods.schedule_for_deletion(only, actor: insert(:user))

    conn = conn(:post, "/i/#{trigger.id}") |> WebhookAuth.call([])

    refute conn.halted
    assert conn.assigns[:trigger].id == trigger.id

    # The revoked key isn't rejected so much as ignored: with no methods left
    # the trigger authenticates nobody, so the same request succeeds too.
    conn =
      conn(:post, "/i/#{trigger.id}")
      |> put_req_header("x-api-key", "only-key")
      |> WebhookAuth.call([])

    refute conn.halted
    assert conn.assigns[:trigger].id == trigger.id
  end

  defp associate_auth_method(trigger, auth_method) do
    associate_auth_methods(trigger, [auth_method])
  end

  defp associate_auth_methods(trigger, auth_methods) do
    trigger
    |> Repo.preload(:webhook_auth_methods)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:webhook_auth_methods, auth_methods)
    |> Repo.update!()
  end
end
