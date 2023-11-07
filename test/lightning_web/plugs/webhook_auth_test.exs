defmodule LightningWeb.Plugs.WebhookAuthTest do
  use LightningWeb.ConnCase, async: true

  import Plug.Test
  import Lightning.Factories

  alias LightningWeb.Plugs.WebhookAuth
  alias Lightning.Repo

  setup do
    {:ok, trigger: insert(:trigger), auth_method: insert(:webhook_auth_method)}
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
      |> Repo.preload([:workflow, :edges])

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
      |> Repo.preload([:workflow, :edges])

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
