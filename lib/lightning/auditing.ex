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
      Map.put(result, :entries, Enum.map(entries, &assign_actor_display/1))
    end)
  end

  defp assign_actor_display(%{audit: %{actor_type: actor_type} = audit} = entry) do
    %{audit | actor_display: actor_display_for(entry[actor_type], actor_type)}
  end

  defp actor_display_for(actor, actor_type) do
    case {actor, actor_type} do
      {nil, :project_repo_connection} ->
        %{
          identifier: nil,
          label: "(Project Repo Connection Deleted)"
        }

      {%ProjectRepoConnection{}, :project_repo_connection} ->
        %{
          identifier: nil,
          label: "GitHub"
        }

      {nil, :trigger} ->
        %{
          identifier: nil,
          label: "(Trigger Deleted)"
        }

      {%Trigger{type: type}, :trigger} ->
        %{
          identifier: nil,
          label: Atom.to_string(type) |> String.capitalize()
        }

      {nil, :user} ->
        %{
          identifier: nil,
          label: "(User deleted)"
        }

      {%User{} = actor, :user} ->
        %{
          identifier: actor.email,
          label: "#{actor.first_name} #{actor.last_name}"
        }
    end
  end
end
