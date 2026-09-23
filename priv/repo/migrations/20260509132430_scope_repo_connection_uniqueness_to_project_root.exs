defmodule Lightning.Repo.Migrations.ScopeRepoConnectionUniquenessToProjectRoot do
  use Ecto.Migration

  @moduledoc """
  Adds `root_project_id` to `project_repo_connections` and a unique index on
  `(root_project_id, repo, branch)`. This makes the database the source of
  truth for "no two projects sharing the same ultimate root may claim the same
  (repo, branch) pair" — closing the check-then-insert race that otherwise
  exists at READ COMMITTED isolation.

  Backfill walks the `parent_id` chain of each connection's project to find
  the topmost ancestor and writes that into `root_project_id`. If two existing
  connections in the same project tree already share `(repo, branch)`, the
  unique index creation will fail; resolve by removing one of the connections
  and re-running the migration.

  `on_delete: :delete_all` matches the existing behaviour on
  `project_repo_connections.project_id`. Picking `:restrict` instead would
  block root-project deletion whenever any descendant sandbox still holds a
  repo connection (because `projects.parent_id` is `:nilify_all` — the
  sandbox sticks around with `parent_id = NULL` after the root is dropped, so
  its connection's `root_project_id` reference survives the cascade).
  Connections are derivative settings; cascading them when the root is gone
  is the sensible choice.
  """

  def up do
    alter table(:project_repo_connections) do
      add :root_project_id,
          references(:projects, type: :binary_id, on_delete: :delete_all)
    end

    flush()

    execute("""
    WITH RECURSIVE project_roots AS (
      SELECT id, parent_id, id AS root_id
      FROM projects
      WHERE parent_id IS NULL
      UNION ALL
      SELECT p.id, p.parent_id, pr.root_id
      FROM projects p
      JOIN project_roots pr ON p.parent_id = pr.id
    )
    UPDATE project_repo_connections prc
    SET root_project_id = pr.root_id
    FROM project_roots pr
    WHERE prc.project_id = pr.id;
    """)

    alter table(:project_repo_connections) do
      modify :root_project_id, :binary_id, null: false
    end

    create unique_index(
             "project_repo_connections",
             [:root_project_id, :repo, :branch],
             name: "project_repo_connections_root_repo_branch_index"
           )
  end

  def down do
    drop index(
           "project_repo_connections",
           [:root_project_id, :repo, :branch],
           name: "project_repo_connections_root_repo_branch_index"
         )

    alter table(:project_repo_connections) do
      remove :root_project_id
    end
  end
end
