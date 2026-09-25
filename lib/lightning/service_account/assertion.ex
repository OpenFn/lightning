defmodule Lightning.ServiceAccount.Assertion do
  @moduledoc """
  The signed JWT a service account authenticates with at the token endpoint,
  as RFC 7523 §2.2 defines it.

  An assertion is accepted once. Its `jti` is recorded in
  `service_account_assertions`, whose primary key refuses a repeat on any node
  of the cluster, and this module's Oban job deletes the row a while after the
  assertion has expired and could not be accepted anyway.
  """

  use Oban.Worker, queue: :background, max_attempts: 3

  import Ecto.Query

  alias Lightning.Repo
  alias Lightning.ServiceAccount

  @max_lifetime 60
  @clock_skew 5
  # Kept past expiry so a node whose clock lags the pruner's still refuses a
  # replay.
  @prune_after 300

  @type error ::
          :malformed
          | :unknown_service_account
          | :bad_signature
          | :wrong_subject
          | :wrong_audience
          | :missing_claims
          | :expired
          | :lives_too_long
          | :issued_in_future
          | :replayed

  @doc """
  Checks `assertion` was signed by the registered service account for
  `audience`, the token endpoint's URL, and records its `jti`.
  """
  @spec verify(String.t(), String.t()) ::
          {:ok, ServiceAccount.t()} | {:error, error()}
  def verify(assertion, audience) do
    with {:ok, account} <- find_service_account(assertion),
         {:ok, claims} <- verify_signature(account, assertion),
         :ok <- check_claims(claims, account, audience) do
      record(claims, account)
    end
  end

  defp find_service_account(assertion) do
    %JOSE.JWT{fields: %{"iss" => iss}} = JOSE.JWT.peek_payload(assertion)

    case Lightning.Config.service_account() do
      %ServiceAccount{id: ^iss} = account -> {:ok, account}
      _other -> {:error, :unknown_service_account}
    end
  rescue
    _ -> {:error, :malformed}
  end

  defp verify_signature(account, assertion) do
    case JOSE.JWT.verify_strict(account.public_key, ["RS256"], assertion) do
      {true, %JOSE.JWT{fields: claims}, _jws} -> {:ok, claims}
      _other -> {:error, :bad_signature}
    end
  rescue
    _ -> {:error, :bad_signature}
  end

  defp check_claims(claims, account, audience) do
    exp = claims["exp"]
    iat = claims["iat"]

    cond do
      claims["sub"] != account.id -> {:error, :wrong_subject}
      claims["aud"] not in [audience, [audience]] -> {:error, :wrong_audience}
      not is_integer(exp) or not is_integer(iat) -> {:error, :missing_claims}
      not valid_jti?(claims["jti"]) -> {:error, :missing_claims}
      true -> check_times(exp, iat, System.system_time(:second))
    end
  end

  defp check_times(exp, iat, now) do
    cond do
      exp <= now -> {:error, :expired}
      exp - iat > @max_lifetime -> {:error, :lives_too_long}
      iat > now + @clock_skew -> {:error, :issued_in_future}
      true -> :ok
    end
  end

  defp valid_jti?(jti) do
    is_binary(jti) and jti != "" and byte_size(jti) <= 255 and
      not String.contains?(jti, <<0>>)
  end

  defp record(%{"jti" => jti, "exp" => exp}, account) do
    {count, _} =
      Repo.insert_all(
        "service_account_assertions",
        [
          %{
            service_account_id: account.id,
            jti: jti,
            expires_at: DateTime.from_unix!(exp)
          }
        ],
        on_conflict: :nothing
      )

    if count == 1, do: {:ok, account}, else: {:error, :replayed}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Repo.delete_all(
      from(a in "service_account_assertions",
        where: a.expires_at < ^DateTime.add(DateTime.utc_now(), -@prune_after)
      )
    )

    :ok
  end
end
