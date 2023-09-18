defmodule Lightning.Workers do
  defmodule Token do
    use Joken.Config

    @impl true
    def token_config do
      %{}
      |> add_claim("iss", fn -> "Lightning" end, &(&1 == "Lightning"))
      |> add_claim(
        "nbf",
        fn -> Lightning.current_time() |> DateTime.to_unix() end,
        &(Lightning.current_time() |> DateTime.to_unix() > &1)
      )
    end
  end

  defmodule AttemptToken do
    use Joken.Config

    @impl true
    def token_config do
      %{}
      |> add_claim("iss", fn -> "Lightning" end, &(&1 == "Lightning"))
      |> add_claim(
        "nbf",
        fn -> Lightning.current_time() |> DateTime.to_unix() end,
        &(Lightning.current_time() |> DateTime.to_unix() > &1)
      )
    end
  end

  def generate_attempt_token(attempt) do
    {:ok, token, _claims} =
      AttemptToken.generate_and_sign(
        %{"id" => attempt.id},
        Lightning.Config.attempt_token_signer()
      )

    token
  end

  def verify_attempt_token(token) when is_binary(token) do
    AttemptToken.verify_and_validate(
      token,
      Lightning.Config.attempt_token_signer()
    )
    |> case do
      {:error, error} ->
        {:error, transform_error(error)}

      {:ok, claims} ->
        {:ok, claims}
    end
  end

  def verify_worker_token(token) when is_binary(token) do
    Token.verify_and_validate(
      token,
      Lightning.Config.worker_token_signer()
    )
  end

  defp transform_error(error) do
    error
    |> Keyword.get(:claim)
    |> case do
      "nbf" ->
        :nbf_not_reached

      _ ->
        error
    end
  end
end
