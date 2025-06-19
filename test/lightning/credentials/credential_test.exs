defmodule Lightning.Credentials.CredentialTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials
  alias Lightning.Credentials.Credential

  describe "changeset/2" do
    test "name, body, and user_id can't be blank" do
      errors = Credential.changeset(%Credential{}, %{}) |> errors_on()
      assert errors[:name] == ["can't be blank"]
      assert errors[:body] == ["can't be blank"]
      assert errors[:user_id] == ["can't be blank"]
    end

    test "oauth credentials require access_token, refresh_token, and expires_in or expires_at to be valid" do
      assert_invalid_oauth_credential(
        %{},
        "Invalid token format. Unable to extract scope information"
      )

      assert_invalid_oauth_credential(
        %{"access_token" => "access_token_123", "scope" => "read write"},
        "Missing refresh_token for new OAuth connection"
      )

      assert_invalid_oauth_credential(
        %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "scope" => "read write"
        },
        "Missing expiration field: either expires_in or expires_at is required"
      )

      refute_invalid_oauth_credential(%{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "scope" => "read write",
        "expires_at" => 3245
      })

      refute_invalid_oauth_credential(%{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "scope" => "read write",
        "expires_in" => 3245
      })
    end
  end

  describe "encryption" do
    test "encrypts a credential at rest" do
      body = %{"foo" => [1]}

      %{id: credential_id, body: decoded_body} =
        Credential.changeset(%Credential{}, %{
          name: "Test Credential",
          body: body,
          user_id: Lightning.AccountsFixtures.user_fixture().id,
          schema: "raw"
        })
        |> Lightning.Repo.insert!()

      assert decoded_body == body

      persisted_body =
        from(c in Credential,
          select: type(c.body, :string),
          where: c.id == ^credential_id
        )
        |> Lightning.Repo.one!()

      refute persisted_body == body
    end
  end

  defp assert_invalid_oauth_credential(body, message) do
    errors =
      Credentials.change_credential(%Credential{}, %{
        name: "oauth credential",
        schema: "oauth",
        oauth_token: body,
        user_id: insert(:user).id
      })
      |> errors_on()

    assert errors[:oauth_token] == [message]
  end

  defp refute_invalid_oauth_credential(body) do
    errors =
      Credentials.change_credential(%Credential{}, %{
        name: "oauth credential",
        schema: "oauth",
        body: %{},
        oauth_token: body,
        user_id: insert(:user).id
      })
      |> errors_on()

    refute errors[:oauth_token]
  end
end
