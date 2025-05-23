defmodule Lightning.Accounts do
  @moduledoc """
  The Accounts context.
  """

  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Ecto.Multi
  alias Lightning.Accounts.Events
  alias Lightning.Accounts.User
  alias Lightning.Accounts.UserBackupCode
  alias Lightning.Accounts.UserNotifier
  alias Lightning.Accounts.UserToken
  alias Lightning.Accounts.UserTOTP
  alias Lightning.Credentials
  alias Lightning.Projects
  alias Lightning.Repo
  alias Lightning.Services.AccountHook

  require Logger

  defdelegate subscribe(), to: Events

  def has_activity_in_projects?(%User{id: id} = _user) do
    count =
      from(run in Lightning.Run,
        where: run.created_by_id == ^id,
        select: count(run.id)
      )
      |> Repo.one()

    count > 0
  end

  @spec purge_user(id :: Ecto.UUID.t()) :: :ok
  def purge_user(id) do
    Logger.debug(fn ->
      # coveralls-ignore-start
      "Purging user ##{id}..."
      # coveralls-ignore-stop
    end)

    # Remove user from projects
    Ecto.assoc(%User{id: id}, :project_users) |> Repo.delete_all()

    # Delete the credentials of the user.
    # Note that there's a nilify constraint that set all project_credentials associated to this user to nil
    Credentials.list_credentials(%User{id: id})
    |> Enum.each(&Credentials.delete_credential/1)

    Repo.get(User, id) |> delete_user()

    Logger.debug(fn ->
      # coveralls-ignore-start
      "User ##{id} purged."
      # coveralls-ignore-stop
    end)

    :ok
  end

  @doc """
  Perform, when called with %{"type" => "purge_deleted"} will find users that are ready for permanent deletion and purge them.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "purge_deleted"}}) do
    users_to_delete =
      from(u in User,
        as: :user,
        where: u.scheduled_deletion <= ago(0, "second"),
        where:
          not exists(
            from(r in Lightning.Run,
              where: parent_as(:user).id == r.created_by_id,
              select: 1
            )
          ),
        where:
          not exists(
            from(f in Projects.File,
              where: parent_as(:user).id == f.created_by_id,
              select: 1
            )
          )
      )
      |> Repo.all()

    :ok = Enum.each(users_to_delete, fn u -> purge_user(u.id) end)

    {:ok, %{users_deleted: users_to_delete}}
  end

  def create_user(attrs) do
    Repo.transact(fn ->
      AccountHook.handle_create_user(attrs)
    end)
  end

  @doc """
  Returns the list of users.

  ## Examples

      iex> list_users()
      [%User{}, ...]

  """
  def list_users do
    Repo.all(User)
  end

  @doc """
  Returns the list of users with the given emails
  """
  def list_users_by_emails(emails) do
    lowercase_emails = Enum.map(emails, &String.downcase/1)

    query =
      from u in User, where: fragment("LOWER(?)", u.email) in ^lowercase_emails

    Repo.all(query)
  end

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  See `get_user/1`.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a single user.

  ## Examples

      iex> get_user(123)
      %User{}

      iex> get_user!(456)
      nil
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Gets a single token.

  Raises `Ecto.NoResultsError` if the UserToken does not exist.

  ## Examples

      iex> get_token!(123)
      %UserToken{}

      iex> get_token!(456)
      ** (Ecto.NoResultsError)

  """
  def get_token!(id), do: Repo.get!(UserToken, id)

  @doc """
  Gets a single UserTOTP if any exists.
  """
  def get_user_totp(%User{id: user_id}) do
    Repo.get_by(UserTOTP, user_id: user_id)
  end

  @doc """
  Updates or Inserts the user's TOTP
  """
  @spec upsert_user_totp(UserTOTP.t(), map()) ::
          {:ok, UserTOTP.t()} | {:error, Ecto.Changeset.t()}
  def upsert_user_totp(totp, attrs) do
    Multi.new()
    |> Multi.insert_or_update(:totp, UserTOTP.changeset(totp, attrs))
    |> Multi.update(:user, fn %{totp: totp} ->
      totp = Repo.preload(totp, [:user])

      Ecto.Changeset.change(totp.user, %{mfa_enabled: true})
    end)
    |> Multi.run(:backup_codes, fn _repo, %{user: user} ->
      user = Repo.preload(user, [:backup_codes])

      if user.backup_codes == [] do
        regenerate_user_backup_codes(user)
      else
        {:ok, user}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{totp: totp}} -> {:ok, totp}
      {:error, :totp, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Deletes the given user's TOTP
  """
  @spec delete_user_totp(UserTOTP.t()) ::
          {:ok, UserTOTP.t()} | {:error, Ecto.Changeset.t()}
  def delete_user_totp(totp) do
    Multi.new()
    |> Multi.update(:user, fn _changes ->
      totp = Repo.preload(totp, [:user])
      Ecto.Changeset.change(totp.user, %{mfa_enabled: false})
    end)
    |> Multi.delete(:totp, totp)
    |> Repo.transaction()
    |> case do
      {:ok, %{totp: totp}} -> {:ok, totp}
      {:error, _key, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Validates if the given TOTP code is valid.
  """
  @spec valid_user_totp?(User.t(), String.t()) :: true | false
  def valid_user_totp?(user, code) do
    totp = Repo.get_by(UserTOTP, user_id: user.id)

    UserTOTP.valid_totp?(totp, code)
  end

  @doc """
  Validates if the given Backup code is valid.
  """
  @spec valid_user_backup_code?(User.t(), String.t()) :: true | false
  def valid_user_backup_code?(user, code) do
    backup_codes = list_user_backup_codes(user)

    with {backup_codes, true} <- validate_backup_codes(backup_codes, code),
         {:ok, _user} <- update_user_backup_codes(user, backup_codes) do
      true
    else
      _other ->
        false
    end
  end

  defp validate_backup_codes(backup_codes, user_code) do
    Enum.map_reduce(backup_codes, false, fn backup, valid? ->
      if Plug.Crypto.secure_compare(backup.code, user_code) and
           is_nil(backup.used_at) do
        {Ecto.Changeset.change(backup, %{used_at: DateTime.utc_now()}), true}
      else
        {backup, valid?}
      end
    end)
  end

  defp update_user_backup_codes(user, backup_codes) do
    user
    |> Repo.preload([:backup_codes])
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:backup_codes, backup_codes)
    |> Repo.update()
  end

  @doc """
  Regenerates the user backup codes
  """
  @spec regenerate_user_backup_codes(User.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def regenerate_user_backup_codes(user) do
    new_backup_codes =
      Enum.map(1..10, fn _n ->
        %UserBackupCode{code: UserBackupCode.generate_backup_code()}
      end)

    user
    |> Repo.preload([:backup_codes])
    |> Ecto.Changeset.change(%{})
    |> Ecto.Changeset.put_assoc(:backup_codes, new_backup_codes)
    |> Repo.update()
  end

  @doc """
  Lists the user backup codes
  """
  @spec list_user_backup_codes(User.t()) :: [UserBackupCode.t(), ...] | []
  def list_user_backup_codes(user) do
    query = from b in UserBackupCode, where: b.user_id == ^user.id

    Repo.all(query)
  end

  @doc """
  Registers a superuser.

  ## Examples
      iex> register_superuser(%{field: value})
      {:ok, %User{}}

      iex> register_superuser(%{field: bad_value})
      {:error, %Ecto.Changeset{}}
  """

  def register_superuser(attrs) do
    Repo.transact(fn ->
      AccountHook.handle_register_superuser(attrs)
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking superuser changes.

  ## Examples

      iex> change_superuser_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  @spec change_superuser_registration(any) :: Ecto.Changeset.t()
  def change_superuser_registration(attrs \\ %{}) do
    User.superuser_registration_changeset(attrs, hash_password: false)
  end

  @spec register_user(
          :invalid
          | %{optional(:__struct__) => none, optional(atom | binary) => any}
        ) :: any
  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    Repo.transact(fn ->
      AccountHook.handle_register_user(attrs)
    end)
    |> tap(fn result ->
      with {:ok, user} <- result do
        Events.user_registered(user)
        deliver_user_confirmation_instructions(user)
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(attrs \\ %{}) do
    User.user_registration_changeset(attrs, hash_password: false)
  end

  def update_user_details(%User{} = user, attrs \\ %{}) do
    User.details_changeset(user, attrs)
    |> Repo.update()
  end

  def change_user_info(%User{} = user, attrs \\ %{}) do
    User.info_changeset(user, attrs)
  end

  def update_user_info(%User{} = user, attrs) do
    change_user_info(user, attrs) |> Repo.update()
  end

  @doc """
  Updates the user preferences.

  ## Examples

      iex> update_user_preferences(%User{}, %{"editor.orientaion" => "vertical"})
  """
  @spec update_user_preferences(User.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_preferences(%User{} = user, preferences) do
    user
    |> User.preferences_changeset(preferences)
    |> Repo.update()
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user scheduled_deletion.

  ## Examples

      iex> change_scheduled_deletion(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_scheduled_deletion(user, attrs \\ %{}) do
    User.scheduled_deletion_changeset(user, attrs)
  end

  def cancel_scheduled_deletion(user_id) do
    user_id
    |> get_user!()
    |> User.details_changeset(%{
      "scheduled_deletion" => nil,
      "disabled" => false
    })
    |> Repo.update()
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}role: :superuser
      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <-
           UserToken.verify_change_email_token_query(token, context),
         %UserToken{context: context, sent_to: email} <-
           Repo.one(query),
         {:ok, %{user: user}} <-
           Repo.transaction(user_email_multi(user, email, context)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset =
      user
      |> User.email_changeset(%{email: email})
      |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.user_and_contexts_query(user, [context])
    )
  end

  @doc """
  Delivers the update email instructions to the given user.

  ## Examples

      iex> request_email_update(user, new_email)
      :ok

  """
  def request_email_update(%User{} = user, new_email) do
    {encoded_token, user_token} =
      UserToken.build_email_token(user, "change:#{user.email}", new_email)

    with {:ok, _user_token} <- Repo.insert(user_token),
         {:ok, _warning_email} <-
           UserNotifier.deliver_update_email_warning(user, new_email),
         {:ok, instructions_email} <-
           UserNotifier.deliver_update_email_instructions(
             %{user | email: new_email},
             encoded_token
           ) do
      {:ok, instructions_email}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates the changes for updating a user's email address.

  This function ensures that:
  - The `email` and `current_password` fields are present.
  - The new email is in a valid format.
  - The new email is different from the current one.
  - The provided `current_password` matches the user's password.

  ## Parameters

  - `user`: The `%User{}` struct representing the current user.
  - `params`: A map of parameters containing the new email and current password.

  ## Returns

  An `Ecto.Changeset` containing any validation errors.

  ## Examples

      iex> validate_change_user_email(user, %{"email" => "new@example.com", "current_password" => "secret"})
      %Ecto.Changeset{...}

  """
  def validate_change_user_email(user, params \\ %{}) do
    data = %{email: nil, current_password: nil}
    types = %{email: :string, current_password: :string}

    {data, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.validate_required([:email, :current_password])
    |> User.validate_email()
    |> validate_email_changed(user)
    |> validate_current_password(user)
  end

  defp validate_email_changed(changeset, user) do
    Changeset.validate_change(changeset, :email, fn :email, email ->
      if user.email == email do
        [email: "has not changed"]
      else
        []
      end
    end)
  end

  defp validate_current_password(changeset, user) do
    Changeset.validate_change(changeset, :current_password, fn :current_password,
                                                               password ->
      if Bcrypt.verify_pass(password, user.hashed_password) do
        []
      else
        [current_password: "does not match password"]
      end
    end)
  end

  @doc """
  Deletes a user.

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

      iex> delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  def change_user(user, attrs) do
    User.changeset(user, attrs)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.user_and_contexts_query(user, :all)
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Given a user and a confirmation email, this function sets a scheduled deletion
  date based on the PURGE_DELETED_AFTER_DAYS environment variable. If no ENV is
  set, this date defaults to NOW but the automatic user purge cronjob will never
  run. (Note that subsequent logins will be blocked for users pending deletion.)
  """
  def schedule_user_deletion(user, email) do
    date =
      case Lightning.Config.purge_deleted_after_days() do
        nil -> DateTime.utc_now()
        integer -> DateTime.utc_now() |> Timex.shift(days: integer)
      end

    user
    |> User.scheduled_deletion_changeset(%{
      "scheduled_deletion" => date,
      "disabled" => true,
      "scheduled_deletion_email" => email
    })
    |> Repo.update()
    |> case do
      {:ok, user} ->
        UserNotifier.send_deletion_notification_email(user)
        {:ok, user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_token(user, "session")
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    UserToken.verify_token_query(token, "session")
    |> Repo.one()
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_session_token(token) do
    Repo.delete_all(UserToken.token_and_context_query(token, "session"))
    :ok
  end

  ## 2FA Session

  @doc """
  Generates a 2FA session token.
  """
  def generate_sudo_session_token(user) do
    {token, user_token} = UserToken.build_token(user, "sudo_session")
    Repo.insert!(user_token)
    token
  end

  @doc """
  Checks if the given sudo token for the user is valid
  """
  def sudo_session_token_valid?(user, token) do
    token_query = UserToken.verify_token_query(token, "sudo_session")

    query = from t in token_query, where: t.user_id == ^user.id
    Repo.exists?(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_sudo_session_token(token) do
    Repo.delete_all(UserToken.token_and_context_query(token, "sudo_session"))

    :ok
  end

  ## Auth

  @doc """
  Generates an auth token.
  """
  def generate_auth_token(user) do
    {token, user_token} = UserToken.build_token(user, "auth")
    Repo.insert!(user_token)
    token
  end

  @doc """
  Exchanges an auth token for a session token.

  The auth token is removed from the database if successful.
  """
  def exchange_auth_token(auth_token) do
    case get_user_by_auth_token(auth_token) do
      user = %User{} ->
        delete_auth_token(auth_token)
        generate_user_session_token(user)

      any ->
        any
    end
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_auth_token(token) do
    UserToken.verify_token_query(token, "auth")
    |> Repo.one()
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_auth_token(token) do
    Repo.delete_all(UserToken.token_and_context_query(token, "auth"))
    :ok
  end

  ## API

  @doc """
  Generates an API token for a user.
  """
  def generate_api_token(user) do
    {token, user_token} = UserToken.build_token(user, "api")
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_api_token(claims) when is_map(claims) do
    case claims do
      %{sub: "user:" <> id} ->
        Repo.get(User, id)

      _ ->
        nil
    end
  end

  def get_user_by_api_token(token) do
    UserToken.verify_token_query(token, "api")
    |> Repo.one()
  end

  @doc """
  Deletes a token.

  ## Examples

      iex> delete_token(token)
      {:ok, %UserToken{}}

      iex> delete_token(token)
      {:error, %Ecto.Changeset{}}

  """
  def delete_token(%UserToken{} = token) do
    Repo.delete(token)
  end

  @doc """
  Lists all user tokens
  """
  def list_api_tokens(user) do
    UserToken.user_and_contexts_query(user, :api)
    |> Repo.all()
  end

  ## Confirmation

  defp build_email_token(user) do
    {encoded_token, user_token} =
      UserToken.build_email_token(user, "confirm", user.email)

    Repo.insert!(user_token)

    encoded_token
  end

  @doc """
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user)
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user)
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(%User{} = user) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      UserNotifier.deliver_confirmation_instructions(
        user,
        build_email_token(user)
      )
    end
  end

  def deliver_user_confirmation_instructions(
        %User{} = registerer,
        %User{} = user
      ) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      UserNotifier.deliver_confirmation_instructions(
        registerer,
        user,
        build_email_token(user)
      )
    end
  end

  def remind_account_confirmation(%User{} = user) do
    UserNotifier.remind_account_confirmation(
      user,
      build_email_token(user)
    )
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
    with {:ok, query} <-
           UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <-
           Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.user_and_contexts_query(user, ["confirm"])
    )
  end

  ## Reset password

  @doc """
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &Routes.user_reset_password_url(conn, :edit, &1))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(
        %User{} = user,
        reset_password_url_fun
      )
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} =
      UserToken.build_email_token(user, "reset_password", user.email)

    Repo.insert!(user_token)

    UserNotifier.deliver_reset_password_instructions(
      user,
      reset_password_url_fun.(encoded_token)
    )
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <-
           UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.user_and_contexts_query(user, :all)
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Used to determine if there is at least one Superuser in the system.
  This triggers the setup page on fresh installs.
  """
  @spec has_one_superuser?() :: boolean()
  def has_one_superuser? do
    from(u in User, select: count(), where: u.role == :superuser)
    |> Repo.one() >= 1
  end

  @doc """
  Gets all users to alert of workflow failure for a project
  """
  def get_users_to_alert_for_project(%{id: project_id}) do
    from(u in User,
      join: pu in assoc(u, :project_users),
      where: pu.project_id == ^project_id,
      where: pu.failure_alert == true
    )
    |> Repo.all()
  end

  def confirmation_required?(%User{confirmed_at: nil, inserted_at: inserted_at}) do
    Lightning.Config.check_flag?(:require_email_verification) &&
      DateTime.diff(DateTime.utc_now(), inserted_at, :hour) >= 48
  end

  def confirmation_required?(_user), do: false

  @doc """
  Retrieves a specific preference value for a given user.

  Returns the value of the specified key from the user's preferences.
  If the value is the string `"true"` or `"false"`, it is converted to a boolean.

  ## Examples

      iex> get_preference(user, "editor.orientation")
      "vertical"

      iex> get_preference(user, "notifications.enabled")
      true

  """
  @spec get_preference(User.t(), String.t()) :: any()
  def get_preference(%User{id: user_id}, key) do
    from(u in User,
      where: u.id == ^user_id,
      select: fragment("?->>?", u.preferences, ^key)
    )
    |> Repo.one()
    |> case do
      "true" -> true
      "false" -> false
      value -> value
    end
  end

  @doc """
  Updates a specific key in the user's preferences.

  Merges the new key-value pair into the user's existing preferences and updates the database.

  ## Examples

      iex> update_user_preference(user, "editor.orientation", "vertical")
      {:ok, %User{}}

      iex> update_user_preference(user, "notifications.enabled", true)
      {:ok, %User{}}

  """
  @spec update_user_preference(User.t(), String.t(), any()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_preference(%User{} = user, key, value) do
    current_preferences = user.preferences || %{}
    updated_preferences = Map.put(current_preferences, key, value)

    user
    |> User.preferences_changeset(updated_preferences)
    |> Repo.update()
  end
end
