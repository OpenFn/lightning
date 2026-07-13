defmodule Lightning.Accounts.SsoRegistrationNotifierTest do
  use Lightning.DataCase, async: false

  import Tesla.Mock

  alias Lightning.Accounts
  alias Lightning.Accounts.SsoRegistrationNotifier

  @url "https://example.test/i/test-webhook"

  setup do
    previous = Application.get_env(:lightning, :openfn_trigger)
    Application.put_env(:lightning, :openfn_trigger, url: @url)

    on_exit(fn ->
      if previous do
        Application.put_env(:lightning, :openfn_trigger, previous)
      else
        Application.delete_env(:lightning, :openfn_trigger)
      end
    end)

    :ok
  end

  # Extract multipart form fields as a %{name => value} map from a Tesla request.
  defp form_fields(%Tesla.Multipart{parts: parts}) do
    Map.new(parts, fn part ->
      {Keyword.get(part.dispositions, :name), part.body}
    end)
  end

  describe "perform/1" do
    test "posts a multipart registration payload with all fields" do
      test_pid = self()

      mock(fn %{method: :post, url: @url, body: body} ->
        send(test_pid, {:posted, form_fields(body)})
        %Tesla.Env{status: 200, body: ""}
      end)

      args = %{
        "new_user_id" => "usr_123",
        "email" => "ada@example.org",
        "first_name" => "Ada",
        "last_name" => "Lovelace"
      }

      assert :ok = perform_job(SsoRegistrationNotifier, args)

      assert_received {:posted, fields}

      assert fields["type"] == "registration"
      assert fields["email"] == "ada@example.org"
      assert fields["name"] == "Ada Lovelace"
      assert fields["firstName"] == "Ada"
      assert fields["lastName"] == "Lovelace"
      assert fields["new_user_id"] == "usr_123"

      # Keys are always sent, even when empty.
      for key <- ~w(project_id contactPreference industry phone organization
                    role websiteUrl intention adaptors) do
        assert fields[key] == "", "expected #{key} to be an empty string"
      end
    end

    test "derives name from only the parts present, sends missing as empty" do
      test_pid = self()

      mock(fn %{method: :post, body: body} ->
        send(test_pid, {:posted, form_fields(body)})
        %Tesla.Env{status: 200, body: ""}
      end)

      args = %{
        "new_user_id" => "usr_1",
        "email" => "solo@example.org",
        "first_name" => "Solo",
        "last_name" => nil
      }

      assert :ok = perform_job(SsoRegistrationNotifier, args)

      assert_received {:posted, fields}
      assert fields["name"] == "Solo"
      assert fields["lastName"] == ""
    end

    test "returns an error on a non-2xx response" do
      mock(fn %{method: :post} -> %Tesla.Env{status: 500, body: ""} end)

      assert {:error, :unexpected_status} =
               perform_job(SsoRegistrationNotifier, %{
                 "new_user_id" => "usr_1",
                 "email" => "x@example.org"
               })
    end

    test "skips (returns :ok) when the trigger url is not configured" do
      Application.delete_env(:lightning, :openfn_trigger)

      assert :ok =
               perform_job(SsoRegistrationNotifier, %{"new_user_id" => "usr_1"})
    end
  end

  describe "enqueue/1" do
    test "is a no-op when the trigger url is not configured" do
      Application.delete_env(:lightning, :openfn_trigger)

      user = Lightning.AccountsFixtures.user_fixture()

      # No Tesla.Mock is set, so any outbound call would fail; returning :ok
      # without raising proves nothing was posted.
      assert :ok = SsoRegistrationNotifier.enqueue(user)
    end
  end

  describe "register_user_from_sso/3 integration" do
    test "notifies the OpenFn trigger after a successful SSO registration" do
      test_pid = self()

      mock(fn %{method: :post, url: @url, body: body} ->
        send(test_pid, {:notified, form_fields(body)})
        %Tesla.Env{status: 200, body: ""}
      end)

      email = "sso-#{System.unique_integer([:positive])}@example.org"

      assert {:ok, user} =
               Accounts.register_user_from_sso(
                 %{email: email, first_name: "Sso", last_name: "User"},
                 "github",
                 "notify-1"
               )

      assert_received {:notified, fields}
      assert fields["type"] == "registration"
      assert fields["email"] == email
      assert fields["new_user_id"] == user.id
    end
  end
end
