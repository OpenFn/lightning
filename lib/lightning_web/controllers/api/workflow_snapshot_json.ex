defmodule LightningWeb.API.WorkflowSnapshotJSON do
  @moduledoc """
  JSON views for a workflow's snapshots.

  A snapshot stores a workflow's name, positions, jobs, triggers and edges as
  they were, but not its `concurrency` or `enable_job_logs`, so those are left
  out rather than sent as today's values or as `null`. Its `inserted_at` is
  when the snapshot was taken, and it has no `updated_at`, since a snapshot
  never changes.
  """
  import LightningWeb.API.Helpers

  alias Lightning.Workflows.Snapshot

  @job_fields [
    :id,
    :name,
    :body,
    :adaptor,
    :project_credential_id,
    :keychain_credential_id
  ]

  @trigger_fields [
    :id,
    :type,
    :enabled,
    :cron_expression,
    :cron_cursor_job_id,
    :custom_path,
    :comment,
    :webhook_reply,
    :webhook_response_config
  ]

  @edge_fields [
    :id,
    :source_trigger_id,
    :source_job_id,
    :target_job_id,
    :condition_type,
    :condition_expression,
    :condition_label,
    :enabled
  ]

  def index(%{page: page, workflow: workflow, conn: conn}) do
    %{
      data:
        Enum.map(page.entries, fn snapshot ->
          %{
            id: snapshot.id,
            lock_version: snapshot.lock_version,
            inserted_at: snapshot.inserted_at,
            latest: snapshot.lock_version == workflow.lock_version
          }
        end),
      links: pagination_links(conn, page, %{})
    }
  end

  def show(%{snapshot: %Snapshot{} = snapshot, workflow: workflow}) do
    %{
      snapshot: %{
        id: workflow.id,
        name: snapshot.name,
        project_id: workflow.project_id,
        lock_version: snapshot.lock_version,
        positions: snapshot.positions,
        inserted_at: snapshot.inserted_at,
        jobs: Enum.map(snapshot.jobs, &Map.take(&1, @job_fields)),
        triggers: Enum.map(snapshot.triggers, &Map.take(&1, @trigger_fields)),
        edges: Enum.map(snapshot.edges, &Map.take(&1, @edge_fields))
      }
    }
  end
end
