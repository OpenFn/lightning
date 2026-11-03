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

  @filter_types %{
    item_type: :string,
    item_id: Ecto.UUID,
    actor_id: Ecto.UUID,
    event: :string,
    inserted_after: :utc_datetime_usec,
    inserted_before: :utc_datetime_usec
  }

  def list_all(params \\ %{}) do
    Audit
    |> with_actors()
    |> order_by([a], desc: a.inserted_at)
    |> Repo.paginate(params)
    |> assign_actor_displays()
  end

  @doc """
  The filters `paginate_events/2` takes, with the type of each.
  """
  @spec filter_types() :: %{atom() => atom() | module()}
  def filter_types, do: @filter_types

  @doc """
  A page of audit events, newest first, each with its actor named in
  `actor_display`, narrowed by `filters`: any of `filter_types/0`, already
  cast. `inserted_after` and `inserted_before` are exclusive.

  Events recorded in the same second come in a fixed order, so a page never
  repeats or skips one.
  """
  @spec paginate_events(map(), keyword()) :: Scrivener.Page.t()
  def paginate_events(filters, page) do
    filters
    |> Enum.reduce(Audit, &filter/2)
    |> with_actors()
    |> order_by([a], desc: a.inserted_at, desc: a.id)
    |> Repo.paginate(page)
    |> assign_actor_displays()
  end

  defp filter({key, value}, query)
       when key in [:item_type, :item_id, :actor_id, :event],
       do: where(query, [a], field(a, ^key) == ^value)

  defp filter({:inserted_after, at}, query),
    do: where(query, [a], a.inserted_at > type(^at, :utc_datetime_usec))

  defp filter({:inserted_before, at}, query),
    do: where(query, [a], a.inserted_at < type(^at, :utc_datetime_usec))

  defp with_actors(query) do
    from(a in query,
      left_join: p in ProjectRepoConnection,
      on: p.id == a.actor_id and a.actor_type == :project_repo_connection,
      left_join: t in Trigger,
      on: t.id == a.actor_id and a.actor_type == :trigger,
      left_join: u in User,
      on: u.id == a.actor_id and a.actor_type == :user,
      select: %{audit: a, user: u, trigger: t, project_repo_connection: p}
    )
  end

  defp assign_actor_displays(%{entries: entries} = page),
    do: Map.put(page, :entries, Enum.map(entries, &assign_actor_display/1))

  defp assign_actor_display(%{audit: %{actor_type: :service_account} = audit}) do
    %{
      audit
      | actor_display: %{
          identifier: audit.metadata["service_account_id"],
          label: "Service account"
        }
    }
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
