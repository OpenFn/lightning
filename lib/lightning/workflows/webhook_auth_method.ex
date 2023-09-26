defmodule Lightning.Workflows.WebhookAuthMethod do
  use Ecto.Schema
  use Joken.Config
  import Ecto.Changeset

  @auth_types [:basic, :api]
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "webhook_auth_methods" do
    field :name, :string
    field :auth_type, Ecto.Enum, values: @auth_types, default: :basic
    field :username, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :api_key, :string

    belongs_to :creator, Lightning.Accounts.User
    belongs_to :project, Lightning.Projects.Project

    many_to_many :triggers, Lightning.Jobs.Trigger,
      join_through: "trigger_webhook_auth_methods"

    timestamps()
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [
      :name,
      :auth_type,
      :username,
      :password,
      :creator_id,
      :project_id
    ])
    |> validate_required([:name, :auth_type, :creator_id, :project_id])
    |> validate_inclusion(:auth_type, @auth_types, message: "must be basic or api")
    |> validate_auth_fields()
    |> apply_unique_constraints()
  end

  defp apply_unique_constraints(changeset) do
    changeset
    |> unique_constraint(
      :name,
      name: "webhook_auth_methods_name_project_id_index",
      message: "must be unique within the project"
    )
    |> unique_constraint(
      :username,
      name: "webhook_auth_methods_username_project_id_index",
      message: "must be unique within the project"
    )
    |> unique_constraint(
      :api_key,
      name: "webhook_auth_methods_api_key_project_id_index",
      message: "must be unique within the project"
    )
  end

  defp validate_auth_fields(changeset) do
    case get_field(changeset, :auth_type) do
      :basic ->
        changeset
        |> validate_required([:password, :username], message: "can't be blank")
        |> validate_length(:password, min: 8, max: 72)
        |> maybe_hash_password()

      :api ->
        changeset
        |> generate_api_key(32)

      _ ->
        changeset
    end
  end

  defp generate_api_key(changeset, api_key_length) do
    api_key =
      :crypto.strong_rand_bytes(api_key_length) |> Base.encode16(case: :lower)

    put_change(changeset, :api_key, api_key)
  end

  defp maybe_hash_password(changeset) do
    password = get_change(changeset, :password)

    if password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Verifies the password.

  If there is no webhook_auth_method or the webhook_auth_method doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(
        %Lightning.Workflows.WebhookAuthMethod{hashed_password: hashed_password},
        password
      )
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
