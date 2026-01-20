defmodule Lightning.Configtest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Lightning.Config.API

  describe "API" do
    test "returns the appropriate PromEx endpoint auth setting" do
      expected =
        extract_from_config(
          Lightning.PromEx,
          :metrics_endpoint_authorization_required
        )

      actual = API.promex_metrics_endpoint_authorization_required?()

      assert expected == actual
    end

    test "returns the appropriate Promex endpoint token" do
      expected =
        extract_from_config(Lightning.PromEx, :metrics_endpoint_token)

      actual = API.promex_metrics_endpoint_token()

      assert expected == actual
    end

    test "returns the appropriate PromEx endpoint scheme" do
      expected =
        extract_from_config(Lightning.PromEx, :metrics_endpoint_scheme)

      actual = API.promex_metrics_endpoint_scheme()

      assert expected == actual
    end

    test "indicates if expensive metrics are enabled" do
      expected =
        extract_from_config(Lightning.PromEx, :expensive_metrics_enabled)

      actual = API.promex_expensive_metrics_enabled?()

      assert expected == actual
    end

    test "indicates if the tracking of UI metrics is enabled" do
      expected =
        extract_from_config(:ui_metrics_tracking, :enabled)

      actual = API.ui_metrics_tracking_enabled?()

      assert expected == actual
    end

    test "returns module responsible for injecting external metric plugins" do
      expected =
        extract_from_config(Lightning.Extensions, :external_metrics)

      refute expected == nil

      actual = API.external_metrics_module()

      assert expected == actual
    end

    test "returns configured AI modes" do
      modes = API.ai_assistant_modes()

      assert modes[:job] == LightningWeb.Live.AiAssistant.Modes.JobCode

      assert modes[:workflow] ==
               LightningWeb.Live.AiAssistant.Modes.WorkflowTemplate
    end

    test "returns number of seconds that constitutes stalled run threshold" do
      expected =
        extract_from_config(
          :metrics,
          :stalled_run_threshold_seconds
        )

      actual = API.metrics_stalled_run_threshold_seconds()

      assert expected == actual
    end

    test "returns max allowable age of a run when considering run performance" do
      expected =
        extract_from_config(
          :metrics,
          :run_performance_age_seconds
        )

      actual = API.metrics_run_performance_age_seconds()

      assert expected == actual
    end

    test "returns the polling period in seconds for run queue metrics" do
      expected =
        extract_from_config(
          :metrics,
          :run_queue_metrics_period_seconds
        )

      actual = API.metrics_run_queue_metrics_period_seconds()

      assert expected == actual
    end

    test "returns the number of seconds before a run is 'unclaimed'" do
      expected =
        extract_from_config(
          :metrics,
          :unclaimed_run_threshold_seconds
        )

      actual = API.metrics_unclaimed_run_threshold_seconds()

      assert expected == actual
    end

    test "returns the per workflow claim limit" do
      expected = Application.get_env(:lightning, :per_workflow_claim_limit, 50)

      actual = API.per_workflow_claim_limit()

      assert expected == actual
    end

    test "returns the claim work_mem setting" do
      prev = Application.get_env(:lightning, :claim_work_mem)

      try do
        Application.put_env(:lightning, :claim_work_mem, "64MB")
        assert API.claim_work_mem() == "64MB"
      after
        if prev,
          do: Application.put_env(:lightning, :claim_work_mem, prev),
          else: Application.delete_env(:lightning, :claim_work_mem)
      end
    end

    test "run_token_signer/0 does not log error for RSA keys" do
      # The test config uses an RSA key, so this should not log any errors
      log =
        capture_log(fn ->
          API.run_token_signer()
        end)

      refute log =~ "WORKER_RUNS_PRIVATE_KEY has wrong key type"
    end

    test "run_token_signer/0 logs error for non-RSA keys" do
      # Ed25519 key for testing
      ed25519_key = """
      -----BEGIN PRIVATE KEY-----
      MC4CAQAwBQYDK2VwBCIEIGCa7P/7SXCoLXsmDPoRcfqU4aGVWkgFb8pWNVSPUNzR
      -----END PRIVATE KEY-----
      """

      with_worker_key(ed25519_key, fn ->
        log =
          capture_log(fn ->
            API.run_token_signer()
          end)

        assert log =~ "WORKER_RUNS_PRIVATE_KEY has wrong key type"
        assert log =~ "Lightning requires an RSA key for RS256 signing"
        assert log =~ "mix lightning.gen_worker_keys"
      end)
    end
  end

  describe "webhook_retry (merge + normalize)" do
    test "returns normalized defaults when not configured" do
      with_retry_env(nil, fn ->
        kw = API.webhook_retry()

        assert kw == [
                 max_attempts: 5,
                 initial_delay_ms: 100,
                 max_delay_ms: 10_000,
                 timeout_ms: 60_000,
                 backoff_factor: 2.0,
                 jitter: true
               ]
      end)
    end

    test "coerces/clamps out-of-range values" do
      bad = [
        max_attempts: 0,
        initial_delay_ms: -5,
        max_delay_ms: 3,
        backoff_factor: 0.5,
        timeout_ms: -10,
        jitter: false
      ]

      with_retry_env(bad, fn ->
        kw = API.webhook_retry()
        assert kw[:max_attempts] == 1
        assert kw[:initial_delay_ms] == 0
        assert kw[:max_delay_ms] >= kw[:initial_delay_ms]
        assert kw[:backoff_factor] == 1.0
        assert kw[:timeout_ms] == 0
        assert kw[:jitter] == false
      end)
    end

    test "ensures max_delay_ms >= initial_delay_ms" do
      with_retry_env([initial_delay_ms: 200, max_delay_ms: 100], fn ->
        kw = API.webhook_retry()
        assert kw[:initial_delay_ms] == 200
        assert kw[:max_delay_ms] == 200
      end)
    end

    test "webhook_retry/1 fetches normalized values and raises on unknown key" do
      with_retry_env([max_attempts: 6, jitter: false], fn ->
        assert API.webhook_retry(:max_attempts) == 6
        assert API.webhook_retry(:jitter) == false
        assert_raise KeyError, fn -> API.webhook_retry(:nope) end
      end)
    end
  end

  defp with_retry_env(value, fun) when is_function(fun, 0) do
    prev = Application.get_env(:lightning, :webhook_retry)

    try do
      if is_nil(value) do
        Application.delete_env(:lightning, :webhook_retry)
      else
        Application.put_env(:lightning, :webhook_retry, value)
      end

      fun.()
    after
      case prev do
        nil -> Application.delete_env(:lightning, :webhook_retry)
        _ -> Application.put_env(:lightning, :webhook_retry, prev)
      end
    end
  end

  defp extract_from_config(config, key) do
    Application.get_env(:lightning, config) |> Keyword.get(key)
  end

  defp with_worker_key(pem, fun) when is_function(fun, 0) do
    prev = Application.get_env(:lightning, :workers)

    try do
      new_config = Keyword.put(prev || [], :private_key, pem)
      Application.put_env(:lightning, :workers, new_config)
      fun.()
    after
      case prev do
        nil -> Application.delete_env(:lightning, :workers)
        _ -> Application.put_env(:lightning, :workers, prev)
      end
    end
  end
end
