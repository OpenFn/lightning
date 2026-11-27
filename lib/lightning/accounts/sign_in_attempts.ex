defmodule Lightning.Accounts.SignInAttempts do
  @moduledoc """
  Limits failed attempts to prove who someone is: a password or MFA code sent
  to sign in, or to finish an MFA sign-in.

  Only `POST /api/session` counts and checks them so far. The log-in and
  two-factor pages don't, so the limits here don't yet hold for an account as a
  whole.

  Failures are counted per account, by its email address in lower case,
  whether or not an account has it, so the limit can't be used to find
  accounts. After ten failures in 15 minutes, `check/1` refuses further
  attempts on that address, right or wrong, until the window ends. Only
  failures count, so a person who signs in often is never limited.

  A sign-in waiting for its MFA code also gets five tries at it
  (`code_attempt/1`), taken before each code is checked: when the fifth fails
  the caller ends that session, so the password has to be entered again.

  There is no limit per client address: behind a load balancer every request
  comes from the balancer's address, so such a limit would lock everyone out
  together.

  Like the confirmation mail limit, an unavailable limiter lets the attempt
  through rather than locking everyone out.
  """
  require Logger

  @failure_limit 10
  @code_limit 5
  @window :timer.minutes(15)

  @doc """
  `:ok` while the account with `email` may try again, or
  `{:error, :rate_limited}` once it has failed too often.
  """
  @spec check(String.t()) :: :ok | {:error, :rate_limited}
  def check(email) when is_binary(email) do
    case Hammer.inspect_bucket(bucket(email), @window, @failure_limit) do
      {:ok, {_count, remaining, _ms_to_next, _created, _updated}}
      when remaining <= 0 ->
        {:error, :rate_limited}

      {:ok, _bucket} ->
        :ok

      {:error, reason} ->
        unavailable(reason)
        :ok
    end
  end

  @doc "Counts a failed attempt against the account with `email`."
  @spec failed(String.t()) :: :ok
  def failed(email) when is_binary(email) do
    with {:error, reason} <-
           Hammer.check_rate(bucket(email), @window, @failure_limit) do
      unavailable(reason)
    end

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
    key = "pending_mfa_attempts::" <> digest(session_token)

    case Hammer.check_rate(key, @window, @code_limit) do
      {:allow, count} when count < @code_limit ->
        :ok

      {:allow, _count} ->
        :last

      {:deny, _limit} ->
        :spent

      {:error, reason} ->
        unavailable(reason)
        :ok
    end
  end

  # The address is whatever the request sent, of any length, and the limiter
  # keeps every key in memory, so the key is its hash.
  defp bucket(email), do: "sign_in_failures::" <> digest(String.downcase(email))

  defp digest(value), do: Base.url_encode64(:crypto.hash(:sha256, value))

  defp unavailable(reason) do
    Logger.warning(
      "Sign-in attempt limiter unavailable, allowing the attempt: " <>
        inspect(reason)
    )
  end
end
