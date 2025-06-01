defmodule Lightning.Config do
  @moduledoc """
  Centralised runtime configuration for Lightning.
  """
  defmodule API do
    @moduledoc false
    @behaviour Lightning.Config
    alias Lightning.Services.AdapterHelper

    @impl true
    def adaptor_registry do
      Application.get_env(:lightning, Lightning.AdaptorRegistry, [])
    end

    @impl true
    def token_signer do
      :persistent_term.get({__MODULE__, "token_signer"}, nil)
      |> case do
        nil ->
          pem =
            Application.get_env(:lightning, :workers, [])
            |> Keyword.get(:private_key)

          signer = Joken.Signer.create("RS256", %{"pem" => pem})

          :persistent_term.put({__MODULE__, "token_signer"}, signer)

          signer

        signer ->
          signer
      end
    end

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
    def activity_cleanup_chunk_size do
      Application.get_env(:lightning, :activity_cleanup_chunk_size)
    end

    @impl true
    def default_ecto_database_timeout do
      Application.get_env(:lightning, Lightning.Repo) |> Keyword.get(:timeout)
    end

    @impl true
    def get_extension_mod(key) do
      AdapterHelper.adapter(key)
    end

    @impl true
    def google(key) do
      Application.get_env(:lightning, Lightning.Google, [])
      |> Keyword.get(key)
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
    def reset_password_token_validity_in_days do
      1
    end

    @impl true
    def storage do
      Application.get_env(:lightning, Lightning.Storage, [])
    end

    @impl true
    def storage(key) do
      storage()
      |> Keyword.get(key)
    end

    @impl true
    def usage_tracking do
      Application.get_env(:lightning, :usage_tracking)
    end

    @impl true
    def usage_tracking_cleartext_uuids_enabled? do
      usage_tracking() |> Keyword.get(:cleartext_uuids_enabled)
    end

    @impl true
    def usage_tracking_enabled? do
      usage_tracking() |> Keyword.get(:enabled)
    end

    @impl true
    def usage_tracking_host do
      usage_tracking() |> Keyword.get(:host)
    end

    @impl true
    def usage_tracking_run_chunk_size do
      usage_tracking() |> Keyword.get(:run_chunk_size)
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
    def kafka_alternate_storage_enabled? do
      kafka_trigger_config() |> Keyword.get(:alternate_storage_enabled)
    end

    @impl true
    def kafka_alternate_storage_file_path do
      kafka_trigger_config() |> Keyword.get(:alternate_storage_file_path)
    end

    @impl true
    def kafka_duplicate_tracking_retention_seconds do
      kafka_trigger_config()
      |> Keyword.get(:duplicate_tracking_retention_seconds)
    end

    @impl true
    def kafka_notification_embargo_seconds do
      kafka_trigger_config() |> Keyword.get(:notification_embargo_seconds)
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

    @impl true
    def promex_metrics_endpoint_authorization_required? do
      promex_config() |> Keyword.get(:metrics_endpoint_authorization_required)
    end

    @impl true
    def promex_metrics_endpoint_scheme do
      promex_config() |> Keyword.get(:metrics_endpoint_scheme)
    end

    @impl true
    def promex_metrics_endpoint_token do
      promex_config() |> Keyword.get(:metrics_endpoint_token)
    end

    defp promex_config do
      Application.get_env(:lightning, Lightning.PromEx, [])
    end

    @impl true
    def ui_metrics_tracking_enabled? do
      Keyword.get(ui_metrics_tracking_config(), :enabled)
    end

    defp ui_metrics_tracking_config do
      Application.get_env(:lightning, :ui_metrics_tracking, [])
    end

    @impl true
    def credential_transfer_token_validity_in_days do
      2
    end

    @impl true
    def book_demo_banner_enabled? do
      Keyword.get(book_demo_banner_config(), :enabled, false)
    end

    @impl true
    def book_demo_calendly_url do
      Keyword.get(book_demo_banner_config(), :calendly_url)
    end

    @impl true
    def book_demo_openfn_workflow_url do
      Keyword.get(book_demo_banner_config(), :openfn_workflow_url)
    end

    defp book_demo_banner_config do
      Application.get_env(:lightning, :book_demo_banner, [])
    end

    @impl true
    def gdpr_banner do
      Application.get_env(:lightning, :gdpr_banner)
    end

    @impl true
    def gdpr_preferences do
      Application.get_env(:lightning, :gdpr_preferences)
    end

    @impl true
    def external_metrics_module do
      Application.get_env(:lightning, Lightning.Extensions, [])
      |> Keyword.get(:external_metrics)
    end

    @impl true
    def ai_assistant_modes do
      %{
        job: LightningWeb.Live.AiAssistant.Modes.JobCode,
        workflow: LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate
      }
    end

    @impl true
    def per_workflow_claim_limit do
      Application.get_env(:lightning, :per_workflow_claim_limit, 50)
    end

    @impl true
    def metrics_run_performance_age_seconds do
      metrics_config() |> Keyword.get(:run_performance_age_seconds)
    end

    @impl true
    def metrics_run_queue_metrics_period_seconds do
      metrics_config() |> Keyword.get(:run_queue_metrics_period_seconds)
    end

    @impl true
    def metrics_stalled_run_threshold_seconds do
      metrics_config() |> Keyword.get(:stalled_run_threshold_seconds)
    end

    @impl true
    def metrics_unclaimed_run_threshold_seconds do
      metrics_config() |> Keyword.get(:unclaimed_run_threshold_seconds)
    end

    defp metrics_config, do: Application.get_env(:lightning, :metrics)
  end

  @callback apollo(key :: atom() | nil) :: map()
  @callback check_flag?(atom()) :: boolean() | nil
  @callback cors_origin() :: list()
  @callback default_max_run_duration() :: integer()
  @callback email_sender_name() :: String.t()
  @callback get_extension_mod(key :: atom()) :: any()
  @callback google(key :: atom()) :: any()
  @callback grace_period() :: integer()
  @callback instance_admin_email() :: String.t()
  @callback kafka_alternate_storage_enabled?() :: boolean()
  @callback kafka_alternate_storage_file_path() :: String.t()
  @callback kafka_duplicate_tracking_retention_seconds() :: integer()
  @callback kafka_notification_embargo_seconds() :: integer()
  @callback kafka_number_of_consumers() :: integer()
  @callback kafka_number_of_messages_per_second() :: float()
  @callback kafka_number_of_processors() :: integer()
  @callback kafka_triggers_enabled?() :: boolean()
  @callback metrics_run_performance_age_seconds() :: integer()
  @callback metrics_run_queue_metrics_period_seconds() :: integer()
  @callback metrics_stalled_run_threshold_seconds() :: integer()
  @callback metrics_unclaimed_run_threshold_seconds() :: integer()
  @callback oauth_provider(key :: atom()) :: keyword() | nil
  @callback promex_metrics_endpoint_authorization_required?() :: boolean()
  @callback promex_metrics_endpoint_scheme() :: String.t()
  @callback promex_metrics_endpoint_token() :: String.t()
  @callback purge_deleted_after_days() :: integer()
  @callback activity_cleanup_chunk_size() :: integer()
  @callback default_ecto_database_timeout() :: integer()
  @callback repo_connection_token_signer() :: Joken.Signer.t()
  @callback reset_password_token_validity_in_days() :: integer()
  @callback run_token_signer() :: Joken.Signer.t()
  @callback storage() :: term()
  @callback storage(key :: atom()) :: term()
  @callback token_signer() :: Joken.Signer.t()
  @callback ui_metrics_tracking_enabled?() :: boolean()
  @callback usage_tracking() :: Keyword.t()
  @callback usage_tracking_cleartext_uuids_enabled?() :: boolean()
  @callback usage_tracking_cron_opts() :: [Oban.Plugins.Cron.cron_input()]
  @callback usage_tracking_enabled?() :: boolean()
  @callback usage_tracking_host() :: String.t()
  @callback usage_tracking_run_chunk_size() :: integer()
  @callback worker_secret() :: binary() | nil
  @callback worker_token_signer() :: Joken.Signer.t()
  @callback adaptor_registry() :: Keyword.t()
  @callback credential_transfer_token_validity_in_days() :: integer()
  @callback book_demo_banner_enabled?() :: boolean()
  @callback book_demo_calendly_url() :: String.t()
  @callback book_demo_openfn_workflow_url() :: String.t()
  @callback gdpr_banner() :: map() | false
  @callback gdpr_preferences() :: map() | false
  @callback external_metrics_module() :: module() | nil
  @callback ai_assistant_modes() :: %{atom() => module()}
  @callback per_workflow_claim_limit() :: pos_integer()

  @doc """
  Returns the configuration for the `Lightning.AdaptorRegistry` service
  """
  def adaptor_registry do
    impl().adaptor_registry()
  end

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

  def token_signer do
    impl().token_signer()
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

  def activity_cleanup_chunk_size do
    impl().activity_cleanup_chunk_size()
  end

  def default_ecto_database_timeout do
    impl().default_ecto_database_timeout()
  end

  def check_flag?(flag) do
    impl().check_flag?(flag)
  end

  def get_extension_mod(key) do
    impl().get_extension_mod(key)
  end

  def google(key) do
    impl().google(key)
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

  def reset_password_token_validity_in_days do
    impl().reset_password_token_validity_in_days()
  end

  def storage do
    impl().storage()
  end

  def storage(key) do
    impl().storage(key)
  end

  def usage_tracking do
    impl().usage_tracking()
  end

  def usage_tracking_cleartext_uuids_enabled? do
    impl().usage_tracking_cleartext_uuids_enabled?()
  end

  def usage_tracking_cron_opts do
    impl().usage_tracking_cron_opts()
  end

  def usage_tracking_enabled? do
    impl().usage_tracking_enabled?()
  end

  def usage_tracking_host do
    impl().usage_tracking_host()
  end

  def usage_tracking_run_chunk_size do
    impl().usage_tracking_run_chunk_size()
  end

  def kafka_triggers_enabled? do
    impl().kafka_triggers_enabled?()
  end

  def kafka_alternate_storage_enabled? do
    impl().kafka_alternate_storage_enabled?()
  end

  def kafka_alternate_storage_file_path do
    impl().kafka_alternate_storage_file_path()
  end

  def kafka_duplicate_tracking_retention_seconds do
    impl().kafka_duplicate_tracking_retention_seconds()
  end

  def kafka_number_of_consumers do
    impl().kafka_number_of_consumers()
  end

  def kafka_notification_embargo_seconds do
    impl().kafka_notification_embargo_seconds()
  end

  def kafka_number_of_messages_per_second do
    impl().kafka_number_of_messages_per_second()
  end

  def kafka_number_of_processors do
    impl().kafka_number_of_processors()
  end

  def promex_metrics_endpoint_authorization_required? do
    impl().promex_metrics_endpoint_authorization_required?()
  end

  def promex_metrics_endpoint_scheme do
    impl().promex_metrics_endpoint_scheme()
  end

  def promex_metrics_endpoint_token do
    impl().promex_metrics_endpoint_token()
  end

  def ui_metrics_tracking_enabled? do
    impl().ui_metrics_tracking_enabled?()
  end

  def credential_transfer_token_validity_in_days do
    impl().credential_transfer_token_validity_in_days()
  end

  def book_demo_banner_enabled? do
    impl().book_demo_banner_enabled?()
  end

  def book_demo_calendly_url do
    impl().book_demo_calendly_url()
  end

  def book_demo_openfn_workflow_url do
    impl().book_demo_openfn_workflow_url()
  end

  def gdpr_banner do
    impl().gdpr_banner()
  end

  def gdpr_preferences do
    impl().gdpr_preferences()
  end

  def external_metrics_module do
    impl().external_metrics_module()
  end

  def ai_assistant_modes do
    impl().ai_assistant_modes()
  end

  def metrics_run_performance_age_seconds do
    impl().metrics_run_performance_age_seconds()
  end

  def metrics_run_queue_metrics_period_seconds do
    impl().metrics_run_queue_metrics_period_seconds()
  end

  def metrics_stalled_run_threshold_seconds do
    impl().metrics_stalled_run_threshold_seconds()
  end

  def metrics_unclaimed_run_threshold_seconds do
    impl().metrics_unclaimed_run_threshold_seconds()
  end

  def per_workflow_claim_limit do
    impl().per_workflow_claim_limit()
  end

  defp impl do
    Application.get_env(:lightning, __MODULE__, API)
  end
end
