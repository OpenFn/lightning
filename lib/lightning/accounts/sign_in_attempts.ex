defmodule Lightning.Accounts.SignInAttempts do
  @moduledoc """
  Checks a password or MFA code sent to sign in, and limits how often someone
  can try. The API (`POST /api/session`) and the log-in and two-factor pages
  check through here, so they share one limit per account.

  Attempts are counted per account, by its email address in lower case,
  whether or not an account has it, so the limit can't be used to find
  accounts. Each attempt is counted before it is checked, so requests sent
  together can't all be checked against a count none of them has raised yet,
  and after ten in 15 minutes every attempt is refused, right or wrong, until
  the window ends. A right password or code takes its attempt back off the
  count, so only failures add up: a person who signs in often is never
  limited, and signing in doesn't clear the failures someone else ran up.

  A sign-in waiting for its MFA code also gets five tries at it: when the
  fifth fails the caller ends that session, so the password has to be entered
  again.

  The counts live in the `sign_in_attempts` table, so every node in a cluster
  shares them and a deploy doesn't reset them. Each runs for a fixed 15-minute
  window from its first attempt, by the database's clock. This module is also
  the Oban worker that deletes counts whose window has ended.

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

  @type code :: {:totp, String.t()} | {:backup_code, String.t()}

  @doc """
  Checks `password` for the account with `email`, counting the attempt. The
  account may still be disabled or scheduled for deletion; that is the
  caller's to check.
  """
  @spec check_password(String.t(), String.t()) ::
          {:ok, User.t()} | {:error, :invalid_credentials | :rate_limited}
  def check_password(email, password)
      when is_binary(email) and is_binary(password) do
    with :ok <- attempt(email) do
      case Accounts.get_user_by_email_and_password(email, password) do
        %User{} = user ->
          take_back(email)
          {:ok, user}

        nil ->
          {:error, :invalid_credentials}
      end
    end
  end

  @doc """
  Checks an MFA `code` for `user`, counting the attempt, when there is no
  pending sign-in: the password came in the same request.
  """
  @spec check_code(User.t(), code()) ::
          :ok | {:error, :invalid_code | :rate_limited}
  def check_code(%User{} = user, code) do
    with :ok <- attempt(user.email) do
      if valid_code?(user, code),
        do: take_back(user.email),
        else: {:error, :invalid_code}
    end
  end

  @doc """
  Checks an MFA `code` to finish the pending sign-in holding `session_token`,
  counting the attempt and taking one of the sign-in's five tries.
  `{:error, :tries_spent}` means the last try has gone, so the caller must end
  that session.
  """
  @spec check_code(User.t(), code(), binary()) ::
          :ok | {:error, :invalid_code | :tries_spent | :rate_limited}
  def check_code(%User{} = user, code, session_token)
      when is_binary(session_token) do
    with :ok <- attempt(user.email) do
      tries = code_tries(session_token)

      cond do
        tries != :spent and valid_code?(user, code) -> take_back(user.email)
        tries == :ok -> {:error, :invalid_code}
        true -> {:error, :tries_spent}
      end
    end
  end

  defp valid_code?(%User{mfa_enabled: true} = user, {:totp, code}),
    do: Accounts.valid_user_totp?(user, code)

  defp valid_code?(%User{mfa_enabled: true} = user, {:backup_code, code}),
    do: Accounts.valid_user_backup_code?(user, code)

  defp valid_code?(_user, _code), do: false

  defp attempt(email) do
    if count(email_key(email)) <= @attempt_limit,
      do: :ok,
      else: {:error, :rate_limited}
  end

  defp take_back(email) do
    key = email_key(email)

    from(a in "sign_in_attempts",
      where: a.key == ^key and a.count > 0,
      update: [inc: [count: -1]]
    )
    |> Repo.update_all([])

    :ok
  end

  # :ok while tries remain after this one, :last for the fifth, :spent after.
  defp code_tries(session_token) do
    case count("pending_mfa_attempts::" <> digest(session_token)) do
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
          fragment("timezone('utc', now()) - interval '15 minutes'")
    )
    |> Repo.delete_all()

    :ok
  end

  # One statement, so concurrent attempts on any node queue on the row's lock
  # and each gets its own count. The window is timed by the database's clock
  # so nodes whose clocks differ agree on when it ends.
  defp count(key) do
    %{rows: [[count]]} =
      Repo.query!(
        """
        INSERT INTO sign_in_attempts AS a (key, count, window_started_at)
        VALUES ($1, 1, timezone('utc', now()))
        ON CONFLICT (key) DO UPDATE SET
          count = CASE
            WHEN a.window_started_at <= timezone('utc', now()) - interval '15 minutes'
            THEN 1 ELSE a.count + 1 END,
          window_started_at = CASE
            WHEN a.window_started_at <= timezone('utc', now()) - interval '15 minutes'
            THEN timezone('utc', now()) ELSE a.window_started_at END
        RETURNING count
        """,
        [key]
      )

    count
  end

  # The address is whatever the request sent, of any length, so the key is
  # its hash.
  defp email_key(email),
    do: "sign_in_failures::" <> digest(String.downcase(email))

  defp digest(value), do: Base.url_encode64(:crypto.hash(:sha256, value))
end
