defmodule Lightning.Workflows.WebhookAuthMethod do
  @moduledoc """
  The `Lightning.Workflows.WebhookAuthMethod` module defines the schema for webhook authentication methods and provides functionalities to handle them.

  ## Schema
  The schema represents a webhook authentication method that can be of two types - `:basic` and `:api`. The basic type requires a username and password, while the api type requires an api_key.

  The schema fields include:
    - `name`: the name of the authentication method
    - `auth_type`: the type of authentication, can be `:basic` or `:api`
    - `username`: the username required for basic authentication
    - `password`: the password required for basic authentication (virtual field)
    - `hashed_password`: the hashed version of the password
    - `api_key`: the API key required for API authentication

  ## Associations
  Each `WebhookAuthMethod` belongs to a `project`.
  It is also associated with multiple `triggers` through a many_to_many relationship.

  ## Validations and Constraints
  This module provides changeset functions for casting and validating the schema fields and applying unique constraints on `name`, `username`, and `api_key` within the project scope.

  ## Password Verification
  The `valid_password?/2` function is provided to verify passwords and it avoids timing attacks by using `Bcrypt.no_user_verify/0` when there is no webhook_auth_method or the webhook_auth_method doesn't have a password.

  """
  alias Lightning.Workflows.WebhookAuthMethod
  use Ecto.Schema
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
      :project_id
    ])
    |> validate_required([:name, :auth_type, :project_id])
    |> validate_auth_fields()
    |> unique_constraint(
      :name,
      name: "webhook_auth_methods_name_project_id_index",
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
        |> delete_change(:username)
        |> delete_change(:password)
        |> generate_api_key(32)

      _ ->
        changeset
    end
  end

  defp generate_api_key(changeset, api_key_length) do
    api_key =
      :crypto.strong_rand_bytes(api_key_length) |> Base.encode16(case: :lower)

    put_change(changeset, :api_key, Bcrypt.hash_pwd_salt(api_key))
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
        %WebhookAuthMethod{hashed_password: hashed_password},
        password
      ) do
    verify_pass?(hashed_password, password)
  end

  @doc """
  Verifies the password.

  If there is no webhook_auth_method or the webhook_auth_method doesn't have an api key, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_api_key?(%WebhookAuthMethod{api_key: hashed_api_key}, api_key) do
    verify_pass?(hashed_api_key, api_key)
  end

  defp verify_pass?(hashed, clear)
       when is_binary(hashed) and byte_size(clear) > 0 do
    Bcrypt.verify_pass(clear, hashed)
  end

  defp verify_pass?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
