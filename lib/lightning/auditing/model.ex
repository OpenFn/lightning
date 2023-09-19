defmodule Lightning.Auditing.Model do
  @moduledoc """
  Macro module to add common model behaviour to a given Ecto model
  """
  require Logger

  # coveralls-ignore-start
  defmacro __using__(opts) do
    repo = Keyword.fetch!(opts, :repo)
    schema = Keyword.fetch!(opts, :schema)
    item = Keyword.fetch!(opts, :item)
    events = Keyword.fetch!(opts, :events)

    if Enum.empty?(events),
      do: raise(ArgumentError, message: "No events provided to Audit")

    save_function =
      quote do
        # Output:
        #
        # def save(%Ecto.Changeset{} = changes) do
        #   Lightning.Audit.save(changes, repo)
        # end
        def save(%Ecto.Changeset{} = changes) do
          unquote(__MODULE__).save(changes, unquote(repo))
        end
      end

    event_signature =
      quote do
        def event(item_type, event, item_id, actor_id, changes \\ %{})
      end

    event_log_functions =
      for event_name <- events do
        quote do
          # Output:
          #
          # def event(item_type, "foo_event", item_id, actor_id, changes) do
          #   Lightning.Audit.event(item_type, schema, "foo_event", item_id, actor_id, changes)
          # end
          def event(item_type, unquote(event_name), item_id, actor_id, changes) do
            unquote(__MODULE__).event(
              unquote(schema),
              unquote(item),
              unquote(event_name),
              item_id,
              actor_id,
              changes
            )
          end
        end
      end

    [save_function, event_signature, event_log_functions]
  end

  # coveralls-ignore-stop

  @doc """
  Saves the event to the `Repo`.

  In case of nothing changes, do nothing.

  It returns `{:ok, :no_changes}` if nothing changed, `{:ok, struct}` if the log
  has been successfully saved or `{:error, changeset}` in case of error.
  """
  @spec save(Ecto.Changeset.t() | :no_changes, Ecto.Repo.t()) ::
          {:ok, :no_changes}
          | {:ok, Ecto.Schema.t()}
          | {:error, Ecto.Changeset.t()}

  def save(:no_changes, _repo) do
    {:ok, :no_changes}
  end

  def save(%Ecto.Changeset{} = changes, repo) do
    Logger.debug("Saving audit info...")
    repo.insert(changes)
  end

  @doc """
  Creates a `schema` changeset for the `event` identified by `item_id` and caused
  by `actor_id`.

  The given `changes` can be either `nil`, `Ecto.Changeset`, struct or map.

  It returns `:no_changes` in case of an `Ecto.Changeset` changes that changed nothing
  or an `Ecto.Changeset` with the event ready to be inserted.
  """
  @spec event(
          module(),
          String.t(),
          String.t(),
          Ecto.UUID.t(),
          Ecto.UUID.t(),
          Ecto.Changeset.t() | map() | nil
        ) ::
          :no_changes | Ecto.Changeset.t()

  def event(schema, item_type, event, item_id, actor_id, changes \\ %{})

  def event(_, _, _, _, _, %Ecto.Changeset{changes: changes} = _changeset)
      when map_size(changes) == 0 do
    :no_changes
  end

  def event(
        schema,
        item_type,
        event,
        item_id,
        actor_id,
        %Ecto.Changeset{data: %subject_schema{} = data, changes: changes}
      ) do
    change_keys = changes |> Map.keys() |> MapSet.new()

    field_keys =
      subject_schema.__schema__(:fields)
      |> MapSet.new()
      |> MapSet.intersection(change_keys)
      |> MapSet.to_list()

    changes = %{
      before: Map.take(data, field_keys),
      after: Map.take(changes, field_keys)
    }

    audit_changeset(schema, item_type, event, item_id, actor_id, changes)
  end

  def event(schema, item_type, event, item_id, actor_id, changes)
      when is_map(changes) do
    audit_changeset(schema, item_type, event, item_id, actor_id, changes)
  end

  defp audit_changeset(schema, item_type, event, item_id, actor_id, changes) do
    schema
    |> struct()
    |> schema.changeset(%{
      item_type: item_type,
      event: event,
      item_id: item_id,
      actor_id: actor_id,
      changes: changes
    })
  end
end
