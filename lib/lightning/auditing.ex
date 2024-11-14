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
      select: %{audit: a, user: u, trigger: t, project_repo_connection: p},
      order_by: [desc: a.inserted_at]
    )
    |> Repo.paginate(params)
    |> then(fn %{entries: entries} = result ->
      Map.put(result, :entries, Enum.map(entries, &extended_audit/1))
    end)
  end

  defp extended_audit(%{
         audit: %{actor_type: :project_repo_connection} = audit,
         project_repo_connection: actor
       }) do
    merge(audit, actor, :project_repo_connection)
  end

  defp extended_audit(%{
         audit: %{actor_type: :trigger} = audit,
         trigger: actor
       }) do
    merge(audit, actor, :trigger)
  end

  defp extended_audit(%{
         audit: %{actor_type: :user} = audit,
         user: actor
       }) do
    merge(audit, actor, :user)
  end

  defp actor_display_for(nil, :project_repo_connection) do
    %{
      identifier: nil,
      label: "(Project Repo Connection Deleted)"
    }
  end

  defp actor_display_for(%ProjectRepoConnection{}, :project_repo_connection) do
    %{
      identifier: nil,
      label: "GitHub"
    }
  end

  defp actor_display_for(nil, :trigger) do
    %{
      identifier: nil,
      label: "(Trigger Deleted)"
    }
  end

  defp actor_display_for(%Trigger{type: type}, :trigger) do
    %{
      identifier: nil,
      label: Atom.to_string(type) |> String.capitalize()
    }
  end

  defp actor_display_for(nil, :user) do
    %{
      identifier: nil,
      label: "(User deleted)"
    }
  end

  defp actor_display_for(%User{} = actor, :user) do
    %{
      identifier: actor.email,
      label: "#{actor.first_name} #{actor.last_name}"
    }
  end

  defp merge(audit, actor, actor_type) do
    %{audit | actor_display: actor_display_for(actor, actor_type)}
  end
end
