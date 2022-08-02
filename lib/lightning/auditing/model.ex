defmodule Lightning.Auditing.Model do
  @moduledoc """
  Macro module to add common model behaviour to a given Ecto model
  """
  require Logger

  # coveralls-ignore-start
  defmacro __using__(opts) do
    repo = Keyword.fetch!(opts, :repo)
    schema = Keyword.fetch!(opts, :schema)
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
        def event(event, row_id, actor_id, metadata \\ %{})
      end

    event_log_functions =
      for event_name <- events do
        quote do
          # Output:
          #
          # def event("foo_event", row_id, actor_id, metadata) do
          #   Lightning.Audit.event(schema, "foo_event", row_id, actor_id, metadata)
          # end
          def event(unquote(event_name), row_id, actor_id, metadata) do
            unquote(__MODULE__).event(
              unquote(schema),
              unquote(event_name),
              row_id,
              actor_id,
              metadata
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
  Creates a `schema` changeset for the `event` identified by `row_id` and caused
  by `actor_id`.

  The given `metadata` can be either `nil`, `Ecto.Changeset`, struct or map.

  It returns `:no_changes` in case of an `Ecto.Changeset` metadata that changed nothing
  or an `Ecto.Changeset` with the event ready to be inserted.
  """
  @spec event(
          module(),
          String.t(),
          Ecto.UUID.t(),
          Ecto.UUID.t(),
          Ecto.Changeset.t() | map() | nil
        ) ::
          :no_changes | Ecto.Changeset.t()

  def event(schema, event, row_id, actor_id, metadata \\ %{})

  def event(_, _, _, _, %Ecto.Changeset{changes: changes} = _changeset)
      when map_size(changes) == 0 do
    :no_changes
  end

  def event(
        schema,
        event,
        row_id,
        actor_id,
        %Ecto.Changeset{data: %subject_schema{} = data, changes: changes}
      ) do
    change_keys = changes |> Map.keys() |> MapSet.new()

    field_keys =
      subject_schema.__schema__(:fields)
      |> MapSet.new()
      |> MapSet.intersection(change_keys)
      |> MapSet.to_list()

    metadata = %{
      before: Map.take(data, field_keys),
      after: Map.take(changes, field_keys)
    }

    audit_changeset(schema, event, row_id, actor_id, metadata)
  end

  def event(schema, event, row_id, actor_id, metadata) when is_map(metadata) do
    audit_changeset(schema, event, row_id, actor_id, metadata)
  end

  defp audit_changeset(schema, event, row_id, actor_id, metadata) do
    schema
    |> struct()
    |> schema.changeset(%{
      event: event,
      row_id: row_id,
      actor_id: actor_id,
      metadata: metadata
    })
  end
end
