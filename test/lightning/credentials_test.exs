defmodule Lightning.CredentialsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Repo
  alias Lightning.Credentials
  alias Lightning.Credentials.{Credential, Audit}

  import Lightning.{
    JobsFixtures,
    CredentialsFixtures,
    AccountsFixtures,
    ProjectsFixtures
  }

  import Ecto.Query

  describe "Model interactions" do
    @invalid_attrs %{body: nil, name: nil}

    test "list_credentials_for_user/1 returns all credentials for given user" do
      user_1 = user_fixture()
      user_2 = user_fixture()

      credential_1 =
        credential_fixture(user_id: user_1.id) |> Repo.preload(:projects)

      credential_2 =
        credential_fixture(user_id: user_2.id) |> Repo.preload(:projects)

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
          user: user,
          project_credentials: [%{project_id: project.id}]
        )
        |> Repo.preload(:user)

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
      valid_attrs = %{
        body: %{},
        name: "some name",
        user_id: user_fixture().id,
        schema: "raw",
        project_credentials: [
          %{project_id: project_fixture().id}
        ]
      }

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

      {:ok, %Lightning.Projects.Project{id: project_id}} =
        Lightning.Projects.create_project(%{
          name: "some-name",
          project_users: [%{user_id: user.id}]
        })

      credential =
        credential_fixture(
          user_id: user.id,
          project_credentials: [
            %{project_id: project_id}
          ]
        )

      original_project_credential =
        Enum.at(credential.project_credentials, 0)
        |> Map.from_struct()

      new_project = project_fixture()

      update_attrs = %{
        body: %{},
        name: "some updated name",
        project_credentials: [
          original_project_credential,
          %{project_id: new_project.id}
        ]
      }

      assert {:ok, %Credential{} = credential} =
               Credentials.update_credential(credential, update_attrs)

      assert credential.body == %{}
      assert credential.name == "some updated name"

      audit_events =
        from(a in Audit,
          where: a.row_id == ^credential.id,
          select: {a.event, type(a.metadata, :map)}
        )
        |> Repo.all()

      assert {"created", %{"after" => nil, "before" => nil}} in audit_events

      assert {"updated",
              %{
                "before" => %{"name" => "some name"},
                "after" => %{"name" => "some updated name"}
              }} in audit_events

      assert {"added_to_project",
              %{
                "before" => %{"project_id" => nil},
                "after" => %{"project_id" => new_project.id}
              }} in audit_events
    end

    test "update_credential/2 with invalid data returns error changeset" do
      user = user_fixture()
      credential = credential_fixture(user_id: user.id)

      assert {:error, %Ecto.Changeset{}} =
               Credentials.update_credential(credential, @invalid_attrs)

      assert credential == Credentials.get_credential!(credential.id)
    end

    test "delete_credential/1 deletes a credential and removes it from associated jobs and projects" do
      user = user_fixture()

      project = project_fixture(user_id: user.id)

      project_credential =
        project_credential_fixture(user_id: user.id, project_id: project.id)

      credential_id = project_credential.credential_id

      %{job: job} =
        workflow_job_fixture(
          project: project,
          project_credential: project_credential
        )

      # 1 project_credential created
      assert length(
               Lightning.Projects.list_project_credentials(
                 %Lightning.Projects.Project{
                   id: project_credential.project_id
                 }
               )
             ) == 1

      assert {:ok,
              %{
                audit: %Lightning.Credentials.Audit{} = audit,
                credential: %Credential{} = credential
              }} =
               Credentials.delete_credential(%Lightning.Credentials.Credential{
                 id: credential_id,
                 user_id: user.id
               })

      assert audit.event == "deleted"
      assert audit.row_id == credential_id

      # previous  audit records are not deleted
      # a new audit (event: deleted) is added
      assert from(a in Lightning.Credentials.Audit,
               where: a.row_id == ^credential.id
             )
             |> Repo.all()
             |> Enum.all?(fn a ->
               a.row_id == credential.id &&
                 a.event in ["created", "updated", "deleted", "added_to_project"]
             end)

      assert_raise Ecto.NoResultsError, fn ->
        Credentials.get_credential!(credential.id)
      end

      # no more project_credentials
      assert length(
               Lightning.Projects.list_project_credentials(
                 %Lightning.Projects.Project{
                   id: project_credential.project_id
                 }
               )
             ) == 0

      job = Repo.get!(Lightning.Jobs.Job, job.id)

      assert job.project_credential_id == nil
    end

    test "change_credential/1 returns a credential changeset" do
      user = user_fixture()
      credential = credential_fixture(user_id: user.id)
      assert %Ecto.Changeset{} = Credentials.change_credential(credential)
    end

    test "invalid_projects_for_user/2 returns a list of invalid projects, given a credential and a user" do
      %{id: user_id_1} = Lightning.AccountsFixtures.user_fixture()
      %{id: user_id_2} = Lightning.AccountsFixtures.user_fixture()
      %{id: user_id_3} = Lightning.AccountsFixtures.user_fixture()

      {:ok, %Lightning.Projects.Project{id: project_id}} =
        Lightning.Projects.create_project(%{
          name: "some-name",
          project_users: [%{user_id: user_id_1}, %{user_id: user_id_2}]
        })

      credential =
        Lightning.CredentialsFixtures.credential_fixture(
          user_id: user_id_1,
          project_credentials: [%{project_id: project_id}]
        )

      assert Credentials.invalid_projects_for_user(
               credential.id,
               user_id_2
             ) == []

      assert Credentials.invalid_projects_for_user(
               credential.id,
               user_id_3
             ) ==
               [project_id]
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
