defmodule Lightning.Repo.Migrations.AddIndexToDataclipIdOnRuns do
  use Ecto.Migration

  def change do
    create_if_not_exists index("runs", [:dataclip_id])
    create_if_not_exists index("work_orders", [:dataclip_id])
  end
end
