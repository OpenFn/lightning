defmodule Lightning.Channels.Audit do
  @moduledoc """
  Audit trail for channel CRUD and auth method changes.

  Provides `event/5` (via `Lightning.Auditing.Audit`) for basic CRUD events,
  plus `audit_auth_method_changes/4` which derives fine-grained audit events
  for client and destination auth method additions, removals, and swaps.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "channel",
    events: [
      "created",
      "updated",
      "deleted",
      "auth_method_added",
      "auth_method_removed",
      "auth_method_changed"
    ]

  alias Ecto.Multi
  alias Lightning.Channels.Channel

  @doc """
  Appends audit events for auth method changes to the given Multi.

  Inspects the changeset for changes to `:client_auth_methods` and
  `:destination_auth_method`, emitting the appropriate added/removed/changed
  events. No-op when no auth method changes are present.

  Step keys are unique per call, so the helper can be composed into a larger Multi any number of
  times — e.g. once per channel when batching audits across channels.
  """
  def audit_auth_method_changes(multi, %Channel{} = channel, changeset, actor) do
    multi
    |> audit_client_changes(channel, changeset, actor)
    |> audit_destination_changes(channel, changeset, actor)
  end

  # --- Client auth methods (has_many) ---

  defp audit_client_changes(multi, channel, changeset, actor) do
    changes =
      Ecto.Changeset.get_change(changeset, :client_auth_methods, [])

    inserted = Enum.filter(changes, &(&1.action == :insert))
    deleted = Enum.filter(changes, &(&1.action == :delete))

    multi
    |> add_auth_method_audits(:added, inserted, :client, channel, actor)
    |> add_auth_method_audits(:removed, deleted, :client, channel, actor)
  end

  # --- Destination auth method (has_one, on_replace: :delete) ---
  #
  # Three scenarios:
  # 1. Set (no existing) → insert → "auth_method_added"
  # 2. Clear (existing → nil) → replace/delete → "auth_method_removed"
  # 3. Swap (existing → different) → replace produces a delete of old +
  #    insert of new. We emit a single "auth_method_changed" event instead.

  defp audit_destination_changes(multi, channel, changeset, actor) do
    old = changeset.data |> Map.get(:destination_auth_method)
    has_existing? = old != nil and not match?(%Ecto.Association.NotLoaded{}, old)

    case Ecto.Changeset.get_change(
           changeset,
           :destination_auth_method,
           :no_change
         ) do
      :no_change ->
        multi

      nil when has_existing? ->
        audit_destination_removed(multi, channel, old, actor)

      nil ->
        multi

      %Ecto.Changeset{action: :insert} = new_cs when has_existing? ->
        old_fields = fields_for_data(old, :destination)
        new_fields = fields_for_changeset(new_cs, :destination)

        Multi.insert(
          multi,
          unique_key(:audit_destination_changed),
          event("auth_method_changed", channel.id, actor, %{
            before: old_fields,
            after: new_fields
          })
        )

      %Ecto.Changeset{action: :insert} = new_cs ->
        fields = fields_for_changeset(new_cs, :destination)

        Multi.insert(
          multi,
          unique_key(:audit_destination_added),
          event("auth_method_added", channel.id, actor, %{
            before: nil,
            after: fields
          })
        )

      %Ecto.Changeset{action: :delete} when has_existing? ->
        audit_destination_removed(multi, channel, old, actor)

      %Ecto.Changeset{action: :delete} ->
        multi
    end
  end

  defp audit_destination_removed(multi, _channel, nil, _actor), do: multi

  defp audit_destination_removed(multi, channel, old, actor) do
    old_fields = fields_for_data(old, :destination)

    Multi.insert(
      multi,
      unique_key("audit_destination_removed"),
      event("auth_method_removed", channel.id, actor, %{
        before: old_fields,
        after: nil
      })
    )
  end

  defp add_auth_method_audits(multi, _direction, [], _role, _channel, _actor),
    do: multi

  defp add_auth_method_audits(multi, direction, changesets, role, channel, actor) do
    {event_name, extract_fields, wrap} =
      case direction do
        :added ->
          {"auth_method_added", &fields_for_changeset(&1, role), &{nil, &1}}

        :removed ->
          {"auth_method_removed", &fields_for_data(&1.data, role), &{&1, nil}}
      end

    Enum.reduce(changesets, multi, fn cs, acc ->
      {before, after_val} = wrap.(extract_fields.(cs))

      Multi.insert(
        acc,
        unique_key("audit_#{role}_#{event_name}"),
        event(event_name, channel.id, actor, %{
          before: before,
          after: after_val
        })
      )
    end)
  end

  defp unique_key(base) do
    "#{base}_#{System.unique_integer([:positive])}"
  end

  # Extract fields from a changeset (for inserts/new records)
  defp fields_for_changeset(cs, :client) do
    %{
      "role" => "client",
      "webhook_auth_method_id" =>
        Ecto.Changeset.get_field(cs, :webhook_auth_method_id)
    }
  end

  defp fields_for_changeset(cs, :destination) do
    %{
      "role" => "destination",
      "project_credential_id" =>
        Ecto.Changeset.get_field(cs, :project_credential_id)
    }
  end

  # Extract fields from existing data (for removals/before state)
  defp fields_for_data(data, :client) do
    %{
      "role" => "client",
      "webhook_auth_method_id" => data.webhook_auth_method_id
    }
  end

  defp fields_for_data(data, :destination) do
    %{
      "role" => "destination",
      "project_credential_id" => data.project_credential_id
    }
  end
end
