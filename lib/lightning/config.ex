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
    def apollo(key \\ nil) do
      case key do
        nil ->
          Application.get_env(:lightning, :apollo, []) |> Map.new()

        key when is_atom(key) ->
          Application.get_env(:lightning, :apollo, []) |> Keyword.get(key)
      end
    end

    @impl true
    def oauth_provider(key) do
      Application.get_env(:lightning, :oauth_clients)
      |> Keyword.get(key)
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

    @impl true
    def usage_tracking do
      Application.get_env(:lightning, :usage_tracking)
    end

    @impl true
    def reset_password_token_validity_in_days do
      1
    end

    @impl true
    def usage_tracking_cron_opts do
      opts = usage_tracking()

      if opts[:enabled] do
        [
          {
            "30 1,9,17 * * *",
            Lightning.UsageTracking.DayWorker,
            args: %{"batch_size" => opts[:daily_batch_size]}
          },
          {
            "* * * * *",
            Lightning.UsageTracking.ResubmissionCandidatesWorker,
            args: %{"batch_size" => opts[:resubmission_batch_size]}
          }
        ]
      else
        []
      end
    end

    @impl true
    def kafka_triggers_enabled? do
      kafka_trigger_config() |> Keyword.get(:enabled, false)
    end

    @impl true
    def kafka_duplicate_tracking_retention_seconds do
      kafka_trigger_config()
      |> Keyword.get(:duplicate_tracking_retention_seconds)
    end

    @impl true
    def kafka_number_of_consumers do
      kafka_trigger_config() |> Keyword.get(:number_of_consumers)
    end

    @impl true
    def kafka_number_of_messages_per_second do
      kafka_trigger_config() |> Keyword.get(:number_of_messages_per_second)
    end

    @impl true
    def kafka_number_of_processors do
      kafka_trigger_config() |> Keyword.get(:number_of_processors)
    end

    defp kafka_trigger_config do
      Application.get_env(:lightning, :kafka_triggers, [])
    end
  end

  @callback apollo(key :: atom() | nil) :: map()
  @callback check_flag?(atom()) :: boolean() | nil
  @callback cors_origin() :: list()
  @callback default_max_run_duration() :: integer()
  @callback email_sender_name() :: String.t()
  @callback get_extension_mod(key :: atom()) :: any()
  @callback grace_period() :: integer()
  @callback instance_admin_email() :: String.t()
  @callback kafka_duplicate_tracking_retention_seconds() :: integer()
  @callback kafka_number_of_consumers() :: integer()
  @callback kafka_number_of_messages_per_second() :: float()
  @callback kafka_number_of_processors() :: integer()
  @callback kafka_triggers_enabled?() :: boolean()
  @callback oauth_provider(key :: atom()) :: keyword() | nil
  @callback purge_deleted_after_days() :: integer()
  @callback repo_connection_token_signer() :: Joken.Signer.t()
  @callback reset_password_token_validity_in_days() :: integer()
  @callback run_token_signer() :: Joken.Signer.t()
  @callback usage_tracking() :: Keyword.t()
  @callback usage_tracking_cron_opts() :: [Oban.Plugins.Cron.cron_input()]
  @callback worker_secret() :: binary() | nil
  @callback worker_token_signer() :: Joken.Signer.t()

  @doc """
  Returns the Apollo server configuration.
  """
  def apollo(key \\ nil) do
    impl().apollo(key)
  end

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

  def oauth_provider(key) do
    impl().oauth_provider(key)
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

  def usage_tracking do
    impl().usage_tracking()
  end

  def reset_password_token_validity_in_days do
    impl().reset_password_token_validity_in_days()
  end

  def usage_tracking_cron_opts do
    impl().usage_tracking_cron_opts()
  end

  def kafka_triggers_enabled? do
    impl().kafka_triggers_enabled?()
  end

  def kafka_duplicate_tracking_retention_seconds do
    impl().kafka_duplicate_tracking_retention_seconds()
  end

  def kafka_number_of_consumers do
    impl().kafka_number_of_consumers()
  end

  def kafka_number_of_messages_per_second do
    impl().kafka_number_of_messages_per_second()
  end

  def kafka_number_of_processors do
    impl().kafka_number_of_processors()
  end

  defp impl do
    Application.get_env(:lightning, __MODULE__, API)
  end
end
