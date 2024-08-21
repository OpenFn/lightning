defmodule Lightning.Repo.Migrations.AddUniquenessToCredentialNamePerUser do
  use Ecto.Migration

  def up do
    # Identify duplicates and update them to ensure uniqueness
    execute """
    WITH duplicates AS (
      SELECT
        id,
        name,
        user_id,
        ROW_NUMBER() OVER (PARTITION BY LOWER(REPLACE(name, '-', ' ')), user_id ORDER BY id) AS row_num
      FROM
        credentials
    )
    UPDATE credentials
    SET name = credentials.name || '-' || duplicates.row_num
    FROM duplicates
    WHERE credentials.id = duplicates.id
    AND duplicates.row_num > 1;
    """

    execute """
    CREATE UNIQUE INDEX credentials_name_user_id_index ON credentials (LOWER(REPLACE(name, '-', ' ')), user_id);
    """
  end

  def down do
    execute """
    DROP INDEX credentials_name_user_id_index;
    """
  end
end
