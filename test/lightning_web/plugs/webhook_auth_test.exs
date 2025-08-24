defmodule LightningWeb.Plugs.WebhookAuthTest do
  use LightningWeb.ConnCase, async: true

  import Plug.Test
  import Lightning.Factories

  alias LightningWeb.Plugs.WebhookAuth
  alias Lightning.Repo

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
    assert Jason.decode!(conn.resp_body) == %{"error" => "webhook_not_found"}
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
    assert Jason.decode!(conn.resp_body) == %{"error" => "webhook_not_found"}
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
    assert Jason.decode!(conn.resp_body) == %{"error" => "webhook_not_found"}
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

  defp associate_auth_method(trigger, auth_method) do
    trigger
    |> Repo.preload(:webhook_auth_methods)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:webhook_auth_methods, [auth_method])
    |> Repo.update!()
  end
end
