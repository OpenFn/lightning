defmodule Lightning.Repo.Migrations.AddExternalIdUserUniqueness do
  use Ecto.Migration

  def up do
    duplicates =
      repo().query!("""
      SELECT c.id, c.external_id, c.name, c.user_id
      FROM credentials c
      WHERE c.id IN (
        SELECT id FROM (
          SELECT id,
                 ROW_NUMBER() OVER (
                   PARTITION BY external_id, user_id
                   ORDER BY inserted_at ASC
                 ) AS rn
          FROM credentials
          WHERE external_id IS NOT NULL
        ) ranked
        WHERE rn > 1
      )
      ORDER BY c.external_id, c.name
      """)

    if duplicates.num_rows > 0 do
      for [id, external_id, name, user_id] <- duplicates.rows do
        repo().query!(
          "UPDATE credentials SET external_id = NULL WHERE id = $1",
          [id]
        )

        IO.puts(
          "[migration] Cleared duplicate external_id #{inspect(external_id)} " <>
            "from credential #{inspect(name)} (#{id}) owned by user #{user_id}"
        )
      end
    end

    create unique_index(:credentials, [:external_id, :user_id],
             where: "external_id IS NOT NULL",
             name: :credentials_external_id_user_id_index
           )
  end

  def down do
    drop index(:credentials, [:external_id, :user_id],
           name: :credentials_external_id_user_id_index
         )
  end
end
