defmodule Lightning.Credentials.OauthClientTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.ProjectOauthClient
  alias Lightning.Credentials.OauthClient
  alias Lightning.Projects.Project

  describe "changeset/2" do
    setup do
      oauth_client = %OauthClient{id: Ecto.UUID.generate()}
      project = %Project{id: Ecto.UUID.generate()}

      [oauth_client: oauth_client, project: project]
    end

    test "creates a valid changeset with required attributes", %{
      oauth_client: oauth_client,
      project: project
    } do
      attrs = %{
        oauth_client_id: oauth_client.id,
        project_id: project.id
      }

      changeset = ProjectOauthClient.changeset(%ProjectOauthClient{}, attrs)

      assert changeset.valid?
    end

    test "validates presence of required fields", _context do
      changeset = ProjectOauthClient.changeset(%ProjectOauthClient{}, %{})

      assert [project_id: {"can't be blank", [validation: :required]}] ===
               changeset.errors
    end

    test "enforces unique constraint on project_id and oauth_client_id combination",
         %{oauth_client: oauth_client, project: project} do
      attrs = %{
        oauth_client_id: oauth_client.id,
        project_id: project.id
      }

      changeset = ProjectOauthClient.changeset(%ProjectOauthClient{}, attrs)

      opts = [
        constraint: :unique,
        constraint_name: "project_oauth_clients_oauth_client_id_project_id_index"
      ]

      changeset =
        Ecto.Changeset.add_error(
          changeset,
          :project_id,
          "oauth client already added to this project.",
          opts
        )

      refute changeset.valid?

      assert "oauth client already added to this project." ==
               changeset.errors[:project_id] |> elem(0)
    end

    test "handles delete action in changeset when delete attribute is true",
         _context do
      changeset =
        ProjectOauthClient.changeset(%ProjectOauthClient{}, %{"delete" => "true"})

      assert changeset.valid?
      assert changeset.action == :delete
      assert changeset.changes.delete == true
    end
  end
end
