defmodule Lightning.Tokens do
  @moduledoc """
  Token generation, verification and validation.
  """

  require Logger

  defmodule PersonalAccessToken do
    @moduledoc false
    use Joken.Config

    # A token is minted on whichever replica served the request and verified on
    # whichever serves the next one, and their clocks agree only as closely as
    # NTP keeps them. Without a tolerance, a user who creates an API token and
    # immediately calls the API gets a 401 for the length of the skew.
    @clock_skew_seconds 60

    @impl true
    def token_config do
      %{}
      |> add_claim("jti", &Joken.generate_jti/0)
      |> add_claim("iss", fn -> "Lightning" end, &(&1 == "Lightning"))
      |> add_claim("sub", nil, fn sub, _claims, _context ->
        String.starts_with?(sub, "user:")
      end)
      |> add_claim(
        "iat",
        fn -> Lightning.current_time() |> DateTime.to_unix() end,
        fn iat, _claims, _context ->
          is_number(iat) and
            DateTime.to_unix(Lightning.current_time()) >=
              iat - @clock_skew_seconds
        end
      )
    end
  end

  defmodule CredentialTransferToken do
    @moduledoc """
    A short-lived, ownership-bound token for confirming a credential transfer.

    The owner, credential and receiver are baked into the signed payload, so
    they cannot be swapped by editing the confirmation URL. The token is
    stateless: revocation and single-use are enforced by the credential's
    `transfer_status` (a cancelled or completed transfer fails the pending and
    ownership guards in `Lightning.Credentials.confirm_transfer/2`), not by the
    token itself.

    The `sub` uses a `credential_transfer:` prefix rather than `user:` so these
    tokens are rejected by `Lightning.Tokens.verify/1` and cannot double as API
    bearer tokens.
    """
    use Joken.Config

    @impl true
    def token_config do
      %{}
      |> add_claim("iss", fn -> "Lightning" end, &(&1 == "Lightning"))
      |> add_claim("sub", nil, fn sub, _claims, _context ->
        is_binary(sub) and String.starts_with?(sub, "credential_transfer:")
      end)
      |> add_claim(
        "iat",
        fn -> Lightning.current_time() |> DateTime.to_unix() end,
        fn iat, _claims, _context ->
          DateTime.to_unix(Lightning.current_time()) >= iat
        end
      )
      |> add_claim(
        "exp",
        fn ->
          Lightning.current_time()
          |> DateTime.add(
            Lightning.Config.credential_transfer_token_validity_in_days(),
            :day
          )
          |> DateTime.to_unix()
        end,
        # See the note on `RunToken`'s `exp`: without `is_number/1` a
        # non-numeric `exp` sorts above every timestamp and never expires.
        fn exp, _claims, _context ->
          is_number(exp) and DateTime.to_unix(Lightning.current_time()) < exp
        end
      )
    end
  end

  @doc """
  Verify a token and return the claims if successful.

  This serves as a central point to verify and validate different types
  of tokens. For user (personal access) tokens it also rejects unusable
  credentials: a deleted token row yields `{:error, :token_revoked}` and a
  blocked account yields `{:error, :user_blocked}`.
  """
  @spec verify(String.t()) :: {:ok, map()} | {:error, any()}
  def verify(token) do
    safe_peek(token)
    |> case do
      {:ok, %{"sub" => "user:" <> user_id}} ->
        with {:ok, claims} <-
               PersonalAccessToken.verify_and_validate(
                 token,
                 Lightning.Config.token_signer()
               ),
             true <- persisted_api_token?(token),
             :active <- account_status(user_id) do
          {:ok, claims}
        else
          false -> {:error, :token_revoked}
          :missing -> {:error, :token_revoked}
          :blocked -> {:error, :user_blocked}
          error -> error
        end

      {:ok, %{"sub" => "run:" <> _}} ->
        Lightning.Workers.verify_run_token(token, %{})

      {:ok, _} ->
        {:error, "Unsupported token type"}

      {:error, err} ->
        {:error, err}
    end
  end

  @doc """
  Asserts every claim in `required` is present on the token.

  Joken iterates the token's claims and looks each up in the config, so a
  validator for an absent claim never runs — a claim config cannot make a claim
  mandatory on its own. This runs before verification and only ever rejects, so
  peeking at unverified claims is safe.
  """
  @spec require_claims(String.t(), [String.t()]) ::
          :ok | {:error, {:missing_claims, [String.t()]} | :token_malformed}
  def require_claims(token, required) do
    case safe_peek(token) do
      {:ok, claims} when is_map(claims) ->
        case Enum.reject(required, &Map.has_key?(claims, &1)) do
          [] -> :ok
          missing -> {:error, {:missing_claims, Enum.sort(missing)}}
        end

      _ ->
        {:error, :token_malformed}
    end
  end

  # Joken.peek_claims/1 is not total, and every caller here hands it
  # attacker-controlled input: a three-segment token whose payload does not
  # base64-decode to JSON raises Jason.DecodeError, and one that decodes to a
  # JSON array or string returns {:ok, [1, 2, 3]} or {:ok, "hi"}, which then
  # crashes any Map operation on it.
  #
  # The rescue stays broad rather than naming the known raisers: a Joken version
  # that raises something outside the list would put the 500-on-unauthenticated-
  # input back. The log line is what stops a genuine fault hiding behind a quiet
  # 401. Warning, not error — garbage tokens are routine, and `error` would page
  # someone every time a scanner reaches the API.
  defp safe_peek(token) do
    Joken.peek_claims(token)
  rescue
    exception ->
      Logger.warning(fn ->
        "Token could not be read: #{Exception.format(:error, exception)}"
      end)

      {:error, :token_malformed}
  end

  @doc """
  Get the subject of a token.
  Currently support RunTokens and PersonalAccessTokens,
  which return `Lightning.Run`s and `Lightning.Accounts.User`s respectively.

  This is pure resolution and performs no authorization, so callers must go
  through `verify/1` first.
  """
  def get_subject(%{"sub" => "user:" <> user_id}) do
    Lightning.Accounts.get_user(user_id)
  end

  def get_subject(%{"sub" => "run:" <> run_id}) do
    Lightning.Runs.get(run_id)
  end

  # Mirror /api: a revoked (hard-deleted) PAT has no user_tokens row, so this
  # existence check stops it authorising here too.
  defp persisted_api_token?(token) do
    token
    |> Lightning.Accounts.UserToken.verify_token_query("api")
    |> Lightning.Repo.exists?()
  end

  # A missing user reports :missing (verify/1 maps it to :token_revoked, not
  # :blocked): deleting a user cascades its token rows away, so the credential
  # is genuinely gone rather than merely blocked.
  defp account_status(user_id) do
    case Lightning.Accounts.get_user(user_id) do
      nil ->
        :missing

      user ->
        if Lightning.Accounts.login_blocked?(user), do: :blocked, else: :active
    end
  end
end
