defmodule Lightning.Config do
  @moduledoc """
  Centralised runtime configuration for Lightning.
  """

  defmodule API do
    @moduledoc false

    @callback attempt_token_signer() :: Joken.Signer.t()
    @callback worker_token_signer() :: Joken.Signer.t()
    @callback attempts_adaptor() :: module()

    def attempt_token_signer() do
      pem =
        Application.get_env(:lightning, :workers, [])
        |> Keyword.get(:attempts_pem)

      Joken.Signer.create("RS256", %{"pem" => pem})
    end

    def worker_token_signer() do
      Joken.Signer.create(
        "HS256",
        Application.get_env(:lightning, :workers, [])
        |> Keyword.get(:worker_secret)
      )
    end

    def attempts_adaptor() do
      Application.get_env(
        :lightning,
        :attempts_module,
        Lightning.Attempts.Queue
      )
    end
  end

  @behaviour API

  @doc """
  Returns the Token signer used to sign and verify attempt tokens.
  """
  @impl true
  def attempt_token_signer() do
    impl().attempt_token_signer()
  end

  @doc """
  Returns the Token signer used to verify worker tokens.
  """
  @impl true
  def worker_token_signer() do
    impl().worker_token_signer()
  end

  @doc """
  Returns the module used to manage attempts.
  """
  @impl true
  def attempts_adaptor() do
    impl().attempts_adaptor()
  end

  defp impl() do
    Application.get_env(:lightning, __MODULE__, API)
  end
end
