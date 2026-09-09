defmodule Lightning.Repo.Migrations.AddRestoredFromToWorkflowReleases do
  use Ecto.Migration

  def change do
    alter table(:workflow_releases) do
      # Which version this one put back. Only a :restore release sets it, so the
      # trail reads forward and the version it came from stays in the history.
      add :restored_from_version_number, :integer
    end
  end
end
