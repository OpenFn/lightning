defmodule Lightning.OauthClientsTest do
  alias Lightning.Projects.ProjectOauthClient
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.OauthClient
  alias Lightning.OauthClients
  alias Lightning.Repo

  defp client_id_in_list?(client, clients) do
    Enum.any?(clients, fn c -> c.id == client.id end)
  end

  defp list_audits(record, event_type) do
    from(a in Lightning.Credentials.OauthClientAudit.base_query(),
      where: a.item_id == ^record.id and a.event == ^event_type
    )
    |> Repo.all()
  end

  defp audit_logged?(record, event_type) do
    list_audits(record, event_type) |> Enum.count() >= 1
  end

  describe "list_clients/1" do
    test "returns only oauth clients associated with a given project" do
      [project_1, project_2, project_3] = insert_list(3, :project)

      client_1 =
        insert(:oauth_client,
          project_oauth_clients: [%{project: project_1}, %{project: project_2}]
        )

      client_2 =
        insert(:oauth_client, project_oauth_clients: [%{project: project_1}])

      client_3 = insert(:oauth_client)

      project_1_clients = OauthClients.list_clients(project_1)
      project_2_clients = OauthClients.list_clients(project_2)
      project_3_clients = OauthClients.list_clients(project_3)

      assert length(project_1_clients) === 2
      assert length(project_2_clients) === 1
      assert length(project_3_clients) === 0

      assert client_id_in_list?(client_1, project_1_clients)
      assert client_id_in_list?(client_2, project_1_clients)
      refute client_id_in_list?(client_3, project_1_clients)

      assert client_id_in_list?(client_1, project_2_clients)
      refute client_id_in_list?(client_2, project_2_clients)
      refute client_id_in_list?(client_3, project_2_clients)

      refute client_id_in_list?(client_1, project_3_clients)
      refute client_id_in_list?(client_2, project_3_clients)
      refute client_id_in_list?(client_3, project_3_clients)
    end
  end

  describe "create_client/1 with project association" do
    test "successfully creates a client and associates with a project" do
      user = insert(:user)
      project = insert(:project)

      attrs = %{
        name: "New Client",
        client_id: "client_id",
        client_secret: "client_secret",
        authorization_endpoint: "https://www.example.com",
        token_endpoint: "https://www.example.com",
        user_id: user.id,
        project_oauth_clients: [%{project_id: project.id}]
      }

      {:ok, client} = OauthClients.create_client(attrs)

      assert audit_logged?(client, "created")
      assert audit_logged?(client, "added_to_project")

      assert client.name == "New Client"
      assert client.user_id == user.id
      assert Repo.get!(OauthClient, client.id)

      assert OauthClients.list_clients(project)
             |> Enum.any?(fn c ->
               c.id == client.id
             end)
    end

    test "fails to create an oauth client with invalid data" do
      attrs = %{name: nil}
      {:error, changeset} = OauthClients.create_client(attrs)

      assert changeset.valid? == false
      assert changeset.errors[:name] != nil
    end
  end

  describe "update_client/2 with project association changes" do
    test "updates client and modifies project associations" do
      client =
        insert(:oauth_client, name: "Old Name")
        |> Repo.preload(:project_oauth_clients)

      [_project, another_project] = insert_list(2, :project)

      updated_attrs = %{
        name: "Updated Name",
        project_oauth_clients: [%{project_id: another_project.id}]
      }

      {:ok, updated_client} = OauthClients.update_client(client, updated_attrs)

      assert audit_logged?(updated_client, "updated")
      assert audit_logged?(updated_client, "added_to_project")

      assert updated_client.name == "Updated Name"
      assert updated_client.id == client.id

      assert OauthClients.list_clients(another_project)
             |> Enum.any?(fn c ->
               c.id == updated_client.id
             end)
    end

    test "removes a project association and logs the event" do
      project = insert(:project)

      client =
        insert(:oauth_client,
          name: "Test Client",
          project_oauth_clients: [%{project: project}]
        )

      updated_attrs = %{
        project_oauth_clients: []
      }

      {:ok, updated_client} = OauthClients.update_client(client, updated_attrs)

      assert audit_logged?(updated_client, "updated")
      assert audit_logged?(updated_client, "removed_from_project")
      refute audit_logged?(updated_client, "added_to_project")

      refute Enum.any?(OauthClients.list_clients(project), fn c ->
               c.id == updated_client.id
             end)
    end

    test "returns an error when update fails due to invalid data" do
      client = insert(:oauth_client)

      invalid_attrs = %{name: nil}
      {:error, changeset} = OauthClients.update_client(client, invalid_attrs)

      refute audit_logged?(client, "updated")

      assert changeset.valid? == false
      assert changeset.errors[:name] != nil
    end
  end

  describe "delete_client/1" do
    test "deletes a client successfully" do
      client = insert(:oauth_client)

      assert {:ok,
              %{
                audit: %Lightning.Auditing.Audit{} = audit,
                client: %Lightning.Credentials.OauthClient{} = oauth_client
              }} = OauthClients.delete_client(client)

      assert audit.event == "deleted"
      assert audit.item_id == oauth_client.id

      assert audit_logged?(client, "deleted")

      assert_raise Ecto.NoResultsError, fn ->
        Repo.get!(OauthClient, client.id)
      end

      all_project_oauth_clients =
        Lightning.Repo.all(Lightning.Projects.ProjectOauthClient)

      refute Enum.any?(all_project_oauth_clients, fn poc ->
               poc.client_id === client.id
             end)
    end
  end

  describe "global clients" do
    test "non global clients are not associated to all projects of the instance" do
      user = insert(:user)
      project_1 = insert(:project, name: "Project 1")
      project_2 = insert(:project, name: "Project 2")

      {:ok, non_global_client} =
        OauthClients.create_client(%{
          name: "Non Global Client",
          client_id: "client_id",
          client_secret: "client_secret",
          authorization_endpoint: "https://www.example.com",
          token_endpoint: "https://www.example.com",
          user_id: user.id,
          global: false
        })

      refute non_global_client.global
      assert Repo.all(ProjectOauthClient) |> Enum.empty?()

      assert list_audits(non_global_client, "created")
             |> Enum.count() === 1

      assert list_audits(non_global_client, "added_to_project")
             |> Enum.count() === 0

      {:ok, non_global_client} =
        OauthClients.create_client(%{
          name: "Non Global Client",
          client_id: "client_id",
          client_secret: "client_secret",
          authorization_endpoint: "https://www.example.com",
          token_endpoint: "https://www.example.com",
          user_id: user.id,
          global: false,
          project_oauth_clients: [%{project_id: project_1.id}]
        })

      associated_projects =
        Repo.all(ProjectOauthClient)
        |> Enum.map(fn assoc ->
          {assoc.project_id, assoc.oauth_client_id}
        end)

      refute non_global_client.global

      assert associated_projects |> Enum.count() === 1

      assert associated_projects === [{project_1.id, non_global_client.id}]

      refute associated_projects === [{project_2.id, non_global_client}]

      assert list_audits(non_global_client, "created")
             |> Enum.count() === 1

      assert list_audits(non_global_client, "added_to_project")
             |> Enum.count() === 1
    end

    test "global clients are associated to all projects of the instance" do
      user = insert(:user)
      project_1 = insert(:project, name: "Project 1")
      project_2 = insert(:project, name: "Project 2")

      {:ok, global_client} =
        OauthClients.create_client(%{
          name: "Global Client",
          client_id: "client_id",
          client_secret: "client_secret",
          authorization_endpoint: "https://www.example.com",
          token_endpoint: "https://www.example.com",
          user_id: user.id,
          global: true
        })

      associations = Repo.all(ProjectOauthClient)

      assert global_client.global
      refute associations |> Enum.empty?()

      assert associations
             |> Enum.map(fn %{project_id: project_id, oauth_client_id: client_id} ->
               {project_id, client_id}
             end) == [
               {project_1.id, global_client.id},
               {project_2.id, global_client.id}
             ]

      assert list_audits(global_client, "created")
             |> Enum.count() === 1

      assert list_audits(global_client, "added_to_project")
             |> Enum.count() === 2
    end

    test "updating a client from global to non global, disassociates it with all the projects of the instance" do
      user = insert(:user)
      _project_1 = insert(:project, name: "Project 1")
      _project_2 = insert(:project, name: "Project 2")

      {:ok, client} =
        OauthClients.create_client(%{
          name: "Global Client",
          client_id: "client_id",
          client_secret: "client_secret",
          authorization_endpoint: "https://www.example.com",
          token_endpoint: "https://www.example.com",
          user_id: user.id,
          global: true
        })

      associations = Repo.all(ProjectOauthClient)

      assert associations |> Enum.count() == 2

      {:ok, client} =
        OauthClients.update_client(client, %{global: false})

      associations = Repo.all(ProjectOauthClient)

      assert associations |> Enum.count() == 0

      assert list_audits(client, "created")
             |> Enum.count() === 1

      assert list_audits(client, "updated")
             |> Enum.count() === 1

      assert list_audits(client, "removed_from_project")
             |> Enum.count() === 2
    end

    test "updating a client from non global to global, associates it to all the projects of the insance" do
      user = insert(:user)
      _project_1 = insert(:project, name: "Project 1")
      _project_2 = insert(:project, name: "Project 2")

      {:ok, client} =
        OauthClients.create_client(%{
          name: "Global Client",
          client_id: "client_id",
          client_secret: "client_secret",
          authorization_endpoint: "https://www.example.com",
          token_endpoint: "https://www.example.com",
          user_id: user.id,
          global: false
        })

      client = Repo.preload(client, :project_oauth_clients)

      associations = Repo.all(ProjectOauthClient)

      assert associations |> Enum.count() == 0

      {:ok, client} =
        OauthClients.update_client(client, %{global: true})

      associations = Repo.all(ProjectOauthClient)

      assert associations |> Enum.count() == 2

      assert list_audits(client, "created")
             |> Enum.count() === 1

      assert list_audits(client, "updated")
             |> Enum.count() === 1

      assert list_audits(client, "added_to_project")
             |> Enum.count() === 2
    end

    test "updating a client from global to non global while associating it to specific projects, associates it only to those projects" do
      user = insert(:user)
      project_1 = insert(:project, name: "Project 1")
      _project_2 = insert(:project, name: "Project 2")

      {:ok, client} =
        OauthClients.create_client(%{
          name: "Global Client",
          client_id: "client_id",
          client_secret: "client_secret",
          authorization_endpoint: "https://www.example.com",
          token_endpoint: "https://www.example.com",
          user_id: user.id,
          global: true
        })

      associations = Repo.all(ProjectOauthClient)

      assert list_audits(client, "created")
             |> Enum.count() === 1

      assert associations |> Enum.count() == 2

      # To ignore the first addition due to setting the client as global
      Repo.delete_all(Lightning.Auditing.Audit)

      {:ok, client} =
        OauthClients.update_client(client, %{
          global: false,
          project_oauth_clients: [%{project_id: project_1.id}]
        })

      associations = Repo.all(ProjectOauthClient)

      assert associations |> Enum.count() == 1

      assert list_audits(client, "updated")
             |> Enum.count() === 1

      assert list_audits(client, "added_to_project")
             |> Enum.count() === 1
    end
  end
end
