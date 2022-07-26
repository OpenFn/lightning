defmodule Lightning.Credentials.AuditTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.{Audit, Credential}
  import Lightning.{AccountsFixtures, CredentialsFixtures}

  describe "event/4" do
    test "created" do
      user = user_fixture()

      credential =
        credential_fixture(user_id: user.id, body: %{"my-secret" => "value"})

      {:ok, audit} =
        Audit.event("created", credential.id, user.id)
        |> Audit.save()

      assert audit.row_id == credential.id
      assert %{before: nil, after: nil} = audit.metadata
      assert audit.event == "created"
      assert audit.actor_id == user.id
    end

    test "updated" do
      user = user_fixture()

      credential = credential_fixture(user_id: user.id, body: %{})

      changeset =
        Credential.changeset(credential, %{body: %{"my-secret" => "value"}})

      {:ok, audit} =
        Audit.event("updated", credential.id, user.id, changeset)
        |> Audit.save()

      assert audit.row_id == credential.id

      # Check that the body attribute is encrypted in audit records too.
      # We can only test the beginning of the encypted string as the
      # algorithm include randomness or padding of some sort.
      # %{}
      assert audit.metadata.before.body =~ "AQpBRVMuR0NNLlYx"
      # %{"my-secret" => "value}
      assert audit.metadata.after.body =~ "AQpBRVMuR0NNLlYx"

      assert audit.event == "updated"
      assert audit.actor_id == user.id
    end
  end
end
