defmodule Lightning.VersionControl.AuditTest do
  use Lightning.DataCase, async: true

  alias Lightning.VersionControl.Audit

  describe "repo_connection/3 - created" do
    test "returns a changeset including the config_path" do
      %{
        branch: branch,
        config_path: config_path,
        project_id: project_id,
        repo: repo,
        sync_direction: sync_direction
      } =
        repo_connection =
        insert(:project_repo_connection, config_path: "config_path")

      %{id: user_id} = user = insert(:user)

      changeset =
        Audit.repo_connection(repo_connection, :created, user)

      assert %{
               changes: %{
                 event: "repo_connection_created",
                 item_type: "project",
                 item_id: ^project_id,
                 actor_id: ^user_id,
                 changes: %{
                   changes: audit_changes
                 }
               },
               valid?: true
             } = changeset

      assert %{
               after: %{
                 branch: branch,
                 config_path: config_path,
                 repo: repo,
                 sync_direction: sync_direction
               }
             } == audit_changes
    end

    test "excludes the config_path from the changeset if it is nil" do
      %{
        branch: branch,
        repo: repo,
        sync_direction: sync_direction
      } =
        repo_connection =
        insert(:project_repo_connection, config_path: nil)

      user = insert(:user)

      changeset =
        Audit.repo_connection(repo_connection, :created, user)

      %{changes: %{changes: %{changes: audit_changes}}} = changeset

      assert %{
               after: %{
                 branch: branch,
                 repo: repo,
                 sync_direction: sync_direction
               }
             } == audit_changes
    end
  end

  describe "repo_connection/3 - :removed" do
    test "returns a changeset including the config_path" do
      %{
        branch: branch,
        config_path: config_path,
        project_id: project_id,
        repo: repo
      } =
        repo_connection =
        insert(:project_repo_connection, config_path: "config_path")

      %{id: user_id} = user = insert(:user)

      changeset =
        Audit.repo_connection(repo_connection, :removed, user)

      assert %{
               changes: %{
                 event: "repo_connection_removed",
                 item_type: "project",
                 item_id: ^project_id,
                 actor_id: ^user_id,
                 changes: %{
                   changes: audit_changes
                 }
               },
               valid?: true
             } = changeset

      assert %{
               before: %{
                 branch: branch,
                 config_path: config_path,
                 repo: repo
               }
             } == audit_changes
    end

    test "excludes the config_path if it is nil" do
      %{
        branch: branch,
        repo: repo
      } =
        repo_connection =
        insert(:project_repo_connection, config_path: nil)

      user = insert(:user)

      changeset =
        Audit.repo_connection(repo_connection, :removed, user)

      assert %{
               changes: %{
                 changes: %{
                   changes: audit_changes
                 }
               },
               valid?: true
             } = changeset

      assert %{
               before: %{
                 branch: branch,
                 repo: repo
               }
             } == audit_changes
    end
  end
end
