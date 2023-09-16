defmodule Lightning.Credentials.Audit do
  @moduledoc """
  Model for storing changes to Credentials
  """
  use Lightning.Auditing.Model,
    repo: Lightning.Repo,
    schema: __MODULE__,
    events: [
      "created",
      "updated",
      "added_to_project",
      "removed_from_project",
      "deleted"
    ]

  defmodule Changes do
    @moduledoc false

    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :before, :map
      field :after, :map
    end

    @doc false
    def changeset(changes, attrs \\ %{}) do
      changes
      |> cast(attrs, [:before, :after])
      |> update_change(:before, &encrypt_body/1)
      |> update_change(:after, &encrypt_body/1)
    end

    defp encrypt_body(changes) when is_map(changes) do
      if Map.has_key?(changes, :body) do
        changes
        |> Map.update(:body, nil, fn val ->
          {:ok, val} = Lightning.Encrypted.Map.dump(val)
          val |> Base.encode64()
        end)
      else
        changes
      end
    end
  end

  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "audit_events" do
    field :event, :string
    field :item_type, :string
    field :item_id, Ecto.UUID
    embeds_one :changes, Changes
    field :actor_id, Ecto.UUID

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(%__MODULE__{} = audit, attrs) do
    audit
    |> cast(attrs, [:event, :item_id, :actor_id, :item_type])
    |> cast_embed(:changes)
    |> validate_required([:event, :actor_id])
  end
end
