defmodule Lightning.Credentials.AuditTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.{Audit, Credential}
  import Lightning.{AccountsFixtures, CredentialsFixtures}

  describe "event/4" do
    test "generates 'created' audit trail entries" do
      user = user_fixture()

      credential =
        credential_fixture(user_id: user.id, body: %{"my-secret" => "value"})

      {:ok, audit} =
        Audit.event("created", credential.id, user.id)
        |> Audit.save()

      assert audit.item_type == "credential"
      assert audit.item_id == credential.id
      assert %{before: nil, after: nil} = audit.changes
      assert audit.event == "created"
      assert audit.actor_id == user.id
    end

    test "generates 'updated' audit trail entries" do
      user = user_fixture()

      credential = credential_fixture(user_id: user.id, body: %{})

      changeset =
        Credential.changeset(credential, %{body: %{"my-secret" => "value"}})

      {:ok, audit} =
        Audit.event("updated", credential.id, user.id, changeset)
        |> Audit.save()

      assert audit.item_type == "credential"
      assert audit.item_id == credential.id

      # Check that the body attribute is encrypted in audit records too.
      # We can only test the beginning of the encrypted string as the
      # algorithm include randomness or padding of some sort.
      # %{}
      assert audit.changes.before.body =~ "AQpBRVMuR0NNLlYx"
      # %{"my-secret" => "value}
      assert audit.changes.after.body =~ "AQpBRVMuR0NNLlYx"

      assert audit.event == "updated"
      assert audit.actor_id == user.id
    end

    test "generates 'deleted' audit trail entries" do
      user = user_fixture()

      credential =
        credential_fixture(user_id: user.id, body: %{"my-secret" => "value"})

      {:ok, audit} =
        Audit.event("deleted", credential.id, user.id)
        |> Audit.save()

      assert audit.item_type == "credential"
      assert audit.item_id == credential.id

      assert audit.changes == %Lightning.Auditing.Model.Changes{
               before: nil,
               after: nil
             }

      assert audit.event == "deleted"
      assert audit.actor_id == user.id
    end
  end
end
