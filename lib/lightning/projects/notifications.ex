defmodule Lightning.Projects.Notifications do
  alias Lightning.Accounts.UserNotifier
  alias Lightning.Repo
  import Ecto.Query

  def added_to_project(old_project, updated_project) do
    existing_user_ids = Enum.map(old_project.project_users, & &1.user_id)

    emails =
      updated_project.project_users
      |> Enum.reject(fn pu -> pu.user_id in existing_user_ids end)
      |> Enum.map(fn pu ->
        UserNotifier.new(%{type: "project_addition", project_user_id: pu.id})
      end)

    Oban.insert_all(Lightning.Oban, emails)
  end

  def data_retention_change(updated_project) do
    users_query =
      from pu in Ecto.assoc(updated_project, :project_users),
        join: u in assoc(pu, :user),
        where: pu.role in ^[:admin, :owner],
        select: u

    users = Repo.all(users_query)

    Enum.each(users, fn user ->
      UserNotifier.send_data_retention_change_email(
        user,
        updated_project
      )
    end)
  end
end
