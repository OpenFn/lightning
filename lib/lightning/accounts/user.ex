defmodule Lightning.Accounts.User do
  @moduledoc """
  The User model.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  import EctoEnum

  alias __MODULE__

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil
        }

  defenum(RolesEnum, :role, [
    :user,
    :superuser
  ])

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :first_name, :string
    field :last_name, :string
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :role, RolesEnum, default: :user
    field :disabled, :boolean, default: false
    field :mfa_enabled, :boolean, default: false
    field :scheduled_deletion, :utc_datetime

    has_one :user_totp, Lightning.Accounts.UserTOTP
    has_many :credentials, Lightning.Credentials.Credential
    has_many :project_users, Lightning.Projects.ProjectUser
    has_many :projects, through: [:project_users, :project]

    has_many :backup_codes, Lightning.Accounts.UserBackupCode,
      on_replace: :delete

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :first_name,
      :last_name,
      :email,
      :password
    ])
    |> validate_name()
    |> validate_email()
    |> validate_password([])
  end

  @common_registration_attrs %{
    first_name: :string,
    last_name: :string,
    email: :string,
    password: :string,
    hashed_password: :string,
    disabled: :boolean,
    scheduled_deletion: :utc_datetime
  }

  @doc """
  A user changeset for registration.

  It is important to validate the length of both email and password.
  Otherwise databases may truncate the email without warnings, which
  could lead to unpredictable or insecure behaviour. Long passwords may
  also be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def user_registration_changeset(attrs, opts \\ []) do
    {%{},
     Map.merge(@common_registration_attrs, %{
       terms_accepted: :boolean
     })}
    |> cast(
      attrs,
      Map.keys(@common_registration_attrs) ++
        [
          :terms_accepted
        ]
    )
    |> validate_email()
    |> validate_password(opts)
    |> validate_change(:terms_accepted, fn :terms_accepted, terms_accepted ->
      if terms_accepted do
        []
      else
        [terms_accepted: "Please accept the terms and conditions to register."]
      end
    end)
  end

  @spec superuser_registration_changeset(
          :invalid
          | %{optional(:__struct__) => none, optional(atom | binary) => any},
          keyword
        ) :: Ecto.Changeset.t()
  @doc """
  A superuser changeset for registration.

  It is important to validate the length of both email and password.
  Otherwise databases may truncate the email without warnings, which
  could lead to unpredictable or insecure behaviour. Long passwords may
  also be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def superuser_registration_changeset(attrs, opts \\ []) do
    registration_fields = Map.merge(@common_registration_attrs, %{role: :string})

    {%{}, registration_fields}
    |> cast(attrs, Map.keys(registration_fields))
    |> validate_email()
    |> validate_password(opts)
    |> put_change(:role, :superuser)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required(:email, message: "can't be blank")
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> validate_change(:email, fn :email, email ->
      if Lightning.Repo.exists?(User |> where(email: ^email)) do
        [email: "has already been taken"]
      else
        []
      end
    end)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required(:password, message: "can't be blank")
    |> validate_length(:password, min: 8, max: 72)
    |> maybe_hash_password(opts)
  end

  defp validate_name(changeset) do
    changeset
    |> validate_required([:first_name, :last_name], message: "can't be blank")
  end

  defp validate_role(changeset) do
    changeset
    |> validate_inclusion(:role, RolesEnum)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, min: 8, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  A user changeset for user details:

  - email
  - first_name
  - last_name
  - role
  """
  def details_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :first_name,
      :last_name,
      :role,
      :disabled,
      :scheduled_deletion
    ])
    |> validate_email()
    |> validate_name()
    |> validate_role()
  end

  @doc """
  A user changeset for changing the email.

  It requires the email to change otherwise an error is added.
  """
  def email_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_email()
    |> case do
      %{changes: %{email: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :email, "did not change")
    end
  end

  @doc """
  A user changeset for changing the scheduled_deletion property.
  """
  def scheduled_deletion_changeset(user, attrs) do
    user
    |> cast(attrs, [:scheduled_deletion, :disabled])
    |> validate_role_for_deletion()
    |> validate_email_for_deletion(attrs["scheduled_deletion_email"])
  end

  @doc """
  A user changeset for changing the password.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(
        %Lightning.Accounts.User{hashed_password: hashed_password},
        password
      )
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  Validates the current password otherwise adds an error to the changeset.
  """
  def validate_current_password(changeset, password) do
    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end

  defp validate_role_for_deletion(changeset) do
    if changeset.data.role == :superuser do
      add_error(
        changeset,
        :scheduled_deletion_email,
        "You can't delete a superuser account."
      )
    else
      changeset
    end
  end

  defp validate_email_for_deletion(changeset, email) do
    if email == changeset.data.email do
      changeset
    else
      add_error(
        changeset,
        :scheduled_deletion_email,
        "This email doesn't match your current email"
      )
    end
  end
end
