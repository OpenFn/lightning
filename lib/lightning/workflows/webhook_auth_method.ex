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
  use Lightning.Schema

  @type t :: %__MODULE__{}

  @auth_types [:basic, :api]

  schema "webhook_auth_methods" do
    field :name, :string
    field :auth_type, Ecto.Enum, values: @auth_types
    field :username, Lightning.Encrypted.Binary
    field :password, Lightning.Encrypted.Binary
    field :api_key, Lightning.Encrypted.Binary
    field :scheduled_deletion, :utc_datetime

    belongs_to :project, Lightning.Projects.Project

    many_to_many :triggers, Lightning.Workflows.Trigger,
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
      :project_id,
      :api_key,
      :scheduled_deletion
    ])
    |> validate_required([:name, :auth_type, :project_id])
    |> validate_auth_fields()
    |> unique_constraint(
      :name,
      name: "webhook_auth_methods_name_project_id_index",
      message: "must be unique within the project"
    )
  end

  def update_changeset(struct, params) do
    struct
    |> cast(params, [:name])
    |> validate_required([:name])
  end

  defp validate_auth_fields(changeset) do
    case get_field(changeset, :auth_type) do
      :basic ->
        changeset
        |> validate_required([:password, :username], message: "can't be blank")
        |> validate_length(:password, min: 8, max: 72)

      :api ->
        changeset
        |> delete_change(:username)
        |> delete_change(:password)
        |> maybe_add_api_key()

      _ ->
        changeset
    end
  end

  defp maybe_add_api_key(changeset) do
    if changeset.valid? and !get_field(changeset, :api_key) do
      put_change(changeset, :api_key, generate_api_key())
    else
      changeset
    end
  end

  def generate_api_key(length \\ 32) do
    length |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end

  @doc """
  Retrieves sensitive values from a WebhookAuthMethod for use in log scrubbing.

  For `:basic` auth, returns the username and password.
  For `:api` auth, returns the api_key.

  ## Examples

      iex> sensitive_values_for(%WebhookAuthMethod{auth_type: :basic, username: "user", password: "pass"})
      ["user", "pass"]

      iex> sensitive_values_for(%WebhookAuthMethod{auth_type: :api, api_key: "secret123"})
      ["secret123"]

      iex> sensitive_values_for(nil)
      []
  """
  @spec sensitive_values_for(t() | nil) :: [String.t()]
  def sensitive_values_for(nil), do: []

  def sensitive_values_for(%__MODULE__{auth_type: :basic} = auth_method) do
    [auth_method.password]
    |> Enum.reject(&is_nil/1)
  end

  def sensitive_values_for(%__MODULE__{auth_type: :api} = auth_method) do
    if auth_method.api_key, do: [auth_method.api_key], else: []
  end

  def sensitive_values_for(%__MODULE__{}), do: []

  @doc """
  Retrieves basic auth strings from a WebhookAuthMethod for use in log scrubbing.

  Returns a list of base64-encoded "username:password" strings that might appear
  in Authorization headers.

  ## Examples

      iex> basic_auth_for(%WebhookAuthMethod{auth_type: :basic, username: "user", password: "pass"})
      ["dXNlcjpwYXNz"]

      iex> basic_auth_for(%WebhookAuthMethod{auth_type: :api, api_key: "secret"})
      []
  """
  @spec basic_auth_for(t() | nil) :: [String.t()]
  def basic_auth_for(nil), do: []

  def basic_auth_for(%__MODULE__{auth_type: :basic} = auth_method) do
    if auth_method.username && auth_method.password do
      ["#{auth_method.username}:#{auth_method.password}" |> Base.encode64()]
    else
      []
    end
  end

  def basic_auth_for(%__MODULE__{}), do: []
end
