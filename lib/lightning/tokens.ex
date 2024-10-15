defmodule Lightning.Tokens do
  @spec verify(String.t()) :: {:ok, map()} | {:error, any()}
  def verify(token) do
    Joken.peek_claims(token)
    |> case do
      # TODO: Look up user tokens via the JTI and ensure the JTI is indexed
      # {:ok, %{"sub" => "user:" <> _}} ->
      #   Lightning.Accounts.verify_token_query(token, "api")

      {:ok, %{"sub" => "run:" <> _}} ->
        Lightning.Workers.verify_run_token(token, %{})

      {:ok, _} ->
        {:error, "Unsupported token type"}

      {:error, err} ->
        {:error, err}
    end
  end
end
