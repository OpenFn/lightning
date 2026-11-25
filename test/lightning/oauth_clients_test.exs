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
    test "returns oauth clients associated with a given project" do
      [project_1, project_2, project_3] = insert_list(3, :project)

      client_1 =
        insert(:oauth_client,
          name: "bbb",
          project_oauth_clients: [%{project: project_1}, %{project: project_2}]
        )

      client_2 =
        insert(:oauth_client,
          name: "aaa",
          project_oauth_clients: [%{project: project_1}]
        )

      client_3 = insert(:oauth_client)

      project_1_clients = OauthClients.list_clients(project_1)

      names = Enum.map(project_1_clients, & &1.name)
      assert names == Enum.sort_by(names, &String.downcase/1)

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

    test "returns global oauth clients even when they are not associated to a given project or user" do
      project = insert(:project)
      user = insert(:user)

      projects_clients = OauthClients.list_clients(project)
      users_clients = OauthClients.list_clients(user)

      assert Enum.empty?(projects_clients)
      assert Enum.empty?(users_clients)

      global_client = insert(:oauth_client, global: true)

      projects_clients = OauthClients.list_clients(project)
      users_clients = OauthClients.list_clients(user)

      assert length(projects_clients) == 1
      assert length(users_clients) == 1

      project_client = List.first(projects_clients)
      user_client = List.first(users_clients)

      assert project_client.id == global_client.id
      assert user_client.id == global_client.id
    end

    test "returns oauth clients associated with a given user" do
      [user_1, user_2] = insert_list(2, :user)

      client_1 = insert(:oauth_client, user: user_1)

      client_2 = insert(:oauth_client, user: user_2)

      user_1_clients = OauthClients.list_clients(user_1)
      user_2_clients = OauthClients.list_clients(user_2)

      assert length(user_1_clients) == 1
      assert length(user_2_clients) == 1

      assert client_id_in_list?(client_1, user_1_clients)
      assert client_id_in_list?(client_2, user_2_clients)

      refute client_id_in_list?(client_1, user_2_clients)
      refute client_id_in_list?(client_2, user_1_clients)
    end
  end

  describe "list_clients/2" do
    test "returns a paginated page of oauth clients for a user" do
      user = insert(:user)
      for _i <- 1..12, do: insert(:oauth_client, user: user)

      page =
        OauthClients.list_clients(user, %{"page" => "1", "page_size" => "10"})

      assert %Scrivener.Page{} = page
      assert page.page_size == 10
      assert page.total_entries >= 12
      assert length(page.entries) == 10

      page2 =
        OauthClients.list_clients(user, %{"page" => "2", "page_size" => "10"})

      assert page2.page_number == 2
      assert length(page2.entries) > 0
    end

    test "returns a paginated page of oauth clients for a project, including globals" do
      user = insert(:user)
      project = insert(:project)
      other_project = insert(:project)

      project_clients =
        for _i <- 1..3,
            do:
              insert(:oauth_client,
                user: user,
                project_oauth_clients: [%{project: project}]
              )

      new_global = insert(:oauth_client, global: true, user: user)

      other_client =
        insert(:oauth_client,
          user: user,
          project_oauth_clients: [%{project: other_project}]
        )

      page =
        OauthClients.list_clients(project, %{"page" => "1", "page_size" => "100"})

      assert %Scrivener.Page{} = page
      assert client_id_in_list?(new_global, page.entries)
      assert Enum.all?(project_clients, &client_id_in_list?(&1, page.entries))
      refute client_id_in_list?(other_client, page.entries)
    end
  end

  describe "list_clients/3" do
    defp list_client_ids(project_or_user, opts) do
      page = OauthClients.list_clients(project_or_user, %{"page" => "1"}, opts)
      Enum.map(page.entries, & &1.id)
    end

    defp list_client_names(project_or_user, opts) do
      page = OauthClients.list_clients(project_or_user, %{"page" => "1"}, opts)
      Enum.map(page.entries, & &1.name)
    end

    test "search matches a client's name, URL, owner and projects, ignoring case" do
      project = insert(:project)
      shared_project = insert(:project, name: "shared-project")

      by_name =
        insert(:oauth_client,
          name: "Acme Login",
          project_oauth_clients: [%{project: project}]
        )

      by_url =
        insert(:oauth_client,
          authorization_endpoint: "https://login.example.org/authorize",
          project_oauth_clients: [%{project: project}]
        )

      by_owner =
        insert(:oauth_client,
          user: build(:user, email: "client-owner@example.com"),
          project_oauth_clients: [%{project: project}]
        )

      by_project =
        insert(:oauth_client,
          project_oauth_clients: [
            %{project: project},
            %{project: shared_project}
          ]
        )

      # Matches the name, but belongs to another project.
      insert(:oauth_client,
        name: "Acme Other",
        project_oauth_clients: [%{project: insert(:project)}]
      )

      for {term, client} <- [
            {"ACME", by_name},
            {"login.example.org", by_url},
            {"client-owner", by_owner},
            {"shared-project", by_project}
          ] do
        assert list_client_ids(project, search: term) == [client.id]
      end

      assert list_client_ids(project, search: "no such client") == []
      assert length(list_client_ids(project, search: "")) == 4
    end

    test "search only returns a user's own clients and global clients" do
      user = insert(:user)
      own = insert(:oauth_client, user: user, name: "Acme Own")
      global = insert(:oauth_client, global: true, name: "Acme Global")
      insert(:oauth_client, name: "Acme Stranger")

      assert user |> list_client_ids(search: "acme") |> Enum.sort() ==
               Enum.sort([own.id, global.id])
    end

    test "search doesn't reveal the hidden owner and projects of a global client" do
      user = insert(:user)

      global =
        insert(:oauth_client,
          global: true,
          name: "Shared Client",
          user: build(:user, email: "hidden-owner@example.com"),
          project_oauth_clients: [
            %{project: insert(:project, name: "hidden-project")}
          ]
        )

      assert list_client_ids(user, search: "hidden-owner") == []
      assert list_client_ids(user, search: "hidden-project") == []

      assert list_client_ids(user, search: "shared client") == [global.id]
      assert list_client_ids(user, search: "global") == [global.id]
    end

    test "sorts by name, ignoring case" do
      user = insert(:user)

      for name <- ["beta", "Alpha", "gamma"],
          do: insert(:oauth_client, user: user, name: name)

      assert list_client_names(user, []) == ["Alpha", "beta", "gamma"]

      assert list_client_names(user, order_by: {:name, :desc}) ==
               ["gamma", "beta", "Alpha"]
    end

    test "sorts by owner, treating a global client's owner as global" do
      project = insert(:project)

      for {name, email} <- [
            {"zeta's", "zeta@example.com"},
            {"alpha's", "Alpha@example.com"}
          ] do
        insert(:oauth_client,
          name: name,
          user: build(:user, email: email),
          project_oauth_clients: [%{project: project}]
        )
      end

      insert(:oauth_client,
        name: "global",
        global: true,
        user: build(:user, email: "mallory@example.com")
      )

      assert list_client_names(project, order_by: {:owner, :asc}) ==
               ["alpha's", "global", "zeta's"]

      assert list_client_names(project, order_by: {:owner, :desc}) ==
               ["zeta's", "global", "alpha's"]
    end

    test "paginates only the matching clients, in a stable order" do
      user = insert(:user)

      owned_by_user =
        insert_list(5, :oauth_client, user: user, name: "same name")

      insert(:oauth_client, user: user, name: "unrelated")

      ids =
        Enum.flat_map(["1", "2", "3"], fn page_number ->
          page =
            OauthClients.list_clients(
              user,
              %{"page" => page_number, "page_size" => "2"},
              search: "same name"
            )

          assert page.total_entries == 5
          Enum.map(page.entries, & &1.id)
        end)

      assert ids == owned_by_user |> Enum.map(& &1.id) |> Enum.sort()
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
        revocation_endpoint: "https://www.example.com/revoke",
        token_endpoint: "https://www.example.com",
        user_id: user.id,
        project_oauth_clients: [%{project_id: project.id}]
      }

      {:ok, client} = OauthClients.create_client(attrs, user)

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
      user = insert(:user)
      attrs = %{name: nil, user_id: user.id}
      {:error, changeset} = OauthClients.create_client(attrs, user)

      assert changeset.valid? == false
      assert changeset.errors[:name] != nil
    end
  end

  describe "update_client/2 with project association changes" do
    test "updates client and modifies project associations" do
      user = insert(:user)

      client =
        insert(:oauth_client, name: "Old Name", user: user)
        |> Repo.preload(:project_oauth_clients)

      [_project, another_project] = insert_list(2, :project)

      updated_attrs = %{
        name: "Updated Name",
        project_oauth_clients: [%{project_id: another_project.id}]
      }

      {:ok, updated_client} =
        OauthClients.update_client(client, updated_attrs, user)

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
      user = insert(:user)

      client =
        %{project_oauth_clients: [poc]} =
        insert(:oauth_client,
          name: "Test Client",
          user: user,
          project_oauth_clients: [%{project: project}]
        )
        |> Repo.preload(:project_oauth_clients)

      updated_attrs = %{
        project_oauth_clients: [
          %{id: poc.id, project_id: project.id, delete: true}
        ]
      }

      {:ok, updated_client} =
        OauthClients.update_client(client, updated_attrs, user)

      assert audit_logged?(updated_client, "updated")
      assert audit_logged?(updated_client, "removed_from_project")
      refute audit_logged?(updated_client, "added_to_project")

      refute Enum.any?(OauthClients.list_clients(project), fn c ->
               c.id == updated_client.id
             end)
    end

    test "returns an error when update fails due to invalid data" do
      user = insert(:user)
      client = insert(:oauth_client, user: user)

      invalid_attrs = %{name: nil}

      {:error, changeset} =
        OauthClients.update_client(client, invalid_attrs, user)

      refute audit_logged?(client, "updated")

      assert changeset.valid? == false
      assert changeset.errors[:name] != nil
    end
  end

  describe "delete_client/1" do
    test "deletes a client successfully" do
      user = insert(:user)
      client = insert(:oauth_client, user: user)

      assert {:ok,
              %{
                audit: %Lightning.Auditing.Audit{} = audit,
                client: %Lightning.Credentials.OauthClient{} = oauth_client
              }} = OauthClients.delete_client(client, user)

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
    test "updating a client from non global to global, doesn't affect project oauth clients" do
      user = insert(:user)
      project_1 = insert(:project, name: "Project 1")
      _project_2 = insert(:project, name: "Project 2")

      {:ok, client} =
        OauthClients.create_client(
          %{
            name: "Global Client",
            client_id: "client_id",
            client_secret: "client_secret",
            authorization_endpoint: "https://www.example.com",
            revocation_endpoint: "https://www.example.com/revoke",
            token_endpoint: "https://www.example.com",
            user_id: user.id,
            global: false,
            project_oauth_clients: [%{project_id: project_1.id}]
          },
          user
        )

      client = Repo.preload(client, :project_oauth_clients)

      associations = Repo.all(ProjectOauthClient)

      assert associations |> Enum.count() == 1

      assert list_audits(client, "updated")
             |> Enum.count() == 0

      assert list_audits(client, "created")
             |> Enum.count() == 1

      assert list_audits(client, "added_to_project")
             |> Enum.count() == 1

      assert list_audits(client, "removed_from_projects")
             |> Enum.count() == 0

      Repo.delete_all(Lightning.Auditing.Audit)

      {:ok, client} =
        OauthClients.update_client(client, %{global: true}, user,
          allow_global: true
        )

      associations = Repo.all(ProjectOauthClient)

      assert associations |> Enum.count() == 1

      assert list_audits(client, "updated")
             |> Enum.count() == 1

      assert list_audits(client, "created")
             |> Enum.count() == 0

      assert list_audits(client, "added_to_project")
             |> Enum.count() == 0

      assert list_audits(client, "removed_from_projects")
             |> Enum.count() == 0
    end

    test "updating a client from global to non global while associating it to specific projects, associates it only to those projects" do
      user = insert(:user)
      _project_1 = insert(:project, name: "Project 1")
      _project_2 = insert(:project, name: "Project 2")

      {:ok, client} =
        OauthClients.create_client(
          %{
            name: "Global Client",
            client_id: "client_id",
            client_secret: "client_secret",
            authorization_endpoint: "https://www.example.com",
            revocation_endpoint: "https://www.example.com/revoke",
            token_endpoint: "https://www.example.com",
            user_id: user.id,
            global: true
          },
          user,
          allow_global: true
        )

      client = Repo.preload(client, :project_oauth_clients)

      associations = Repo.all(ProjectOauthClient)

      assert list_audits(client, "created")
             |> Enum.count() === 1

      assert associations |> Enum.count() == 0

      # To ignore the first addition due to setting the client as global
      Repo.delete_all(Lightning.Auditing.Audit)

      project_3 = insert(:project, name: "Project 3")

      {:ok, client} =
        OauthClients.update_client(
          client,
          %{
            global: false,
            project_oauth_clients:
              associations
              |> Enum.map(fn poc ->
                %{id: poc.id, project_id: poc.project_id, delete: poc.delete}
              end)
              |> Enum.concat([%{project_id: project_3.id}])
          },
          user,
          allow_global: true
        )

      associations = Repo.all(ProjectOauthClient)

      assert associations |> Enum.count() == 1

      assert list_audits(client, "updated")
             |> Enum.count() === 1

      assert list_audits(client, "added_to_project")
             |> Enum.count() === 1
    end

    @client_attrs %{
      name: "Client",
      client_id: "client_id",
      client_secret: "client_secret",
      authorization_endpoint: "https://www.example.com",
      token_endpoint: "https://www.example.com"
    }

    test "create_client drops :global unless allow_global is set" do
      user = insert(:user)
      attrs = Map.merge(@client_attrs, %{user_id: user.id, global: true})

      {:ok, client} = OauthClients.create_client(attrs, user)
      refute client.global

      {:ok, global_client} =
        OauthClients.create_client(attrs, user, allow_global: true)

      assert global_client.global
    end

    test "update_client cannot set :global unless allow_global is set" do
      user = insert(:user)
      client = insert(:oauth_client, global: false, user: user)

      {:ok, unchanged} =
        OauthClients.update_client(client, %{global: true}, user)

      refute unchanged.global

      {:ok, promoted} =
        OauthClients.update_client(client, %{global: true}, user,
          allow_global: true
        )

      assert promoted.global
    end
  end

  describe "ownership" do
    test "a user who does not own a client cannot create, update or delete it" do
      owner = insert(:user)
      stranger = insert(:user)
      client = insert(:oauth_client, name: "Owned Client", user: owner)

      # Creation asks about the owner named in the attrs, not about the person
      # calling, so a stranger cannot make a client that belongs to someone
      # else.
      assert {:error, :unauthorized} =
               OauthClients.create_client(
                 %{
                   name: "Planted Client",
                   client_id: "client_id",
                   client_secret: "client_secret",
                   authorization_endpoint: "https://www.example.com",
                   revocation_endpoint: "https://www.example.com/revoke",
                   token_endpoint: "https://www.example.com",
                   user_id: owner.id
                 },
                 stranger
               )

      refute Repo.get_by(OauthClient, name: "Planted Client")

      assert {:error, :unauthorized} =
               OauthClients.update_client(client, %{name: "Hijacked"}, stranger)

      assert {:error, :unauthorized} =
               OauthClients.delete_client(client, stranger)

      reloaded = Repo.get!(OauthClient, client.id)
      assert reloaded.name == "Owned Client"
    end

    test "an update cannot move a client into somebody else's account" do
      # Ownership is what the guard above asks about, so an update that could
      # write :user_id would let the owner hand the client, and the secret they
      # already know, to another account. The form params reach the changeset
      # unfiltered, so the schema has to be the thing that refuses.
      owner = insert(:user)
      stranger = insert(:user)
      client = insert(:oauth_client, name: "Mine", user: owner)

      assert {:ok, updated} =
               OauthClients.update_client(
                 client,
                 %{"name" => "Still mine", "user_id" => stranger.id},
                 owner
               )

      assert updated.user_id == owner.id
      assert Repo.get!(OauthClient, client.id).user_id == owner.id
    end
  end
end
