defmodule Lightning.OauthClientsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.OauthClient
  alias Lightning.OauthClients
  alias Lightning.Repo

  defp client_id_in_list?(client, clients) do
    Enum.any?(clients, fn c -> c.id == client.id end)
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

  describe "create_client/1" do
    test "creates a new oauth client successfully" do
      user = insert(:user)

      attrs = %{
        name: "New Client",
        client_id: "client_id",
        client_secret: "client_secret",
        authorization_endpoint: "https://www.example.com",
        token_endpoint: "https://www.example.com",
        user_id: user.id
      }

      {:ok, client} = OauthClients.create_client(attrs)

      assert client.name == "New Client"
      assert client.user_id == user.id
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
      client = insert(:oauth_client, name: "Old Name")
      updated_attrs = %{name: "Updated Name"}
      {:ok, updated_client} = OauthClients.update_client(client, updated_attrs)

      assert updated_client.name == "Updated Name"
      assert updated_client.id == client.id
    end

    test "returns an error when update fails due to invalid data" do
      client = insert(:oauth_client)

      invalid_attrs = %{name: nil}
      {:error, changeset} = OauthClients.update_client(client, invalid_attrs)

      assert changeset.valid? == false
      assert changeset.errors[:name] != nil
    end
  end

  describe "delete_client/1" do
    test "deletes a client successfully" do
      client = insert(:oauth_client)
      assert Repo.get!(OauthClient, client.id)

      {:ok, _deleted_client} = OauthClients.delete_client(client)

      assert_raise Ecto.NoResultsError, fn ->
        Repo.get!(OauthClient, client.id)
      end
    end
  end
end
