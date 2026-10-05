defmodule Lightning.TokenMatrixTest do
  @moduledoc """
  Every token Lightning issues, fed to every door that accepts a token.

  Personal access, credential transfer and run tokens are all signed with the
  same RSA key, so a signature check cannot tell them apart — only their claims
  can. Worker tokens are the exception, signed with the shared worker secret.
  That leaves the claim configs as the entire boundary between "this token opens
  the API" and "this token opens a run", which is thin enough to deserve being
  written out in full rather than sampled.

  There is one test per verifier, and each runs *every* token type through it,
  so a token type added to `@token_types` is exercised against every door
  without anyone remembering to go and add it. What these tests cannot do is
  notice a new verifier — a function added elsewhere that takes a token needs a
  test writing here, same as any other new function.

  Individual crossings are asserted in more depth elsewhere — the run token in
  `Lightning.WorkersTest`, the worker token in `Lightning.Workers.WorkerTokenTest`
  and the API bearer path in `Lightning.TokensTest`. This file is about covering
  the grid, not depth in any one square.
  """
  use Lightning.DataCase, async: true

  import Lightning.Factories
  import Lightning.TokenHelpers, only: [ws_worker_token: 1]

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Credentials
  alias Lightning.Tokens
  alias Lightning.Workers

  # Every kind of token Lightning issues. `setup` mints each one the way
  # production mints it, so a token type honoured by nothing below would mean
  # the mint itself is broken rather than the doors being tight.
  @token_types [:personal_access, :credential_transfer, :run, :worker]

  setup do
    Mox.stub_with(Lightning.MockConfig, Lightning.Config.API)
    Mox.stub_with(LightningMock, Lightning.Stub)
    Lightning.Stub.freeze_time(~U[2024-01-01 00:00:00Z])

    owner = insert(:user)
    receiver = insert(:user)

    credential =
      insert(:credential, user_id: owner.id, transfer_status: :pending)

    {:ok, transfer_token, _claims} =
      Tokens.CredentialTransferToken.generate_and_sign(
        %{
          "sub" => "credential_transfer:#{owner.id}",
          "credential_id" => credential.id,
          "receiver_id" => receiver.id
        },
        Lightning.Config.token_signer()
      )

    tokens = %{
      personal_access: Accounts.generate_api_token(owner),
      credential_transfer: transfer_token,
      run: Workers.generate_run_token(%Lightning.Run{id: Ecto.UUID.generate()}),
      worker: ws_worker_token(%{})
    }

    %{tokens: tokens, owner: owner}
  end

  # Bearer auth for /api and /collections. Workers read collections with the run
  # token they were issued, so this deliberately takes run tokens too and hands
  # them to the run verifier.
  test "Tokens.verify/1 honours personal access and run tokens", context do
    assert_honours(context, [:personal_access, :run], fn token ->
      Tokens.verify(token)
    end)
  end

  test "Workers.verify_run_token/2 honours run tokens alone", context do
    assert_honours(context, [:run], fn token ->
      Workers.verify_run_token(token, %{})
    end)
  end

  test "Workers.verify_worker_token/2 honours worker tokens alone", context do
    assert_honours(context, [:worker], fn token ->
      Workers.verify_worker_token(token, %{})
    end)
  end

  test "Credentials.confirm_transfer/2 honours transfer tokens alone",
       context do
    assert_honours(context, [:credential_transfer], fn token ->
      Credentials.confirm_transfer(token, context.owner)
    end)
  end

  # This one checks no signature at all — it looks the token string up in
  # user_tokens. Every other token type is turned away only because it was never
  # stored there.
  test "Accounts.get_user_by_api_token/1 honours personal access tokens alone",
       context do
    assert_honours(context, [:personal_access], fn token ->
      Accounts.get_user_by_api_token(token)
    end)
  end

  defp assert_honours(context, honoured, verify) do
    assert honoured -- @token_types == [],
           "#{inspect(honoured -- @token_types)} is not a token type minted here"

    for token_type <- @token_types do
      result = context.tokens |> Map.fetch!(token_type) |> verify.() |> tuple()

      if token_type in honoured,
        do: assert_honoured(token_type, result),
        else: assert_refused(token_type, honoured, result)
    end
  end

  defp assert_honoured(token_type, result) do
    case result do
      {:ok, _payload} ->
        :ok

      other ->
        flunk(
          "A #{token_type} token is meant to be honoured here, but it was " <>
            "refused with #{inspect(other)}."
        )
    end
  end

  defp assert_refused(token_type, honoured, result) do
    case result do
      {:ok, payload} ->
        flunk(
          "A #{token_type} token was honoured here, where only " <>
            "#{Enum.join(honoured, " and ")} tokens may be. It returned " <>
            "#{inspect(payload)}."
        )

      {:error, reason} ->
        assert refused_by_token_check?(reason),
               "A #{token_type} token was refused here, but for " <>
                 "#{inspect(reason)}. That is a check behind the token rather " <>
                 "than the token check itself, so the token verified and only " <>
                 "the record it named refused it."
    end
  end

  # `get_user_by_api_token/1` answers with a struct or nil rather than a tagged
  # tuple, so it needs bringing into the shape the others use.
  defp tuple(nil), do: {:error, :no_such_token}
  defp tuple(%User{} = user), do: {:ok, user}
  defp tuple(result), do: result

  # A foreign token has to be turned away by the token check itself. Reasons like
  # `:not_owner` or `:not_pending` from `confirm_transfer/2` would mean the
  # signature and claims passed and only the record behind them refused, which
  # would make the assertion pass for the wrong reason.
  defp refused_by_token_check?({:missing_claims, _missing}), do: true

  defp refused_by_token_check?(reason) when is_list(reason),
    do: Keyword.has_key?(reason, :claim)

  defp refused_by_token_check?(reason),
    do:
      reason in [
        :signature_error,
        :token_malformed,
        :token_error,
        :token_revoked,
        :no_such_token,
        "Unsupported token type"
      ]
end
