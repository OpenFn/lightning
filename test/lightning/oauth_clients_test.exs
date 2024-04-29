defmodule Lightning.OauthClientsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.OauthClient
  alias Lightning.OauthClients
  alias Lightning.Repo

  describe "list_clients/1" do
    test "returns all oauth clients for a given project" do
      project = insert(:project)

      _client1 =
        insert_list(2, :oauth_client,
          project_oauth_clients: [
            %{project_id: project.id}
          ]
        )

      _client2 = insert(:oauth_client)

      result = OauthClients.list_clients(project)
      assert length(result) == 2
      assert Enum.all?(result, fn client -> client.project_id == project.id end)
    end
  end

  describe "create_client/1" do
    test "creates a new oauth client successfully" do
      attrs = %{name: "New Client", project_id: 123}
      {:ok, client} = OauthClients.create_client(attrs)

      assert client.name == "New Client"
      assert client.project_id == 123
      assert Repo.get!(OauthClient, client.id)
    end

    test "fails to create an oauth client with invalid data" do
      # assuming name is required
      attrs = %{name: nil}
      {:error, changeset} = OauthClients.create_client(attrs)

      assert changeset.valid? == false
      assert changeset.errors[:name] != nil
    end
  end

  describe "update_client/2" do
    test "updates an existing client successfully" do
      client = %OauthClient{name: "Old Name"} |> Repo.insert!()
      updated_attrs = %{name: "Updated Name"}
      {:ok, updated_client} = OauthClients.update_client(client, updated_attrs)

      assert updated_client.name == "Updated Name"
      assert updated_client.id == client.id
    end

    test "returns an error when update fails due to invalid data" do
      client = %OauthClient{name: "Initial Name"} |> Repo.insert!()
      # assuming name is required
      invalid_attrs = %{name: nil}
      {:error, changeset} = OauthClients.update_client(client, invalid_attrs)

      assert changeset.valid? == false
      assert changeset.errors[:name] != nil
    end
  end

  describe "delete_client/1" do
    test "deletes a client successfully" do
      client = %OauthClient{name: "Delete Me"} |> Repo.insert!()
      assert Repo.get!(OauthClient, client.id)

      {:ok, _deleted_client} = OauthClients.delete_client(client)

      assert_raise Ecto.NoResultsError, fn ->
        Repo.get!(OauthClient, client.id)
      end
    end

    test "handles errors when deleting a non-existing client" do
      # client does not exist in the database
      fake_client = %OauthClient{id: -1, name: "Non-existent"}
      {:error, _reason} = OauthClients.delete_client(fake_client)

      # Just checking error path; specific error checks would depend on the implementation
      assert true
    end
  end
end
