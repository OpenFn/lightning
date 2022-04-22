defmodule Lightning.CredentialsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials

  describe "credentials" do
    alias Lightning.Credentials.Credential

    import Lightning.CredentialsFixtures

    @invalid_attrs %{body: nil, name: nil}

    test "list_credentials/0 returns all credentials" do
      credential = credential_fixture()
      assert Credentials.list_credentials() == [credential]
    end

    test "get_credential!/1 returns the credential with given id" do
      credential = credential_fixture()
      assert Credentials.get_credential!(credential.id) == credential
    end

    test "get_credential_body/1 returns the credentials body" do
      credential_body = %{"username" => "foo"}
      credential = credential_fixture(body: credential_body)

      assert Credentials.get_credential_body(credential) |> Jason.decode!() ==
               credential_body

      assert Credentials.get_credential_body(%Credential{id: Ecto.UUID.generate()}) == nil
    end

    test "create_credential/1 with valid data creates a credential" do
      valid_attrs = %{body: %{}, name: "some name"}

      assert {:ok, %Credential{} = credential} = Credentials.create_credential(valid_attrs)
      assert credential.body == %{}
      assert credential.name == "some name"
    end

    test "create_credential/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Credentials.create_credential(@invalid_attrs)
    end

    test "update_credential/2 with valid data updates the credential" do
      credential = credential_fixture()
      update_attrs = %{body: %{}, name: "some updated name"}

      assert {:ok, %Credential{} = credential} =
               Credentials.update_credential(credential, update_attrs)

      assert credential.body == %{}
      assert credential.name == "some updated name"
    end

    test "update_credential/2 with invalid data returns error changeset" do
      credential = credential_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Credentials.update_credential(credential, @invalid_attrs)

      assert credential == Credentials.get_credential!(credential.id)
    end

    test "delete_credential/1 deletes the credential" do
      credential = credential_fixture()
      assert {:ok, %Credential{}} = Credentials.delete_credential(credential)
      assert_raise Ecto.NoResultsError, fn -> Credentials.get_credential!(credential.id) end
    end

    test "change_credential/1 returns a credential changeset" do
      credential = credential_fixture()
      assert %Ecto.Changeset{} = Credentials.change_credential(credential)
    end
  end
end
