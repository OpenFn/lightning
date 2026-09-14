defmodule Lightning.Workflows.TriggerPathMigrationTest do
  @moduledoc """
  The migration that namespaces custom paths decides which URLs keep working.
  Its data steps have no other coverage, so they are read straight out of the
  migration file and run against rows in the state they would find. Reading the
  file rather than copying the SQL means an edit to the migration is an edit to
  what this tests.
  """
  use Lightning.DataCase, async: false

  import Ecto.Query
  import Lightning.Factories

  alias Lightning.Repo
  alias Lightning.Workflows.Trigger

  @migration "priv/repo/migrations/20260827133000_namespace_trigger_custom_paths_by_project.exs"

  # Every UPDATE the migration runs, in order: backfill project_id, release
  # paths held by already-deleted workflows, mark the rows that had a bare URL,
  # dedupe within a project, dedupe bare URLs across projects.
  defp data_steps do
    File.read!(@migration)
    |> then(&Regex.scan(~r/execute\("""\n(\s*UPDATE.*?)\n\s*"""\)/s, &1))
    |> Enum.map(fn [_whole, sql] -> String.trim(sql) end)
  end

  # The indexes come down first and go back up afterwards. Rebuilding them is
  # the assertion: a surviving duplicate makes index creation raise.
  defp run_data_steps do
    for sql <- data_steps(), do: Repo.query!(sql)

    Repo.query!("""
    CREATE UNIQUE INDEX triggers_project_id_custom_path_index
    ON triggers (project_id, custom_path)
    WHERE custom_path IS NOT NULL AND type = 'webhook'
    """)

    Repo.query!("""
    CREATE UNIQUE INDEX triggers_legacy_bare_path_index
    ON triggers (custom_path) WHERE legacy_bare_path
    """)

    :ok
  end

  # Puts a trigger back into the state the migration would find it in.
  defp as_before_migration(trigger, attrs) do
    {1, _} =
      Repo.update_all(
        from(t in Trigger, where: t.id == ^trigger.id),
        set: Keyword.put(attrs, :legacy_bare_path, false)
      )

    trigger
  end

  defp reload(trigger), do: Repo.get!(Trigger, trigger.id)

  setup do
    # The table as the migration finds it: no unique indexes, nothing marked.
    Repo.query!("DROP INDEX triggers_legacy_bare_path_index")
    Repo.query!("DROP INDEX triggers_project_id_custom_path_index")
    Repo.update_all(Trigger, set: [legacy_bare_path: false])
    :ok
  end

  test "reads every data step out of the migration" do
    # A guard on the extraction itself: if the migration grows or loses a step,
    # this test is running something different from what it thinks.
    assert length(data_steps()) == 5
  end

  test "releases a path held by an already-deleted workflow" do
    # Soft-deleted workflows are never purged.
    project = insert(:project)

    deleted =
      insert(:workflow,
        project: project,
        deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

    trigger =
      insert(:trigger, workflow: deleted, type: :webhook, enabled: false)
      |> as_before_migration(custom_path: "orders")

    run_data_steps()

    assert reload(trigger).custom_path == nil
    refute reload(trigger).legacy_bare_path
  end

  test "spares a deleted workflow whose trigger is still serving" do
    # Webhook ingest ignores `deleted_at`, so clearing this would 404 a live
    # endpoint with no way to put the value back.
    project = insert(:project)

    deleted =
      insert(:workflow,
        project: project,
        deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

    trigger =
      insert(:trigger, workflow: deleted, type: :webhook, enabled: true)
      |> as_before_migration(custom_path: "still-live")

    run_data_steps()

    assert reload(trigger).custom_path == "still-live"
  end

  test "a live workflow can then take that name" do
    project = insert(:project)

    deleted =
      insert(:workflow,
        project: project,
        deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )

    insert(:trigger, workflow: deleted, type: :webhook, enabled: false)
    |> as_before_migration(custom_path: "orders")

    live = insert(:workflow, project: project)

    replacement =
      insert(:trigger, workflow: live, type: :webhook)
      |> as_before_migration(custom_path: "orders")

    run_data_steps()

    assert reload(replacement).custom_path == "orders"
    assert reload(replacement).legacy_bare_path
  end

  test "grandfathers a webhook that already had a bare URL" do
    workflow = insert(:workflow, project: insert(:project))

    trigger =
      insert(:trigger, workflow: workflow, type: :webhook)
      |> as_before_migration(custom_path: "orders")

    run_data_steps()

    assert reload(trigger).legacy_bare_path
    assert reload(trigger).custom_path == "orders"
  end

  test "leaves a webhook with no path alone" do
    workflow = insert(:workflow, project: insert(:project))
    trigger = insert(:trigger, workflow: workflow, type: :webhook)

    run_data_steps()

    refute reload(trigger).legacy_bare_path
  end

  test "ignores a stale path on a cron trigger" do
    # A path on a cron row never served a URL.
    workflow = insert(:workflow, project: insert(:project))

    cron =
      insert(:trigger, workflow: workflow, type: :cron)
      |> as_before_migration(custom_path: "orders")

    run_data_steps()

    refute reload(cron).legacy_bare_path
  end

  test "a stale cron path does not outrank a webhook holding the same one" do
    project = insert(:project)
    cron_workflow = insert(:workflow, project: project)
    webhook_workflow = insert(:workflow, project: project)

    # The cron row is older, so a type-blind dedupe would keep it and strip the
    # webhook that is actually serving traffic.
    cron =
      insert(:trigger,
        workflow: cron_workflow,
        type: :cron,
        inserted_at: ~U[2023-01-01 00:00:00Z]
      )
      |> as_before_migration(custom_path: "orders")

    webhook =
      insert(:trigger,
        workflow: webhook_workflow,
        type: :webhook,
        inserted_at: ~U[2024-01-01 00:00:00Z]
      )
      |> as_before_migration(custom_path: "orders")

    run_data_steps()

    assert reload(webhook).custom_path == "orders"
    assert reload(webhook).legacy_bare_path
    assert reload(cron).custom_path == "orders"
    refute reload(cron).legacy_bare_path
  end

  test "within a project the oldest webhook keeps a duplicated path" do
    project = insert(:project)

    older =
      insert(:trigger,
        workflow: insert(:workflow, project: project),
        type: :webhook,
        inserted_at: ~U[2023-01-01 00:00:00Z]
      )
      |> as_before_migration(custom_path: "orders")

    newer =
      insert(:trigger,
        workflow: insert(:workflow, project: project),
        type: :webhook,
        inserted_at: ~U[2024-01-01 00:00:00Z]
      )
      |> as_before_migration(custom_path: "orders")

    run_data_steps()

    assert reload(older).custom_path == "orders"
    assert reload(older).legacy_bare_path

    # The duplicate falls back to its generated URL rather than aborting the
    # migration on the unique index.
    assert reload(newer).custom_path == nil
    refute reload(newer).legacy_bare_path
  end

  test "across projects both keep the path, the oldest keeps the bare URL" do
    older =
      insert(:trigger,
        workflow: insert(:workflow, project: insert(:project)),
        type: :webhook,
        inserted_at: ~U[2023-01-01 00:00:00Z]
      )
      |> as_before_migration(custom_path: "orders")

    newer =
      insert(:trigger,
        workflow: insert(:workflow, project: insert(:project)),
        type: :webhook,
        inserted_at: ~U[2024-01-01 00:00:00Z]
      )
      |> as_before_migration(custom_path: "orders")

    run_data_steps()

    assert reload(older).custom_path == "orders"
    assert reload(older).legacy_bare_path

    # Namespacing means the newer one keeps its path, just not the bare URL.
    assert reload(newer).custom_path == "orders"
    refute reload(newer).legacy_bare_path
  end
end
