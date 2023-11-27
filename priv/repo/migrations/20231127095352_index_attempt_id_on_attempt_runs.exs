defmodule Lightning.Repo.Migrations.IndexAttemptIdOnAttemptRuns do
  use Ecto.Migration

  def change do
    create index("attempt_runs", ["attempt_id"], using: "hash")
  end
end
