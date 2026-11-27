defmodule Lightning.Accounts.SignInAttempts do
  @moduledoc """
  Checks a password or MFA code sent to sign in, and limits how often someone
  can try. The API (`POST /api/session`), the log-in and two-factor pages and
  the forms that ask a signed-in user to re-enter a password or code check
  through here, so they share one limit per account.

  Attempts are counted per account, by its email address in lower case,
  whether or not an account has it, so the limit can't be used to find
  accounts. Each attempt is counted before it is checked, so requests sent
  together can't all be checked against a count none of them has raised yet,
  and after ten in 15 minutes every attempt is refused, right or wrong, until
  the window ends. A right password or code takes its attempt back off the
  count, so only failures add up: a person who signs in often is never
  limited, and signing in doesn't clear the failures someone else ran up.
  Every refusal says how many seconds of the window are left.

  A sign-in waiting for its MFA code also gets five tries at it: when the
  fifth fails the caller ends that session, so the password has to be entered
  again.

  The counts live in the `sign_in_attempts` table, so every node in a cluster
  shares them and a deploy doesn't reset them. Each count runs for a fixed
  15-minute window from its first attempt, by the database's clock. This module
  is also the Oban worker that deletes counts whose window has ended.

  There is no limit per client address: behind a load balancer every request
  comes from the balancer's address, so such a limit would lock everyone out
  together.
  """
  use Oban.Worker, queue: :background, max_attempts: 3

  import Ecto.Query

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Repo

  @attempt_limit 10
  @code_limit 5
  @window_seconds 900

  # Lower-cased by the database, as it does when it finds the account by email,
  # so every spelling of an address that reaches one account shares one count.
  @email_key_sql """
  'sign_in_failures::' || translate(
    encode(sha256(convert_to(lower($1::text), 'UTF8')), 'base64'), '+/', '-_')
  """

  @type rate_limited :: {:rate_limited, pos_integer()}
  @type code :: {:totp, String.t()} | {:backup_code, String.t()}

  @doc """
  Checks `password` for the account with `email`, counting the attempt. The
  account may still be disabled or scheduled for deletion; that is the
  caller's to check.
  """
  @spec check_password(String.t(), String.t()) ::
          {:ok, User.t()} | {:error, :invalid_credentials | rate_limited()}
  def check_password(email, password)
      when is_binary(email) and is_binary(password) do
    with {:ok, window} <- attempt(email) do
      case Accounts.get_user_by_email_and_password(email, password) do
        %User{} = user ->
          take_back(email, window)
          {:ok, user}

        nil ->
          {:error, :invalid_credentials}
      end
    end
  end

  @doc """
  Checks `password` for a signed-in `user` who is asked for it again, counting
  the attempt on the account's sign-in count. A limited account is refused
  even with the right password, and is not signed out.
  """
  @spec confirm_password(User.t(), String.t()) ::
          :ok | {:error, :invalid_credentials | rate_limited()}
  def confirm_password(%User{} = user, password) when is_binary(password),
    do: counted(user.email, fn -> User.valid_password?(user, password) end)

  @doc """
  Checks an MFA `code` for `user`, counting the attempt, when there is no
  pending sign-in: the password came in the same request, or the user is
  already signed in and asked for the code again.
  """
  @spec check_code(User.t(), code()) ::
          :ok | {:error, :invalid_credentials | rate_limited()}
  def check_code(%User{} = user, code),
    do: counted(user.email, fn -> valid_code?(user, code) end)

  @doc """
  Checks an MFA `code` to finish the pending sign-in holding `session_token`,
  counting the attempt and taking one of the sign-in's five tries.
  `{:error, :tries_spent}` means the last try has gone, so the caller must end
  that session.
  """
  @spec check_code(User.t(), code(), binary()) ::
          :ok | {:error, :invalid_credentials | :tries_spent | rate_limited()}
  def check_code(%User{} = user, code, session_token)
      when is_binary(session_token) do
    with {:ok, window} <- attempt(user.email) do
      tries = code_tries(session_token)

      cond do
        tries != :spent and valid_code?(user, code) ->
          take_back(user.email, window)

        tries == :ok ->
          {:error, :invalid_credentials}

        true ->
          {:error, :tries_spent}
      end
    end
  end

  defp valid_code?(%User{mfa_enabled: true} = user, {:totp, code}),
    do: Accounts.valid_user_totp?(user, code)

  defp valid_code?(%User{mfa_enabled: true} = user, {:backup_code, code}),
    do: Accounts.valid_user_backup_code?(user, code)

  defp valid_code?(_user, _code), do: false

  defp counted(email, valid?) do
    with {:ok, window} <- attempt(email) do
      if valid?.(),
        do: take_back(email, window),
        else: {:error, :invalid_credentials}
    end
  end

  defp attempt(email) do
    case count(@email_key_sql, email) do
      {count, _seconds_left, window} when count <= @attempt_limit ->
        {:ok, window}

      {_count, seconds_left, _window} ->
        {:error, {:rate_limited, seconds_left}}
    end
  end

  # Only the window this attempt was counted in: if it ended meanwhile, the
  # count now belongs to someone else's attempt.
  defp take_back(email, window) do
    Repo.query!(
      """
      UPDATE sign_in_attempts SET count = count - 1
      WHERE key = #{@email_key_sql} AND count > 0 AND window_started_at = $2
      """,
      [email, window]
    )

    :ok
  end

  # :ok while tries remain after this one, :last for the fifth, :spent after.
  defp code_tries(session_token) do
    {count, _seconds_left, _window} =
      count("$1", "pending_mfa_attempts::" <> digest(session_token))

    case count do
      count when count < @code_limit -> :ok
      @code_limit -> :last
      _over -> :spent
    end
  end

  @doc "Deletes the counts whose window has ended."
  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    from(a in "sign_in_attempts",
      where:
        a.window_started_at <=
          fragment(
            "timezone('utc', now()) - ?::integer * interval '1 second'",
            @window_seconds
          )
    )
    |> Repo.delete_all()

    :ok
  end

  # One statement, so concurrent attempts on any node queue on the row's lock
  # and each gets its own count. The window is timed by the database's clock
  # so nodes whose clocks differ agree on when it ends. The same statement
  # returns the seconds left in the window, so a refusal can say when to try
  # again; for a refused attempt it is between 1 and 900.
  defp count(key_sql, value) do
    %{rows: [[count, seconds_left, window]]} =
      Repo.query!(
        """
        INSERT INTO sign_in_attempts AS a (key, count, window_started_at)
        VALUES (#{key_sql}, 1, timezone('utc', now()))
        ON CONFLICT (key) DO UPDATE SET
          count = CASE
            WHEN a.window_started_at <= timezone('utc', now()) - $2::integer * interval '1 second'
            THEN 1 ELSE a.count + 1 END,
          window_started_at = CASE
            WHEN a.window_started_at <= timezone('utc', now()) - $2::integer * interval '1 second'
            THEN timezone('utc', now()) ELSE a.window_started_at END
        RETURNING count,
          ceil(extract(epoch FROM
            a.window_started_at + $2::integer * interval '1 second' - timezone('utc', now())
          ))::integer,
          a.window_started_at
        """,
        [value, @window_seconds]
      )

    {count, seconds_left, window}
  end

  defp digest(value), do: Base.url_encode64(:crypto.hash(:sha256, value))
end
