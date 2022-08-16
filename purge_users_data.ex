defmodule PurgeUsersData do
  def purge_user(id) do
    Logger.debug(fn -> "Purging user ##{id}..." end)

    [
      "DELETE FROM credentials WHERE user_id = $1;",
      "DELETE FROM project_users WHERE user_id = $1;",
      "DELETE FROM users WHERE id = $1;"
    ]
    |> Enum.each(fn x ->
      {:ok, result} = Ecto.Adapters.SQL.query(Repo, x, [id])
      Logger.info(fn -> "Manual purge #{x} returned #{inspect(result)}." end)
    end)

    Logger.debug(fn -> "User ##{id} purged." end)
    :ok
  end
end
