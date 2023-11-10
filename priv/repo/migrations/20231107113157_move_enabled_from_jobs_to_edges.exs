defmodule Lightning.Repo.Migrations.MoveEnabledFromJobsToEdges do
  use Ecto.Migration
  import Ecto.Query

  def change do
    # Add the enabled column to the workflow_edges table with default true
    alter table(:workflow_edges) do
      add :enabled, :boolean, default: true, null: false
    end

    # Ensure that the schema change above is executed immediately
    flush()

    # Begin a transaction for data consistency
    Lightning.Repo.transaction(fn ->
      # Fetch all edges with specified fields
      edges =
        Lightning.Repo.all(
          from(e in "workflow_edges",
            select: %{
              id: e.id,
              source_trigger_id: e.source_trigger_id,
              target_job_id: e.target_job_id
            }
          )
        )

      # Update the `enabled` field for each edge
      edges
      |> Enum.each(fn edge ->
        if edge_has_source_trigger_id?(edge) do
          # If the edge has a source_trigger_id, set enabled to true
          Lightning.Repo.update_all(
            from(e in "workflow_edges", where: e.id == ^edge.id),
            set: [enabled: true]
          )
        else
          # Get the `enabled` value from the corresponding job
          job_enabled? =
            Lightning.Repo.one(
              from(j in "jobs",
                where: j.id == ^edge.target_job_id,
                select: j.enabled
              )
            )

          # Set the edge's enabled value to the job's enabled value
          Lightning.Repo.update_all(
            from(e in "workflow_edges", where: e.id == ^edge.id),
            set: [enabled: job_enabled?]
          )
        end
      end)
    end)

    # Drop the enabled column from the jobs table after the updates are done
    alter table(:jobs) do
      remove :enabled
    end
  end

  # Helper function to check if an edge has a source_trigger_id
  defp edge_has_source_trigger_id?(edge) do
    # This function checks the map returned by the select in the query
    !is_nil(edge.source_trigger_id)
  end
end
