defmodule Lightning.Accounts.SignInAttempts do
  @moduledoc """
  Limits attempts to prove who someone is: a password or MFA code sent to sign
  in, or to finish an MFA sign-in.

  Only `POST /api/session` counts and checks them so far. The log-in and
  two-factor pages don't, so the limits here don't yet hold for an account as a
  whole.

  The counts live in the `sign_in_attempts` table, so every node in a cluster
  shares them and a deploy doesn't reset them. Each count runs for a fixed
  15-minute window from its first attempt, by the database's clock, and starts
  again from one once the window has ended. This module is also the Oban
  worker that deletes counts whose window has ended.

  Attempts are counted per account, by its email address in lower case,
  whether or not an account has it, so the limit can't be used to find
  accounts. `sign_in_attempt/1` counts an attempt before the password is
  checked, so requests sent together can't all be checked against a count
  none of them has raised yet, and refuses once there have been more than ten
  in the window, right or wrong. `sign_in_succeeded/1` takes a successful
  attempt back off the count, so only failures add up: a person who signs in
  often is never limited, and signing in doesn't clear the failures someone
  else ran up.

  A sign-in waiting for its MFA code also gets five tries at it
  (`code_attempt/1`), taken before each code is checked: when the fifth fails
  the caller ends that session, so the password has to be entered again.

  There is no limit per client address: behind a load balancer every request
  comes from the balancer's address, so such a limit would lock everyone out
  together.
  """
  use Oban.Worker, queue: :background, max_attempts: 3

  import Ecto.Query

  alias Lightning.Repo

  @attempt_limit 10
  @code_limit 5

  @doc """
  Counts an attempt to sign in as the account with `email`, before its
  password is checked: `:ok` while it is within the limit, or
  `{:error, :rate_limited}` once there have been too many.
  """
  @spec sign_in_attempt(String.t()) :: :ok | {:error, :rate_limited}
  def sign_in_attempt(email) when is_binary(email) do
    if count(email_key(email)) <= @attempt_limit,
      do: :ok,
      else: {:error, :rate_limited}
  end

  @doc """
  Takes the attempt `sign_in_attempt/1` counted back off, once it has signed
  in.
  """
  @spec sign_in_succeeded(String.t()) :: :ok
  def sign_in_succeeded(email) when is_binary(email) do
    key = email_key(email)

    from(a in "sign_in_attempts",
      where: a.key == ^key and a.count > 0,
      update: [inc: [count: -1]]
    )
    |> Repo.update_all([])

    :ok
  end

  @doc """
  Takes one of the five tries the pending sign-in holding `session_token` has
  at its MFA code. Call it before checking the code: `:ok` while tries remain
  after this one, `:last` for the fifth, after which a wrong code must end
  that session, and `:spent` once there are none, when the code must not be
  checked at all.
  """
  @spec code_attempt(binary()) :: :ok | :last | :spent
  def code_attempt(session_token) when is_binary(session_token) do
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
