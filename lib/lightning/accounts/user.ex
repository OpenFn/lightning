defmodule Lightning.Accounts.User do
  @moduledoc """
  The User model.
  """
  use Lightning.Schema

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

  @derive {Jason.Encoder,
           only: [:id, :first_name, :last_name, :email, :role, :disabled]}

  schema "users" do
    field :first_name, :string
    field :last_name, :string
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :confirmed, :boolean, virtual: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :role, RolesEnum, default: :user
    field :support_user, :boolean, default: false
    field :disabled, :boolean, default: false
    field :mfa_enabled, :boolean, default: false
    field :scheduled_deletion, :utc_datetime
    field :github_oauth_token, Lightning.Encrypted.Map, redact: true

    field :contact_preference, Ecto.Enum,
      values: [:critical, :any],
      default: :critical

    field :preferences, :map, default: %{}

    has_one :user_totp, Lightning.Accounts.UserTOTP
    has_many :credentials, Lightning.Credentials.Credential
    has_many :oauth_clients, Lightning.Credentials.OauthClient
    has_many :project_users, Lightning.Projects.ProjectUser
    has_many :projects, through: [:project_users, :project]

    has_many :backup_codes, Lightning.Accounts.UserBackupCode,
      on_replace: :delete

    timestamps()
  end

  @doc """
  Returns true when the user's email is on the @openfn.org domain.

  Used to derive Langfuse tracking flags (metrics_opt_in / persona) when
  making AI chat calls to Apollo.
  """
  @spec core_contributor?(t()) :: boolean()
  def core_contributor?(%__MODULE__{email: email}) when is_binary(email) do
    email |> String.downcase() |> String.ends_with?("@openfn.org")
  end

  def core_contributor?(_), do: false

  @doc """
  Returns the Langfuse persona string for a user.

  `"core-contributor"` for @openfn.org users, `"user"` otherwise.
  """
  @spec langfuse_persona(t()) :: String.t()
  def langfuse_persona(%__MODULE__{} = user) do
    if core_contributor?(user), do: "core-contributor", else: "user"
  end

  @doc """
  A user changeset for creating a user.

  `confirmed: true` confirms the email; nothing unconfirms one.
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :first_name,
      :last_name,
      :email,
      :password,
      :contact_preference,
      :role,
      :confirmed
    ])
    |> validate_names()
    |> validate_unique_email()
    |> maybe_validate_password()
    |> confirm_when_asked()
  end

  defp validate_names(changeset) do
    [:first_name, :last_name]
    |> Enum.reduce(changeset, fn field, changeset ->
      changeset
      |> Lightning.Validators.validate_name(field)
      |> validate_length(field, max: 255, count: :codepoints)
    end)
    |> validate_required([:first_name, :last_name], message: "can't be blank")
  end

  defp validate_unique_email(changeset) do
    changeset
    |> validate_email()
    |> unique_constraint(:email)
  end

  defp maybe_validate_password(%{data: %{id: user_id}} = changeset)
       when not is_nil(user_id) do
    changeset = keep_current_password(changeset)

    if get_change(changeset, :password) do
      validate_password(changeset, [])
    else
      changeset
    end
  end

  defp maybe_validate_password(changeset) do
    validate_password(changeset, [])
  end

  # Checked against the password rules first: bcrypt ignores a NUL and
  # anything past 72 bytes, so an invalid password can verify as the current
  # one and must still be refused.
  defp keep_current_password(%{data: user} = changeset) do
    with password when is_binary(password) <- get_change(changeset, :password),
         true <- byte_size(password) <= 72,
         [] <-
           password_changeset(user, %{password: password}, hash_password: false).errors,
         true <- valid_password?(user, password) do
      delete_change(changeset, :password)
    else
      _ -> changeset
    end
  end

  defp confirm_when_asked(changeset) do
    if get_change(changeset, :confirmed) == true and
         is_nil(get_field(changeset, :confirmed_at)),
       do: confirm_changeset(changeset),
       else: changeset
  end

  # `hashed_password` is a type so `maybe_hash_password` can put it, but is
  # never cast from the attrs.
  @common_registration_attrs %{
    first_name: :string,
    last_name: :string,
    email: :string,
    password: :string,
    hashed_password: :string,
    contact_preference:
      Ecto.ParameterizedType.init(Ecto.Enum, values: [:critical, :any])
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
      [
        :terms_accepted
        | Map.keys(@common_registration_attrs) -- [:hashed_password]
      ]
    )
    |> validate_email()
    |> validate_names()
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
    |> cast(attrs, Map.keys(registration_fields) -- [:hashed_password])
    |> validate_email()
    |> validate_names()
    |> validate_password(opts)
    |> put_change(:role, :superuser)
  end

  def validate_email_exists(changeset) do
    changeset
    |> validate_change(:email, fn :email, email ->
      if Lightning.Repo.exists?(User |> where(email: ^email)) do
        [email: {"has already been taken", validation: :unsafe_unique}]
      else
        []
      end
    end)
  end

  def validate_email(changeset) do
    changeset
    |> Lightning.Validators.validate_email_format()
    |> validate_email_exists()
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required(:password, message: "can't be blank")
    |> validate_length(:password, min: 12, max: 72)
    |> Lightning.Validators.validate_no_null_bytes(
      :password,
      "can't contain a NUL character"
    )
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> validate_length(:password, min: 8, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing a user's details, with the same rules as
  `changeset/2`. A password that is already the user's changes nothing.
  """
  def details_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :password,
      :first_name,
      :last_name,
      :role,
      :support_user,
      :disabled,
      :scheduled_deletion,
      :confirmed
    ])
    |> validate_names()
    |> validate_unique_email()
    |> maybe_validate_password()
    |> confirm_when_asked()
    |> maybe_clear_scheduled_deletion()
  end

  @doc """
  A user changeset for basic information:

  - first_name
  - last_name
  - contact_preference
  """
  def info_changeset(user, attrs) do
    user
    |> cast(attrs, [:first_name, :last_name, :contact_preference])
    |> validate_names()
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

  @spec remove_github_token_changeset(t()) :: Ecto.Changeset.t()
  def remove_github_token_changeset(user) do
    change(user, github_oauth_token: nil)
  end

  def github_token_changeset(user, attrs) do
    user
    |> cast(attrs, [:github_oauth_token])
    |> validate_required([:github_oauth_token])
  end

  def preferences_changeset(user, attrs) do
    user
    |> change(%{preferences: Map.merge(user.preferences, attrs)})
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

  defp maybe_clear_scheduled_deletion(changeset) do
    case fetch_field(changeset, :role) do
      {_source, :superuser} -> put_change(changeset, :scheduled_deletion, nil)
      _anything_else -> changeset
    end
  end
end
