defmodule Lightning.Credentials.CredentialTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.Credential

  describe "changeset/2" do
    test "name, body, and user_id can't be blank" do
      errors = Credential.changeset(%Credential{}, %{}) |> errors_on()
      assert errors[:name] == ["can't be blank"]
      assert errors[:body] == ["can't be blank"]
      assert errors[:user_id] == ["can't be blank"]
    end

    test "user_id not valid for transfer" do
      %{id: user_id} = Lightning.AccountsFixtures.user_fixture()

      Lightning.Projects.create_project(%{
        name: "some-name",
        project_users: [%{user_id: user_id}]
      })

      errors =
        Credential.changeset(
          Lightning.CredentialsFixtures.credential_fixture(),
          %{user_id: user_id}
        )
        |> errors_on()

      assert errors[:user_id] == [
               "Transfer impossible, this user doesn't have access to some of the projects using this credential; please grant the user access to all the project using this credential or share it with another user"
             ]
    end

    test "user_id is valid for transfer" do
      %{id: user_id_1} = Lightning.AccountsFixtures.user_fixture()
      %{id: user_id_2} = Lightning.AccountsFixtures.user_fixture()

      {:ok, %Lightning.Projects.Project{id: project_id} = project} =
        Lightning.Projects.create_project(%{
          name: "some-name",
          project_users: [%{user_id: user_id_1, user_id: user_id_2}]
        })

      credential =
        Lightning.CredentialsFixtures.credential_fixture(
          user_id: user_id_1,
          project_credentials: [%{project_id: project_id}]
        )

      errors =
        Credential.changeset(
          credential,
          %{user_id: user_id_2}
        )
        |> errors_on()

      assert errors[:user_id] == nil
    end
  end

  describe "encryption" do
    test "encrypts a credential at rest" do
      body = %{"foo" => [1]}

      %{id: credential_id, body: decoded_body} =
        Credential.changeset(%Credential{}, %{
          name: "Test Credential",
          body: body,
          user_id: Lightning.AccountsFixtures.user_fixture().id
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
end
