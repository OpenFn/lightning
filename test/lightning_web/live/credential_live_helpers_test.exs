defmodule LightningWeb.CredentialLive.HelpersTest do
  use Lightning.DataCase

  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.OauthClient
  alias LightningWeb.CredentialLive.Helpers

  setup do
    available_projects = [%{id: 1}, %{id: 2}]
    selected_projects = []
    projects = [%{id: 1}, %{id: 2}, %{id: 3}]

    {:ok,
     projects: projects,
     available_projects: available_projects,
     selected_projects: selected_projects}
  end

  describe "prepare_projects_associations/3" do
    test "identifies projects to add, delete, and keep correctly" do
      projects =
        [project_1, project_2, project_3, project_4, project_5] =
        insert_list(5, :project)

      credential =
        insert(:credential,
          project_credentials: [
            %{project_id: project_1.id},
            %{project_id: project_2.id},
            %{project_id: project_3.id}
          ]
        )

      oauth_client =
        insert(:oauth_client,
          project_oauth_clients: [
            %{project_id: project_1.id},
            %{project_id: project_2.id},
            %{project_id: project_3.id}
          ]
        )

      credential_changeset = Credential.changeset(credential, %{})
      oauth_client_changeset = OauthClient.changeset(oauth_client, %{})

      selected_projects = [project_2, project_3, project_4, project_5]

      scenario = %{
        deleted: [project_1],
        added: [project_4, project_5],
        kept: [project_2, project_3]
      }

      [
        {:project_oauth_clients, oauth_client_changeset},
        {:project_credentials, credential_changeset}
      ]
      |> Enum.each(fn {key, changeset} ->
        result =
          Helpers.prepare_projects_associations(
            changeset,
            selected_projects,
            key
          )

        assert length(result) == length(projects)

        deleted_projects =
          Enum.filter(result, fn assoc ->
            Map.get(assoc, "delete") == "true"
          end)

        assert Enum.map(deleted_projects, & &1["project_id"]) ==
                 Enum.map(scenario.deleted, & &1.id)

        added_projects =
          Enum.filter(result, fn assoc ->
            is_nil(Map.get(assoc, "id"))
          end)

        assert Enum.map(added_projects, & &1["project_id"]) |> Enum.sort() ==
                 Enum.map(scenario.added, & &1.id) |> Enum.sort()

        kept_projects =
          Enum.filter(result, fn assoc ->
            Map.has_key?(assoc, "id") and not Map.has_key?(assoc, "delete")
          end)

        assert Enum.map(kept_projects, & &1["project_id"]) ==
                 Enum.map(scenario.kept, & &1.id)
      end)
    end
  end

  describe "filter_available_projects/2" do
    test "filters out selected projects from a list of all projects" do
      all_projects = [%{id: 1}, %{id: 2}, %{id: 3}]
      selected_projects = [%{id: 1}, %{id: 3}]

      result = Helpers.filter_available_projects(all_projects, selected_projects)

      expected_result = [%{id: 2}]
      assert result == expected_result
    end

    test "returns all projects when none are selected" do
      all_projects = [%{id: 1}, %{id: 2}, %{id: 3}]

      result = Helpers.filter_available_projects(all_projects, [])
      assert result == all_projects
    end
  end

  describe "select_project/4" do
    test "selects a project, updating socket assigns", %{
      projects: projects,
      available_projects: available_projects,
      selected_projects: selected_projects
    } do
      project_id_to_select = 1

      updated =
        Helpers.select_project(
          project_id_to_select,
          projects,
          available_projects,
          selected_projects
        )

      assert %{id: 1} in updated.selected_projects
      assert length(updated.available_projects) == 2
    end

    test "does nothing if the project is not available", %{
      projects: projects,
      available_projects: available_projects,
      selected_projects: selected_projects
    } do
      unavailable_project_id = 3

      updated_socket =
        Helpers.select_project(
          unavailable_project_id,
          projects,
          available_projects,
          selected_projects
        )

      assert length(updated_socket.selected_projects) == 0
    end

    test "does not duplicate a project if it is already selected", %{
      projects: projects,
      available_projects: available_projects,
      selected_projects: _selected_projects
    } do
      already_selected_projects = [%{id: 1}]
      project_id_to_select = 1

      updated =
        Helpers.select_project(
          project_id_to_select,
          projects,
          available_projects,
          already_selected_projects
        )

      selected_counts =
        updated.selected_projects
        |> Enum.map(& &1.id)
        |> Enum.frequencies()

      assert selected_counts[1] == 1
    end
  end

  describe "unselect_project/2" do
    test "unselects a project, updating socket assigns" do
      selected_projects = [%{id: 1}, %{id: 2}]
      projects = [%{id: 1}, %{id: 2}, %{id: 3}]

      project_id_to_delete = 2

      updated =
        Helpers.unselect_project(
          project_id_to_delete,
          projects,
          selected_projects
        )

      assert %{id: 2} not in updated.selected_projects
      assert length(updated.available_projects) == 2
    end

    test "does nothing if the project is not initially selected", %{
      projects: projects
    } do
      selected_projects = [%{id: 1}]
      project_id_to_unselect = 2

      updated =
        Helpers.unselect_project(
          project_id_to_unselect,
          projects,
          selected_projects
        )

      assert updated.selected_projects == [%{id: 1}]
      assert length(updated.available_projects) == length(projects) - 1
    end
  end

  describe "unselect_project/4 and select_project/4" do
    test "handles invalid project ID gracefully for selection", %{
      projects: projects,
      available_projects: available_projects,
      selected_projects: selected_projects
    } do
      invalid_project_id = :invalid

      updated =
        Helpers.select_project(
          invalid_project_id,
          projects,
          available_projects,
          selected_projects
        )

      assert updated.selected_projects == selected_projects
      assert updated.available_projects == available_projects
    end

    test "handles invalid project ID gracefully for unselection", %{
      projects: projects,
      selected_projects: selected_projects
    } do
      invalid_project_id = :invalid

      updated =
        Helpers.unselect_project(
          invalid_project_id,
          projects,
          selected_projects
        )

      assert updated.selected_projects == selected_projects
      assert updated.available_projects == projects
    end
  end
end
