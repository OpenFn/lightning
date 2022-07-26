defmodule Lightning.CredentialsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials
  alias Lightning.Credentials.{Credential, Audit}
  import Lightning.{CredentialsFixtures, AccountsFixtures, ProjectsFixtures}
  import Ecto.Query

  describe "Model interactions" do
    @invalid_attrs %{body: nil, name: nil}

    test "list_credentials_for_user/1 returns all credentials for given user" do
      user_1 = user_fixture()
      user_2 = user_fixture()
      credential_1 = credential_fixture(user_id: user_1.id)
      credential_2 = credential_fixture(user_id: user_2.id)

      assert Credentials.list_credentials_for_user(user_1.id) == [
               credential_1
             ]

      assert Credentials.list_credentials_for_user(user_2.id) == [
               credential_2
             ]
    end

    test "list_credentials/0 returns all credentials" do
      user = user_fixture()
      credential = credential_fixture(user_id: user.id)
      assert Credentials.list_credentials() == [credential]
    end

    test "list_credentials/1 returns all credentials for a project" do
      user = user_fixture()
      project = project_fixture(project_users: [%{user_id: user.id}])

      credential =
        credential_fixture(
          user_id: user.id,
          project_credentials: [%{project_id: project.id}]
        )

      assert Credentials.list_credentials(project) == [
               credential |> unload_relation(:project_credentials)
             ]
    end

    test "get_credential!/1 returns the credential with given id" do
      user = user_fixture()
      credential = credential_fixture(user_id: user.id)
      assert Credentials.get_credential!(credential.id) == credential
    end

    test "create_credential/1 with valid data creates a credential" do
      valid_attrs = %{body: %{}, name: "some name", user_id: user_fixture().id}

      assert {:ok, %Credential{} = credential} =
               Credentials.create_credential(valid_attrs)

      assert credential.body == %{}
      assert credential.name == "some name"

      assert from(a in Audit,
               where: a.row_id == ^credential.id and a.event == "created"
             )
             |> Repo.one!(),
             "Has exactly one 'created' event"
    end

    test "create_credential/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               Credentials.create_credential(@invalid_attrs)
    end

    test "update_credential/2 with valid data updates the credential" do
      user = user_fixture()
      credential = credential_fixture(user_id: user.id)
      update_attrs = %{body: %{}, name: "some updated name"}

      assert {:ok, %Credential{} = credential} =
               Credentials.update_credential(credential, update_attrs)

      assert credential.body == %{}
      assert credential.name == "some updated name"
    end

    test "update_credential/2 with invalid data returns error changeset" do
      user = user_fixture()
      credential = credential_fixture(user_id: user.id)

      assert {:error, %Ecto.Changeset{}} =
               Credentials.update_credential(credential, @invalid_attrs)

      assert credential == Credentials.get_credential!(credential.id)
    end

    test "delete_credential/1 deletes the credential" do
      user = user_fixture()
      credential = credential_fixture(user_id: user.id)
      assert {:ok, %Credential{}} = Credentials.delete_credential(credential)

      assert_raise Ecto.NoResultsError, fn ->
        Credentials.get_credential!(credential.id)
      end
    end

    test "change_credential/1 returns a credential changeset" do
      user = user_fixture()
      credential = credential_fixture(user_id: user.id)
      assert %Ecto.Changeset{} = Credentials.change_credential(credential)
    end
  end

  describe "get_sensitive_values/1" do
    test "collects up all values" do
      credential =
        credential_fixture(
          body: %{
            "loginUrl" => "https://login.salesforce.com",
            "user" => %{
              "email" => "demo@openfn.org",
              "password" => "shhh",
              "scopes" => ["read/write", "admin"]
            },
            "security_token" => nil,
            "port" => 75
          }
        )

      secrets = ["admin", "read/write", "shhh", 75]

      assert Credentials.sensitive_values_for(credential) == secrets
      assert Credentials.sensitive_values_for(credential.id) == secrets
    end
  end
end
