defmodule Lightning.Config do
  @moduledoc """
  Centralised runtime configuration for Lightning.
  """
  defmodule API do
    @moduledoc false

    @callback run_token_signer() :: Joken.Signer.t()
    @callback worker_token_signer() :: Joken.Signer.t()
    @callback worker_secret() :: binary() | nil
    @callback grace_period() :: integer()

    def run_token_signer do
      pem =
        Application.get_env(:lightning, :workers, [])
        |> Keyword.get(:private_key)

      Joken.Signer.create("RS256", %{"pem" => pem})
    end

    def worker_token_signer do
      Joken.Signer.create("HS256", worker_secret())
    end

    def worker_secret do
      Application.get_env(:lightning, :workers, [])
      |> Keyword.get(:worker_secret)
    end

    @doc """
    The grace period is 20% of the max run duration and may be used to wait for
    an additional amount of time after a run was meant to be finished.
    """
    def grace_period do
      (Application.get_env(:lightning, :max_run_duration_seconds) * 0.2)
      |> trunc()
    end
  end

  # credo:disable-for-next-line
  @behaviour API

  @doc """
  Returns the Token signer used to sign and verify run tokens.
  """
  @impl true
  def run_token_signer do
    impl().run_token_signer()
  end

  @doc """
  Returns the Token signer used to verify worker tokens.
  """
  @impl true
  def worker_token_signer do
    impl().worker_token_signer()
  end

  @impl true
  def worker_secret do
    impl().worker_secret()
  end

  @impl true
  def grace_period do
    impl().grace_period()
  end

  defp impl do
    Application.get_env(:lightning, __MODULE__, API)
  end
end
