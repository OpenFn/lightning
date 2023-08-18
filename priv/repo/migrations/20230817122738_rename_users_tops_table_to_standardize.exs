defmodule Lightning.Repo.Migrations.RenameUsersTopsTableToStandardize do
  use Ecto.Migration

  def change do
    rename(table(:users_totps), to: table(:user_totps))

    rename_constraint("user_totps",
      from: "users_totps_user_id_fkey",
      to: "user_totps_user_id_fkey"
    )

    rename_index(from: "users_totps_pkey", to: "user_totps_pkey")
    rename_index(from: "users_totps_user_id_index", to: "users_totp_user_id_index")
  end

  defp rename_constraint(table, from: from, to: to) do
    execute(
      """
      ALTER TABLE #{table} RENAME CONSTRAINT "#{from}" TO "#{to}";
      """,
      """
      ALTER TABLE #{table} RENAME CONSTRAINT "#{to}" TO "#{from}";
      """
    )
  end

  defp rename_index(from: from, to: to) do
    execute(
      """
      ALTER INDEX #{from} RENAME TO #{to};
      """,
      """
      ALTER INDEX #{to} RENAME TO #{from};
      """
    )
  end
end
