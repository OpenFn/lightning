defmodule Lightning.Auditing do
  @moduledoc """
  Context for working with Audit records.
  """

  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Auditing.Audit
  alias Lightning.Repo
  alias Lightning.VersionControl.ProjectRepoConnection
  alias Lightning.Workflows.Trigger

  def list_all(params \\ %{}) do
    from(a in Audit,
      left_join: p in ProjectRepoConnection,
      on: p.id == a.actor_id and a.actor_type == :project_repo_connection,
      left_join: t in Trigger,
      on: t.id == a.actor_id and a.actor_type == :trigger,
      left_join: u in User,
      on: u.id == a.actor_id and a.actor_type == :user,
      select_merge: %{
        project_repo_connection: p,
        trigger: t,
        user: u
      },
      order_by: [desc: a.inserted_at]
    )
    |> Repo.paginate(params)
    |> then(fn %{entries: entries} = result ->
      Map.put(
        result,
        :entries,
        Enum.map(entries, &Map.put(&1, :actor_display, actor_display_for(&1)))
      )
    end)
  end

  defp actor_display_for(%{
         project_repo_connection: nil,
         actor_type: :project_repo_connection
       }) do
    %{
      identifier: nil,
      label: "(Project Repo Connection Deleted)"
    }
  end

  defp actor_display_for(%{actor_type: :project_repo_connection}) do
    %{
      identifier: nil,
      label: "GitHub"
    }
  end

  defp actor_display_for(%{trigger: nil, actor_type: :trigger}) do
    %{
      identifier: nil,
      label: "(Trigger Deleted)"
    }
  end

  defp actor_display_for(%{
         trigger: %Trigger{type: type} = _actor,
         actor_type: :trigger
       }) do
    %{
      identifier: nil,
      label: Atom.to_string(type) |> String.capitalize()
    }
  end

  defp actor_display_for(%{user: nil, actor_type: :user}) do
    %{
      identifier: nil,
      label: "(User deleted)"
    }
  end

  defp actor_display_for(%{user: %User{} = actor, actor_type: :user}) do
    %{
      identifier: actor.email,
      label: "#{actor.first_name} #{actor.last_name}"
    }
  end
end
