defmodule Lightning.Repo.Migrations.AddWipedToDataclips do
  use Ecto.Migration

  def change do
    alter table("dataclips") do
      add :wiped_at, :utc_datetime
    end

    alter table("steps") do
      modify :input_dataclip_id, :binary_id, null: true, from: {:binary_id, null: false}
    end

    # TODO: remove this when done
    alter table("projects") do
      add :retention_policy, :string
    end
  end
end
