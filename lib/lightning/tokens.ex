defmodule Lightning.Tokens do
  @moduledoc """
  Token generation, verification and validation.
  """

  defmodule PersonalAccessToken do
    @moduledoc false
    use Joken.Config

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
          Lightning.current_time() >= iat |> DateTime.from_unix()
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
        fn exp, _claims, _context ->
          DateTime.to_unix(Lightning.current_time()) < exp
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
    Joken.peek_claims(token)
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
