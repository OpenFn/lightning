defmodule Lightning.Accounts.UserToken do
  @moduledoc """
  The UserToken model.

  The reason why we store session tokens in the database, even
  though Phoenix already provides a session cookie, is because
  Phoenix' default session cookies are not persisted, they are
  simply signed and potentially encrypted. This means they are
  valid indefinitely, unless you change the signing/encryption
  salt.

  Therefore, storing them allows individual user
  sessions to be expired. The token system can also be extended
  to store additional data, such as the device used for logging in.
  You could then use this information to display all valid sessions
  and devices in the UI and allow users to explicitly expire any
  session they deem invalid.
  """

  use Ecto.Schema
  use Joken.Config

  import Ecto.Changeset
  import Ecto.Query

  alias Lightning.Accounts.User

  @hash_algorithm :sha256
  @rand_size 32

  # It is very important to keep the reset password token expiry short,
  # since someone with access to the email may take over the account.
  @reset_password_validity_in_days 1
  @confirm_validity_in_days 7
  @change_email_validity_in_days 7
  @session_validity_in_days 60
  @sudo_session_validity_in_seconds 60 * 5
  @auth_validity_in_seconds 30

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "user_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :last_used_at, :utc_datetime_usec

    belongs_to :user, User

    timestamps updated_at: false
  end

  def token_config do
    default_claims(skip: [:exp])
    |> add_claim(
      "my_key",
      fn -> "My custom claim" end,
      &(&1 == "My custom claim")
    )
  end

  @doc """
  Generates a token that will be stored in a signed place,
  such as session or cookie. As they are signed, those
  tokens do not need to be hashed.
  """
  @spec build_token(User.t(), context :: binary()) ::
          {binary(), Ecto.Changeset.t(%__MODULE__{})}
  def build_token(user, "api" = context) do
    token =
      Joken.generate_and_sign!(default_claims(skip: [:exp]), %{
        "user_id" => user.id
      })

    {token,
     changeset(%__MODULE__{}, %{token: token, context: context, user_id: user.id})}
  end

  def build_token(user, context) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {token,
     changeset(%__MODULE__{}, %{token: token, context: context, user_id: user.id})}
  end

  @doc """
  Update when the api token was last used by setting`last_used_at`.
  """
  def last_used_changeset(user) do
    now = DateTime.utc_now()
    change(user, last_used_at: now)
  end

  def changeset(user_token, attrs) do
    user_token
    |> cast(attrs, [:token, :context, :user_id, :sent_to, :last_used_at])
    |> validate_required([:token, :context, :user_id])
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any.

  The token is valid if it matches the value in the database and it has
  not expired (after @auth_validity_in_seconds or @session_validity_in_days).
  """
  def verify_token_query(token, "auth" = context) do
    query =
      from(token in token_and_context_query(token, context),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@auth_validity_in_seconds, "second"),
        select: user
      )

    {:ok, query}
  end

  def verify_token_query(token, "api" = context) do
    query =
      from(token in token_and_context_query(token, context),
        join: user in assoc(token, :user),
        select: user
      )

    {:ok, query}
  end

  def verify_token_query(token, "session" = context) do
    query =
      from(token in token_and_context_query(token, context),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: user
      )

    {:ok, query}
  end

  def verify_token_query(token, "sudo_session" = context) do
    query =
      from(token in token_and_context_query(token, context),
        join: user in assoc(token, :user),
        where:
          token.inserted_at >
            ago(@sudo_session_validity_in_seconds, "second"),
        select: user
      )

    {:ok, query}
  end

  @doc """
  Builds a token and its hash to be delivered to the user's email.

  The non-hashed token is sent to the user email while the
  hashed part is stored in the database. The original token cannot be reconstructed,
  which means anyone with read-only access to the database cannot directly use
  the token in the application to gain access. Furthermore, if the user changes
  their email in the system, the tokens sent to the previous email are no longer
  valid.

  Users can easily adapt the existing code to provide other types of delivery methods,
  for example, by phone numbers.
  """
  def build_email_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     changeset(%__MODULE__{}, %{
       token: hashed_token,
       context: context,
       user_id: user.id,
       sent_to: sent_to
     })}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any.

  The given token is valid if it matches its hashed counterpart in the
  database and the user email has not changed. This function also checks
  if the token is being used within a certain period, depending on the
  context. The default contexts supported by this function are either
  "confirm", for account confirmation emails, and "reset_password",
  for resetting the password. For verifying requests to change the email,
  see `verify_change_email_token_query/2`.
  """
  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)
        days = days_for_context(context)

        query =
          from(token in token_and_context_query(hashed_token, context),
            join: user in assoc(token, :user),
            where:
              token.inserted_at > ago(^days, "day") and
                token.sent_to == user.email,
            select: user
          )

        {:ok, query}

      :error ->
        :error
    end
  end

  defp days_for_context("confirm"), do: @confirm_validity_in_days
  defp days_for_context("reset_password"), do: @reset_password_validity_in_days

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any.

  This is used to validate requests to change the user
  email. It is different from `verify_email_token_query/2` precisely because
  `verify_email_token_query/2` validates the email has not changed, which is
  the starting point by this function.

  The given token is valid if it matches its hashed counterpart in the
  database and if it has not expired (after @change_email_validity_in_days).
  The context must always start with "change:".
  """
  def verify_change_email_token_query(token, "change:" <> _ = context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from(t in Lightning.Accounts.UserToken,
            where: t.token == ^hashed_token,
            where: t.context == ^context,
            where: t.inserted_at > ago(@change_email_validity_in_days, "day")
          )

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc """
  Returns the token struct for the given token value and context.
  """
  def token_and_context_query(token, context) do
    from(Lightning.Accounts.UserToken, where: [token: ^token, context: ^context])
  end

  @doc """
  Gets all tokens for the given user for the given contexts.
  """
  def user_and_contexts_query(user, :all) do
    from(t in Lightning.Accounts.UserToken, where: t.user_id == ^user.id)
  end

  def user_and_contexts_query(user, [_ | _] = contexts) do
    from(t in Lightning.Accounts.UserToken,
      where: t.user_id == ^user.id and t.context in ^contexts
    )
  end

  def user_and_contexts_query(user, :api) do
    from(t in Lightning.Accounts.UserToken,
      where: t.user_id == ^user.id and t.context == "api",
      order_by: [desc: :inserted_at]
    )
  end
end
