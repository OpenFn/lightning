defmodule Lightning.Tokens do
  defmodule PersonalAccessToken do
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

  @spec verify(String.t()) :: {:ok, map()} | {:error, any()}
  def verify(token) do
    Joken.peek_claims(token)
    |> case do
      # TODO: Look up user tokens via the JTI and ensure the JTI is indexed
      {:ok, %{"sub" => "user:" <> _}} ->
        PersonalAccessToken.verify_and_validate(
          token,
          Lightning.Config.token_signer()
        )

      {:ok, %{"sub" => "run:" <> _}} ->
        Lightning.Workers.verify_run_token(token, %{})

      {:ok, _} ->
        {:error, "Unsupported token type"}

      {:error, err} ->
        {:error, err}
    end
  end

  def get_subject(%{"sub" => "user:" <> user_id}) do
    Lightning.Accounts.get_user(user_id)
  end

  def get_subject(%{"sub" => "run:" <> run_id}) do
    Lightning.Runs.get(run_id)
  end
end
