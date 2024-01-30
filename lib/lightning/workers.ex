defmodule Lightning.Workers do
  @moduledoc """
  Lightning uses external worker processes to execute workflow jobs.

  This module deals with the security tokens and the formatting used on
  the communication with the workers.
  """
  defmodule Token do
    @moduledoc """
    JWT token configuration to authenticate workers.
    """
    use Joken.Config

    @impl true
    def token_config do
      %{}
      |> add_claim(
        "nbf",
        fn -> Lightning.current_time() |> DateTime.to_unix() end,
        fn nbf, _claims, %{current_time: current_time} ->
          current_time |> DateTime.to_unix() >= nbf
        end
      )
    end
  end

  defmodule RunToken do
    @moduledoc """
    JWT token configuration to verify if workers work is legit.
    """
    use Joken.Config

    @impl true
    def token_config do
      %{}
      |> add_claim("iss", fn -> "Lightning" end, &(&1 == "Lightning"))
      |> add_claim("id", nil, fn id, _claims, context ->
        is_binary(id) and id == Map.get(context, :id)
      end)
      |> add_claim(
        "nbf",
        fn -> Lightning.current_time() |> DateTime.to_unix() end,
        fn nbf, _claims, %{current_time: current_time} ->
          current_time |> DateTime.to_unix() >= nbf
        end
      )
      |> add_claim(
        "exp",
        fn ->
          Lightning.current_time()
          |> DateTime.add(Lightning.Config.grace_period())
          |> DateTime.to_unix()
        end,
        fn exp, _claims, %{current_time: current_time} ->
          current_time |> DateTime.to_unix() < exp
        end
      )
    end
  end

  def generate_run_token(run) do
    {:ok, token, _claims} =
      RunToken.generate_and_sign(
        %{"id" => run.id},
        Lightning.Config.run_token_signer()
      )

    token
  end

  @doc """
  Verifies and validates a run token.

  It requires a context map with the following keys:

  - `:id` - the run id that the token was issued with.

  Optionally takes a context map that will be passed to the validation:

  - `:current_time` - the current time as a `DateTime` struct.
  """
  @spec verify_run_token(binary(), map()) ::
          {:ok, Joken.claims()} | {:error, any()}
  def verify_run_token(token, context) when is_binary(token) do
    context = Enum.into(context, %{current_time: Lightning.current_time()})

    RunToken.verify_and_validate(
      token,
      Lightning.Config.run_token_signer(),
      context
    )
    |> case do
      {:error, error} ->
        {:error, transform_error(error)}

      {:ok, claims} ->
        {:ok, claims}
    end
  end

  @doc """
  Verifies and validates a worker token.

  Optionally takes a context map that will be passed to the validation:

  - `:current_time` - the current time as a `DateTime` struct.
  """
  @spec verify_worker_token(binary(), map()) ::
          {:ok, Joken.claims()} | {:error, any()}
  def verify_worker_token(token, context \\ %{}) when is_binary(token) do
    context = Enum.into(context, %{current_time: Lightning.current_time()})

    Token.verify_and_validate(
      token,
      Lightning.Config.worker_token_signer(),
      context
    )
  end

  defp transform_error(error) when is_atom(error) do
    error
  end

  defp transform_error(error) when is_list(error) do
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
