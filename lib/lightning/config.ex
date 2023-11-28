defmodule Lightning.Config do
  @moduledoc """
  Centralised runtime configuration for Lightning.
  """
  defmodule API do
    @moduledoc false

    @callback attempt_token_signer() :: Joken.Signer.t()
    @callback worker_token_signer() :: Joken.Signer.t()
    @callback worker_secret() :: binary() | nil
    @callback attempts_adaptor() :: module()
    @callback grace_period() :: integer()

    def attempt_token_signer() do
      pem =
        Application.get_env(:lightning, :workers, [])
        |> Keyword.get(:private_key)

      Joken.Signer.create("RS256", %{"pem" => pem})
    end

    def worker_token_signer() do
      Joken.Signer.create("HS256", worker_secret())
    end

    def attempts_adaptor() do
      Application.get_env(
        :lightning,
        :attempts_module,
        Lightning.Attempts.Queue
      )
    end

    def worker_secret() do
      Application.get_env(:lightning, :workers, [])
      |> Keyword.get(:worker_secret)
    end

    @doc """
    The grace period is 20% of the max attempt duration and may be used to wait
    for an additional amount of time after an attempt was meant to be finished.
    """
    def grace_period() do
      (Application.get_env(:lightning, :max_run_duration) * 0.2)
      |> trunc()
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

  @impl true
  def worker_secret() do
    impl().worker_secret()
  end

  @impl true
  def grace_period() do
    impl().grace_period()
  end

  defp impl() do
    Application.get_env(:lightning, __MODULE__, API)
  end
end
