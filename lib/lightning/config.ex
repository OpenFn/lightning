defmodule Lightning.Config do
  @moduledoc """
  Centralised runtime configuration for Lightning.
  """
  defmodule API do
    @moduledoc false
    @behaviour Lightning.Config
    alias Lightning.Services.AdapterHelper

    @impl true
    def run_token_signer do
      pem =
        Application.get_env(:lightning, :workers, [])
        |> Keyword.get(:private_key)

      Joken.Signer.create("RS256", %{"pem" => pem})
    end

    @impl true
    def worker_token_signer do
      Joken.Signer.create("HS256", worker_secret())
    end

    @impl true
    def worker_secret do
      Application.get_env(:lightning, :workers, [])
      |> Keyword.get(:worker_secret)
    end

    @impl true
    def repo_connection_token_signer do
      Joken.Signer.create(
        "HS256",
        Application.fetch_env!(:lightning, :repo_connection_signing_secret)
      )
    end

    @impl true
    def grace_period do
      Application.get_env(:lightning, :run_grace_period_seconds)
    end

    @impl true
    def default_max_run_duration do
      Application.get_env(:lightning, :max_run_duration_seconds)
    end

    @impl true
    def purge_deleted_after_days do
      Application.get_env(:lightning, :purge_deleted_after_days)
    end

    @impl true
    def get_extension_mod(key) do
      AdapterHelper.adapter(key)
    end

    @impl true
    def check_flag?(flag) do
      Application.get_env(:lightning, flag)
    end

    @impl true
    def cors_origin do
      Application.get_env(:lightning, :cors_origin)
    end

    @impl true
    def instance_admin_email do
      Application.get_env(:lightning, :emails, [])
      |> Keyword.get(:admin_email)
    end

    @impl true
    def email_sender_name do
      Application.get_env(:lightning, :emails, [])
      |> Keyword.get(:sender_name)
    end
  end

  defmodule Utils do
    @moduledoc """
    Utility functions for working with the application environment.
    """

    @doc """
    Retrieve a value nested in the application environment.
    """
    @spec get_env([atom()], any()) :: any()
    def get_env(_keys, default \\ nil)

    def get_env([app, key, item], default) do
      Application.get_env(app, key, []) |> Keyword.get(item, default)
    end

    def get_env([app, key], default) do
      Application.get_env(app, key, default)
    end

    @spec ensure_boolean(binary()) :: boolean()
    def ensure_boolean(value) do
      case value do
        "true" ->
          true

        "yes" ->
          true

        "false" ->
          false

        "no" ->
          false

        _other ->
          raise ArgumentError,
                "expected true, false, yes or no, got: #{inspect(value)}"
      end
    end
  end

  @callback run_token_signer() :: Joken.Signer.t()
  @callback worker_token_signer() :: Joken.Signer.t()
  @callback repo_connection_token_signer() :: Joken.Signer.t()
  @callback worker_secret() :: binary() | nil
  @callback grace_period() :: integer()
  @callback default_max_run_duration() :: integer()
  @callback purge_deleted_after_days() :: integer()
  @callback get_extension_mod(key :: atom()) :: any()
  @callback check_flag?(atom()) :: boolean() | nil
  @callback cors_origin() :: list()
  @callback instance_admin_email() :: String.t()
  @callback email_sender_name() :: String.t()

  @doc """
  Returns the Token signer used to sign and verify run tokens.
  """
  def run_token_signer do
    impl().run_token_signer()
  end

  @doc """
  Returns the Token signer used to verify worker tokens.
  """
  def worker_token_signer do
    impl().worker_token_signer()
  end

  def worker_secret do
    impl().worker_secret()
  end

  @doc """
  The grace period is configurable and is used to wait for an additional
  amount of time after a given run was meant to be finished.

  The returned value is in seconds.
  """
  def grace_period do
    impl().grace_period()
  end

  @doc """
  Returns the default maximum run duration in seconds.
  """
  def default_max_run_duration do
    impl().default_max_run_duration()
  end

  def repo_connection_token_signer do
    impl().repo_connection_token_signer()
  end

  def purge_deleted_after_days do
    impl().purge_deleted_after_days()
  end

  def check_flag?(flag) do
    impl().check_flag?(flag)
  end

  def get_extension_mod(key) do
    impl().get_extension_mod(key)
  end

  def cors_origin do
    impl().cors_origin()
  end

  def instance_admin_email do
    impl().instance_admin_email()
  end

  def email_sender_name do
    impl().email_sender_name()
  end

  defp impl do
    Application.get_env(:lightning, __MODULE__, API)
  end
end
