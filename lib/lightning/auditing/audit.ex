defmodule Lightning.Auditing.Audit do
  @moduledoc """
  Macro module to add common model behaviour to a given Ecto model
  """
  use Lightning.Schema

  require Ecto.Query
  require Logger

  @callback update_changes(changes :: map()) :: map()

  # coveralls-ignore-start
  defmacro __using__(opts) do
    repo = Keyword.fetch!(opts, :repo)
    item = Keyword.fetch!(opts, :item)
    events = Keyword.fetch!(opts, :events)

    if Enum.empty?(events),
      do: raise(ArgumentError, message: "No events provided to Audit")

    update_changes_func =
      quote do
        @behaviour Lightning.Auditing.Audit

        def update_changes(changes) do
          changes
        end

        defoverridable update_changes: 1
      end

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
        def event(event, item_id, actor, changes \\ %{})
      end

    event_log_functions =
      for event_name <- events do
        quote do
          # Output:
          #
          # def event(item_type, "foo_event", item_id, actor, changes) do
          #   Lightning.Audit.event(item_type, "foo_event", item_id, actor, changes)
          # end
          def event(unquote(event_name), item_id, actor, changes) do
            unquote(__MODULE__).event(
              unquote(item),
              unquote(event_name),
              item_id,
              actor,
              changes,
              &update_changes/1
            )
          end
        end
      end

    base_query =
      quote do
        import Ecto.Query

        def base_query do
          from(unquote(__MODULE__), where: [item_type: unquote(item)])
        end
      end

    [
      base_query,
      save_function,
      event_signature,
      event_log_functions,
      update_changes_func
    ]
  end

  # coveralls-ignore-stop

  defmodule Changes do
    @moduledoc false

    use Lightning.Schema

    @primary_key false
    embedded_schema do
      field :before, :map
      field :after, :map
    end

    @doc false
    def changeset(changes, attrs, update_changes_fun) do
      changes
      |> cast(attrs, [:before, :after])
      |> update_change(:before, update_changes_fun)
      |> update_change(:after, update_changes_fun)
    end
  end

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "audit_events" do
    field :event, :string
    field :item_type, :string
    field :item_id, Ecto.UUID
    embeds_one :changes, Changes
    field :actor_id, Ecto.UUID
    field :actor_type, :string
    field :actor, :map, virtual: true

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(
        %__MODULE__{} = audit,
        attrs,
        update_changes_fun \\ fn x -> x end
      ) do
    audit
    |> cast(attrs, [:event, :item_id, :actor_id, :actor_type, :item_type])
    |> cast_embed(:changes,
      with: fn schema, changes ->
        Changes.changeset(schema, changes, update_changes_fun)
      end
    )
    |> validate_required([:event, :actor_id, :actor_type])
  end

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
  Creates a `changeset` for the `event` identified by `item_id` and caused
  by `actor`.

  The given `changes` can be either `nil`, `Ecto.Changeset`, struct or map.

  It returns `:no_changes` in case of an `Ecto.Changeset` changes that changed nothing
  or an `Ecto.Changeset` with the event ready to be inserted.
  """
  @spec event(
          String.t(),
          String.t(),
          Ecto.UUID.t(),
          %{id: Ecto.UUID.t()},
          Ecto.Changeset.t() | map() | nil,
          update_changes_fun :: (map() -> map())
        ) ::
          :no_changes | Ecto.Changeset.t()

  def event(
        item_type,
        event,
        item_id,
        actor,
        changes \\ %{},
        update_fun \\ fn x -> x end
      )

  def event(_, _, _, _, %Ecto.Changeset{changes: changes}, _update_fun)
      when map_size(changes) == 0 do
    :no_changes
  end

  def event(
        item_type,
        event,
        item_id,
        actor,
        %Ecto.Changeset{data: %subject_schema{} = data, changes: changes},
        update_fun
      ) do
    change_keys = changes |> Map.keys() |> MapSet.new()

    field_keys =
      subject_schema.__schema__(:fields)
      |> MapSet.new()
      |> MapSet.intersection(change_keys)
      |> MapSet.to_list()

    before_change = Map.take(data, field_keys)

    after_change = Map.take(changes, field_keys)

    changes =
      %{
        before: if(event == "created", do: nil, else: before_change),
        after: if(after_change === %{}, do: nil, else: after_change)
      }

    audit_changeset(item_type, event, item_id, actor, changes, update_fun)
  end

  def event(item_type, event, item_id, actor, changes, update_fun)
      when is_map(changes) do
    audit_changeset(item_type, event, item_id, actor, changes, update_fun)
  end

  defp audit_changeset(
         item_type,
         event,
         item_id,
         %actor_struct{id: actor_id},
         changes,
         update_fun
       ) do
    changeset(
      %__MODULE__{},
      %{
        item_type: item_type,
        event: event,
        item_id: item_id,
        actor_id: actor_id,
        actor_type: actor_struct |> extract_actor_type(),
        changes: changes
      },
      update_fun
    )
  end

  defp extract_actor_type(struct_name) do
    struct_name
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
  end
end
