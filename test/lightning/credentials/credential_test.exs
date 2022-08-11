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
      %{id: user_id, first_name: first_name, last_name: last_name} =
        Lightning.AccountsFixtures.user_fixture(
          first_name: "Elias",
          last_name: "BA"
        )

      Lightning.Projects.create_project(%{
        name: "project-a",
        project_users: [%{user_id: user_id}]
      })

      {:ok, %Lightning.Projects.Project{id: project_id_b, name: project_name_b}} =
        Lightning.Projects.create_project(%{
          name: "project-b"
        })

      {:ok, %Lightning.Projects.Project{id: project_id_c, name: project_name_c}} =
        Lightning.Projects.create_project(%{
          name: "project-c"
        })

      errors =
        Credential.changeset(
          Lightning.CredentialsFixtures.credential_fixture(
            project_credentials: [
              %{project_id: project_id_b},
              %{project_id: project_id_c}
            ]
          ),
          %{user_id: user_id}
        )
        |> errors_on()

      assert errors[:user_id] == [
               "Invalid owner: #{first_name} #{last_name} doesn't have access to #{project_name_b}, #{project_name_c}. Please grant them access or select another owner."
             ]
    end

    test "user_id is valid for transfer" do
      %{id: user_id_1} = Lightning.AccountsFixtures.user_fixture()
      %{id: user_id_2} = Lightning.AccountsFixtures.user_fixture()

      {:ok, %Lightning.Projects.Project{id: project_id}} =
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
