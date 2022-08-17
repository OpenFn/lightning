defmodule Lightning.Repo.Migrations.RenameUsersTokens do
  use Ecto.Migration

  def change do
    rename(table(:users_tokens), to: table(:user_tokens))

    rename_constraint("user_tokens",
      from: "users_tokens_user_id_fkey",
      to: "user_tokens_user_id_fkey"
    )

    rename_index(from: "users_tokens_pkey", to: "user_tokens_pkey")
    rename_index(from: "users_tokens_context_token_index", to: "user_tokens_context_token_index")
    rename_index(from: "users_tokens_user_id_index", to: "user_tokens_user_id_index")
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
