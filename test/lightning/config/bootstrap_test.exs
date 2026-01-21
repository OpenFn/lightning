defmodule Lightning.Config.BootstrapTest do
  use ExUnit.Case, async: true

  alias Lightning.Config.Bootstrap

  import Mox
  setup :verify_on_exit!

  @opts_key {Config, :opts}
  @config_key {Config, :config}
  @imports_key {Config, :imports}

  # Setup some process keys to behave like the Config module when a config is
  # evaluated
  setup do
    Process.put(@opts_key, {:dev, ""})
    Process.put(@config_key, [])
    Process.put(@imports_key, [])

    :ok
  end

  test "without sourcing envs first" do
    assert_raise RuntimeError,
                 """
                 Environment variables haven't been sourced first.
                 Please call `source_envs/0` before calling `configure/0`.
                 """,
                 fn ->
                   Bootstrap.configure()
                 end
  end

  describe "prod" do
    setup do
      Process.put({Config, :opts}, {:prod, ""})
      Process.put({Config, :config}, [])
      Process.put({Config, :imports}, [])

      Process.delete(:dotenvy_vars)

      stub(Lightning.MockConfig, :webhook_retry, fn
        :timeout_ms -> 0
        _ -> nil
      end)

      :ok
    end

    test "prod" do
      Dotenvy.source([])

      assert_raise RuntimeError,
                   """
                   environment variable DATABASE_URL is missing.
                   For example: ecto://USER:PASS@HOST/DATABASE
                   """,
                   fn ->
                     Bootstrap.configure()
                   end

      Dotenvy.source([%{"DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE"}])

      assert_raise RuntimeError,
                   """
                   environment variable SECRET_KEY_BASE is missing.
                   You can generate one by calling: mix phx.gen.secret
                   """,
                   fn ->
                     Bootstrap.configure()
                   end

      Dotenvy.source([
        %{"SECRET_KEY_BASE" => "Foo"},
        %{"DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE"}
      ])

      Bootstrap.configure()

      assert {:url, "ecto://USER:PASS@HOST/DATABASE"} in get_env(
               :lightning,
               Lightning.Repo
             )
    end

    test "LightningWeb.Endpoint idle_timeout" do
      # 1) default (no IDLE_TIMEOUT provided) -> 60_000
      reconfigure(%{
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE"
      })

      assert endpoint_idle_timeout() == 60_000

      # 2) invalid IDLE_TIMEOUT -> falls back to 60_000
      reconfigure(%{
        "IDLE_TIMEOUT" => "",
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE"
      })

      assert endpoint_idle_timeout() == 60_000

      # 3) valid IDLE_TIMEOUT (seconds) -> converted to ms
      reconfigure(%{
        "IDLE_TIMEOUT" => "240",
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE"
      })

      assert endpoint_idle_timeout() == 240_000
    end

    test "idle_timeout honors retry timeout" do
      # override the default stub for this test
      stub(Lightning.MockConfig, :webhook_retry, fn
        :timeout_ms -> 60_000
        _ -> nil
      end)

      reconfigure(%{
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE"
      })

      # idle_timeout = max(60_000, 60_000 + 15_000) = 75_000
      assert endpoint_idle_timeout() == 75_000
    end
  end

  describe "storage" do
    setup context do
      envs = Map.get(context, :env) |> List.wrap()
      Dotenvy.source(envs)

      :ok
    end

    test "should default to using the local storage adapter" do
      Bootstrap.configure()

      storage = get_env(:lightning, Lightning.Storage)

      assert {:backend, Lightning.Storage.Local} in storage
      assert {:path, "."} in storage

      refute get_env(:lightning, :google_required)
    end

    @tag env: %{"STORAGE_PATH" => "/tmp"}
    test "can set the storage path" do
      Bootstrap.configure()

      storage = get_env(:lightning, Lightning.Storage)

      assert {:backend, Lightning.Storage.Local} in storage
      assert {:path, "/tmp"} in storage
    end

    @tag env: %{"STORAGE_BACKEND" => "gcs"}
    test "can set the storage backend use GCS", %{env: env} do
      assert_raise RuntimeError,
                   "GCS_BUCKET is not set, but STORAGE_BACKEND is set to gcs",
                   fn ->
                     Bootstrap.configure()
                   end

      Dotenvy.source([env, %{"GCS_BUCKET" => "foo"}])

      assert_raise RuntimeError,
                   "GOOGLE_APPLICATION_CREDENTIALS_JSON is not set, this is required when using Google Cloud services.",
                   fn ->
                     Bootstrap.configure()
                   end

      Dotenvy.source([
        env,
        %{"GCS_BUCKET" => "foo", "GOOGLE_APPLICATION_CREDENTIALS_JSON" => "bar"}
      ])

      assert_raise RuntimeError,
                   "Could not decode GOOGLE_APPLICATION_CREDENTIALS_JSON",
                   fn ->
                     Bootstrap.configure()
                   end

      Dotenvy.source([
        env,
        %{
          "GCS_BUCKET" => "foo",
          "GOOGLE_APPLICATION_CREDENTIALS_JSON" =>
            %{"I'm some" => "JSON"} |> Jason.encode!() |> Base.encode64()
        }
      ])

      Bootstrap.configure()

      storage = get_env(:lightning, Lightning.Storage)

      assert {:backend, Lightning.Storage.GCS} in storage
      assert {:bucket, "foo"} in storage

      assert {:credentials, %{"I'm some" => "JSON"}} in get_env(
               :lightning,
               Lightning.Google
             )

      assert {:required, true} in get_env(:lightning, Lightning.Google)
    end

    @tag env: %{"STORAGE_BACKEND" => "foo"}
    test "raises an error with unsupported backend" do
      assert_raise RuntimeError, ~r/Unknown storage backend: foo/, fn ->
        Bootstrap.configure()
      end
    end
  end

  describe "setting up a mailer" do
    setup context do
      envs = Map.get(context, :env) |> List.wrap()
      Dotenvy.source(envs)

      :ok
    end

    @tag env: %{}
    test "doesn't change anything by default" do
      Process.put(@config_key, lightning: Application.get_all_env(:lightning))
      Bootstrap.configure()

      assert get_env(:lightning, Lightning.Mailer) == [
               adapter: Swoosh.Adapters.Test
             ]
    end

    @tag env: %{}
    test "defaults the admin mail address isn't provided" do
      # This is not the cleanest test, in the real world, the admin email
      # key wouldn't exist - but since we fallback to real config (in this test case)
      # test.exs, we need to find a way to provide an invalid but available
      # value.
      # TODO: consider wrapping Application in a mock, and call get_env/3
      # on a compile time injected module.
      Process.put(@config_key, lightning: [emails: [admin_email: false]])

      Bootstrap.configure()

      assert {:admin_email, "lightning@example.com"} in get_env(
               :lightning,
               :emails
             )
    end

    @tag env: %{"MAIL_PROVIDER" => "mailgun"}
    test "sets up for mailgun", %{env: env} do
      assert_raise RuntimeError, ~r/MAILGUN_API_KEY not set/, fn ->
        Bootstrap.configure()
      end

      Dotenvy.source([
        env,
        %{"MAILGUN_API_KEY" => "foo", "MAILGUN_DOMAIN" => "bar"}
      ])

      Bootstrap.configure()

      assert get_env(:lightning, Lightning.Mailer) == [
               adapter: Swoosh.Adapters.Mailgun,
               api_key: "foo",
               domain: "bar"
             ]
    end

    @tag env: %{"MAIL_PROVIDER" => "local"}
    test "sets up for local" do
      Bootstrap.configure()

      assert get_env(:lightning, Lightning.Mailer) == [
               adapter: Swoosh.Adapters.Local
             ]
    end

    @tag env: %{"MAIL_PROVIDER" => "smtp"}
    test "sets up for smtp", %{env: env} do
      # Incrementally add the required environment variables, these are checked
      # in order and all of them are required.
      [
        {"SMTP_USERNAME", "foo"},
        {"SMTP_PASSWORD", "bar"},
        {"SMTP_RELAY", "baz"}
      ]
      |> Enum.reduce(
        env,
        fn {key, value}, env ->
          assert_raise RuntimeError, ~r/#{key} not set/, fn ->
            Bootstrap.configure()
          end

          Dotenvy.source!([env, %{key => value}])
        end
      )

      Bootstrap.configure()

      assert get_env(:lightning, Lightning.Mailer) == [
               adapter: Swoosh.Adapters.SMTP,
               username: "foo",
               password: "bar",
               relay: "baz",
               tls: :always,
               port: 587
             ]
    end
  end

  describe "kafka alternate storage" do
    setup %{
            tmp_dir: tmp_dir,
            enabled: enabled,
            misconfigured: misconfigured
          } = context do
      path = Map.get(context, :path, tmp_dir)

      %{"KAFKA_ALTERNATE_STORAGE_ENABLED" => enabled}
      |> then(fn vars ->
        if path do
          vars
          |> Map.put("KAFKA_ALTERNATE_STORAGE_FILE_PATH", path)
        else
          vars
        end
      end)
      |> List.wrap()
      |> Dotenvy.source()

      if misconfigured do
        tmp_dir |> File.chmod!(0o000)
      end

      :ok
    end

    @tag tmp_dir: true, enabled: "true", misconfigured: true
    test "raises an error if enabled and misconfigured" do
      assert_raise RuntimeError, ~r/must be a writable directory/, fn ->
        Bootstrap.configure()
      end
    end

    @tag tmp_dir: true, enabled: "true", misconfigured: false, path: "xxx/yyy"
    test "raises an error if enabled and path does not exist" do
      assert_raise RuntimeError, ~r/must be a writable directory/, fn ->
        Bootstrap.configure()
      end
    end

    @tag tmp_dir: true, enabled: "true", misconfigured: false, path: nil
    test "raises an error if enabled and path is nil" do
      assert_raise RuntimeError, ~r/must be a writable directory/, fn ->
        Bootstrap.configure()
      end
    end

    @tag tmp_dir: true, enabled: "true", misconfigured: false, path: ""
    test "raises an error if enabled and path is empty string" do
      assert_raise RuntimeError, ~r/must be a writable directory/, fn ->
        Bootstrap.configure()
      end
    end

    @tag tmp_dir: true, enabled: "true", misconfigured: false
    test "does not raise an error if enabled and properly configured" do
      Bootstrap.configure()
    end

    @tag tmp_dir: true, enabled: "false", misconfigured: true
    test "does not raise an error if disabled and misconfigured" do
      Bootstrap.configure()
    end

    @tag tmp_dir: true, enabled: "false", misconfigured: false, path: nil
    test "does not raise an error if disabled and path is nil" do
      Bootstrap.configure()
    end

    @tag tmp_dir: true, enabled: "false", misconfigured: false, path: ""
    test "does not raise an error if disabled and path is empty string" do
      Bootstrap.configure()
    end

    @tag tmp_dir: true, enabled: "false", misconfigured: false, path: "xxx/yyy"
    test "does not raise an error if disabled and path does not exist" do
      Bootstrap.configure()
    end
  end

  describe "adaptor registry" do
    test "raises an exception when LOCAL_ADAPTORS is set to true but OPENFN_ADAPTORS_REPO is not set" do
      assert_raise RuntimeError,
                   ~r/LOCAL_ADAPTORS is set to true, but OPENFN_ADAPTORS_REPO is not set/,
                   fn ->
                     Dotenvy.source([%{"LOCAL_ADAPTORS" => "true"}])

                     Bootstrap.configure()
                   end
    end

    test "local_adaptors_repo is set to false when OPENFN_ADAPTORS_REPO is set but LOCAL_ADAPTORS is not set" do
      Dotenvy.source([%{"OPENFN_ADAPTORS_REPO" => "/path"}])
      Bootstrap.configure()

      adaptor_registry = get_env(:lightning, Lightning.AdaptorRegistry)

      assert adaptor_registry[:local_adaptors_repo] == false
    end

    test "local_adaptors_repo is set when both OPENFN_ADAPTORS_REPO and LOCAL_ADAPTORS are set" do
      # configure both
      Dotenvy.source([
        %{"OPENFN_ADAPTORS_REPO" => "/path", "LOCAL_ADAPTORS" => "true"}
      ])

      Bootstrap.configure()

      adaptor_registry = get_env(:lightning, Lightning.AdaptorRegistry)

      assert adaptor_registry[:local_adaptors_repo] == "/path"
    end
  end

  describe "per_workflow_claim_limit" do
    test "defaults to 50" do
      Dotenvy.source([%{}])
      Bootstrap.configure()
      assert get_env(:lightning, :per_workflow_claim_limit) == 50
    end

    test "can be set to a different value" do
      Dotenvy.source([%{"PER_WORKFLOW_CLAIM_LIMIT" => "100"}])
      Bootstrap.configure()
      assert get_env(:lightning, :per_workflow_claim_limit) == 100
    end

    test "must be a positive integer" do
      Dotenvy.source([%{"PER_WORKFLOW_CLAIM_LIMIT" => "0"}])

      assert_raise RuntimeError,
                   ~r/PER_WORKFLOW_CLAIM_LIMIT must be a positive integer/,
                   fn ->
                     Bootstrap.configure()
                   end
    end

    test "must be an integer" do
      Dotenvy.source([%{"PER_WORKFLOW_CLAIM_LIMIT" => "foo"}])

      assert_raise RuntimeError,
                   "Error converting variable PER_WORKFLOW_CLAIM_LIMIT to integer: Unparsable as integer",
                   fn ->
                     Bootstrap.configure()
                   end
    end
  end

  describe "claim_work_mem" do
    test "defaults to nil" do
      Dotenvy.source([%{}])
      Bootstrap.configure()
      assert get_env(:lightning, :claim_work_mem) == nil
    end

    test "can be set to a value" do
      Dotenvy.source([%{"CLAIM_WORK_MEM" => "64MB"}])
      Bootstrap.configure()
      assert get_env(:lightning, :claim_work_mem) == "64MB"
    end

    test "empty string becomes nil" do
      Dotenvy.source([%{"CLAIM_WORK_MEM" => ""}])
      Bootstrap.configure()
      assert get_env(:lightning, :claim_work_mem) == nil
    end

    test "accepts valid PostgreSQL memory values" do
      for value <- ["256kB", "32MB", "1GB", "2TB", "128mb", "1gb"] do
        Dotenvy.source([%{"CLAIM_WORK_MEM" => value}])
        Bootstrap.configure()
        assert get_env(:lightning, :claim_work_mem) == value
      end
    end

    test "rejects invalid memory values" do
      Dotenvy.source([%{"CLAIM_WORK_MEM" => "invalid"}])

      assert_raise RuntimeError,
                   ~r/Invalid CLAIM_WORK_MEM value/,
                   fn ->
                     Bootstrap.configure()
                   end
    end

    test "rejects values without units" do
      Dotenvy.source([%{"CLAIM_WORK_MEM" => "32"}])

      assert_raise RuntimeError,
                   ~r/Invalid CLAIM_WORK_MEM value/,
                   fn ->
                     Bootstrap.configure()
                   end
    end
  end

  describe "webhook retry (dev)" do
    test "does not set :webhook_retry when no WEBHOOK_RETRY_* envs are provided" do
      Dotenvy.source([%{}])
      Bootstrap.configure()
      assert get_env(:lightning, :webhook_retry) == nil
    end

    test "sets only provided keys with correct types" do
      Dotenvy.source([
        %{
          "WEBHOOK_RETRY_MAX_ATTEMPTS" => "7",
          "WEBHOOK_RETRY_INITIAL_DELAY_MS" => "250",
          "WEBHOOK_RETRY_MAX_DELAY_MS" => "5000",
          "WEBHOOK_RETRY_BACKOFF_FACTOR" => "1.5",
          "WEBHOOK_RETRY_TIMEOUT_MS" => "42000",
          "WEBHOOK_RETRY_JITTER" => "false"
        }
      ])

      Bootstrap.configure()

      actual = get_env(:lightning, :webhook_retry) |> Enum.sort()

      expected =
        [
          max_attempts: 7,
          initial_delay_ms: 250,
          max_delay_ms: 5000,
          backoff_factor: 1.5,
          timeout_ms: 42_000,
          jitter: false
        ]
        |> Enum.sort()

      assert actual == expected
    end

    test "accepts a partial set of variables and stores only those" do
      Dotenvy.source([
        %{"WEBHOOK_RETRY_MAX_ATTEMPTS" => "9"}
      ])

      Bootstrap.configure()
      assert get_env(:lightning, :webhook_retry) == [max_attempts: 9]
    end

    test "parses jitter boolean values using Utils.ensure_boolean/1" do
      Dotenvy.source([%{"WEBHOOK_RETRY_JITTER" => "true"}])
      Bootstrap.configure()
      assert get_env(:lightning, :webhook_retry) == [jitter: true]
    end
  end

  describe "promex metrics configuration" do
    @tag env: %{}
    test "`expensive_metrics_enabled` is false if env variable is not set", %{
      env: env
    } do
      Dotenvy.source([env])

      Bootstrap.configure()

      enable =
        :lightning
        |> get_env(Lightning.PromEx)
        |> Keyword.get(:expensive_metrics_enabled)

      assert enable == false
    end

    @tag env: %{"PROMEX_EXPENSIVE_METRICS_ENABLED" => "yes"}
    test "`expensive_metrics_enabled` is true if env variable is truthy", %{
      env: env
    } do
      Dotenvy.source([env])

      Bootstrap.configure()

      enable =
        :lightning
        |> get_env(Lightning.PromEx)
        |> Keyword.get(:expensive_metrics_enabled)

      assert enable == true
    end

    @tag env: %{"PROMEX_EXPENSIVE_METRICS_ENABLED" => "no"}
    test "`expensive_metrics_enabled` is false if env variable is falsey", %{
      env: env
    } do
      Dotenvy.source([env])

      Bootstrap.configure()

      enable =
        :lightning
        |> get_env(Lightning.PromEx)
        |> Keyword.get(:expensive_metrics_enabled)

      assert enable == false
    end
  end

  describe "worker private key validation" do
    test "accepts valid RSA keys" do
      rsa_key = """
      -----BEGIN RSA PRIVATE KEY-----
      MIIEpQIBAAKCAQEAxGY6EPnNbNPmhaQ1O7ACAvqIO/V+qKjxpb10GjUIQVATfHJh
      m4iuoRz7q+d9PUSksMJOI+1koRMvW2zBH6Bb7x7BDwNLjjEN0U5JZi6LfiKUxU1g
      5FnqZB+NWj7BGNXQ+I4sNcibv/1zXPdVEcqGWy7fHfVyc8Cis6vglYqg6s5lsjIJ
      bmmBwmpqtfyLHWLu/Dqb3TSVcxzqRVNIZCS2UToUJotiYUaG5oKftfY164hnwDH8
      deXP7mEU3FTsv+jtsJoK4Bo5VyGABuN+gpaoLtYdcUS2VajHsGq8IZsxXhyCnCoq
      2n/sd5pwVAE68Lv0fkuN86uX0nWzbUVwO74ulwIDAQABAoIBAQCzbn4QclkG21XZ
      tRtZa8V6uS9sMC7GoosblEoVg2wGV8Vlxg59DdQVqCgadwTJzAP25Z6EXme4bZGv
      ol2Sqmwzu9JACA+oWhK4riCK9W1GEQwAcmBaX/ev/8+hqoG6UeZ4n1Ou05fQQRt7
      zQ/wkCpN9jWr5knpjQ5YvmgR17SKr+kC3ZixtZ5aKtA+daz0q6AxA/E/9iG++LJ4
      g5wV0fb6f2L11sQIKfrK2zBSEI+hL7VdC6EoBbx4jkxqfZbCodZNYQ8/Q/OoFO+d
      BQzUTzBHUSVjz65814tPVgBYRMnATsbrCoeBu6IxNVhtpvRBKH/69hNaRpgUBILk
      nXwb6SwJAoGBAPh1NE5rmeSVah6VeP1c4D5tDbT0+Pxhsun5t7lWTvOIxMWR/4da
      HORn8Fl0AsNco5UqmYHF13P0B7NMt5VCpyVMqCcnvvtskpp51lA9b1v0Ab+Izdm7
      Udlvx3wbagK/5vDP8aiCYIRXxXDMUTbbc88LmF80N/uS/v6aOb42yQQzAoGBAMpc
      eDb63Zp3SvbYYYotFysLDijS9/+BjUtL619mo3Jf5tsOvB5qZPZ517nimhXEN6Rz
      tANZcSTyHYk3xMY4r+EL9efoqB8M/KKG+0rZznzASi+Qt2VeIpRz/7PDSHiX9MOA
      h0EcVRu3WyeHLVikA604oPwDLDK8qJXoPPOAmygNAoGADpDAakCAmxfvSq+0khXZ
      x48ZGJyr5A/OL01GagUXR8uizXpLoqGzw+gb/QKCDvXlWR9QNH1mrhOGSAqdUJDB
      v7wIt5Lq7U5mIcw2timD174sRBA/ER6cI8UbyrjItDSP01o9boWGJvwGRSCVOkQP
      O/oQCrTC+2qYrFBaRj5r9mUCgYEAgyejkp7NegvPPmXH8jJ/TZqAttzld2iUFzVB
      fDedv8eAbIIEUwJKJaWauBOyImFmXuPOzEzwFC4IDqNimcar14RVANW+AUH9i6lI
      vZ6lQh2u910oQD7e0rDMDcqH8gEq1ns7LmwajTgtkFUAgu7qox6M2EmGH+w+p8o5
      lujHpxECgYEAw9mV+W6EC9Bq07KGDI8ar8Ugnm3Jqo127lPiSsWiEIr9KOLiOilK
      fzPupZ4bQo5LVtYp85xcf64oyiAiPlWc7K+ecPh/FEDQtTvDbfhicd57OKv5ThT6
      otkxgXHLEBs9GZZZz+MyVsY8ricBmcFfYEb8wybE5opAOct08Xbrzec=
      -----END RSA PRIVATE KEY-----
      """

      encoded_key = Base.encode64(rsa_key, padding: false)

      Dotenvy.source([%{"WORKER_RUNS_PRIVATE_KEY" => encoded_key}])

      assert :ok = Bootstrap.configure()

      # Verify the key was actually set
      private_key = get_env(:lightning, :workers) |> Keyword.get(:private_key)
      assert is_binary(private_key)
      assert private_key =~ "BEGIN RSA PRIVATE KEY"
    end

    test "rejects non-RSA keys (Ed25519 / OKP)" do
      # Ed25519 key - OKP (Octet Key Pair) type
      ed25519_key = """
      -----BEGIN PRIVATE KEY-----
      MC4CAQAwBQYDK2VwBCIEIGCa7P/7SXCoLXsmDPoRcfqU4aGVWkgFb8pWNVSPUNzR
      -----END PRIVATE KEY-----
      """

      encoded_key = Base.encode64(ed25519_key, padding: false)

      Dotenvy.source([%{"WORKER_RUNS_PRIVATE_KEY" => encoded_key}])

      error =
        assert_raise RuntimeError, fn ->
          Bootstrap.configure()
        end

      assert error.message =~ "WORKER_RUNS_PRIVATE_KEY has wrong key type:"
      assert error.message =~ "Lightning requires an RSA key for RS256 signing"
      assert error.message =~ "mix lightning.gen_worker_keys"
    end

    test "rejects EC (Elliptic Curve) keys" do
      # EC P-256 key for testing
      ec_key = """
      -----BEGIN EC PRIVATE KEY-----
      MHcCAQEEIIGlRHKQphLqMvj/+/P5wXDqQj8u1fJzJqNQKJvqPRq9oAoGCCqGSM49
      AwEHoUQDQgAEgTyTZ5fzGh4x4L3KXqjJLLQI4j3TqvLUqh3ScxqL5qJqvLUqh3Sc
      xqL5qJqvLUqh3ScxqL5qJqvLUqh3ScxqLw==
      -----END EC PRIVATE KEY-----
      """

      encoded_key = Base.encode64(ec_key, padding: false)

      Dotenvy.source([%{"WORKER_RUNS_PRIVATE_KEY" => encoded_key}])

      error =
        assert_raise RuntimeError, fn ->
          Bootstrap.configure()
        end

      assert error.message =~ "WORKER_RUNS_PRIVATE_KEY has wrong key type:"
      assert error.message =~ "Lightning requires an RSA key for RS256 signing"
      assert error.message =~ "mix lightning.gen_worker_keys"
    end

    test "handles malformed PEM data" do
      # Invalid PEM structure - should trigger rescue path
      malformed_pem = """
      -----BEGIN PRIVATE KEY-----
      This is not valid base64 encoded key data!!!
      -----END PRIVATE KEY-----
      """

      encoded_key = Base.encode64(malformed_pem, padding: false)

      Dotenvy.source([%{"WORKER_RUNS_PRIVATE_KEY" => encoded_key}])

      error =
        assert_raise RuntimeError, fn ->
          Bootstrap.configure()
        end

      assert error.message =~
               "WORKER_RUNS_PRIVATE_KEY could not be parsed:"

      assert error.message =~ "mix lightning.gen_worker_keys"
    end

    test "handles completely invalid PEM format" do
      # Not even PEM format - should trigger rescue path
      invalid_data = "not-a-pem-key-at-all"

      encoded_key = Base.encode64(invalid_data, padding: false)

      Dotenvy.source([%{"WORKER_RUNS_PRIVATE_KEY" => encoded_key}])

      error =
        assert_raise RuntimeError, fn ->
          Bootstrap.configure()
        end

      assert error.message =~
               "WORKER_RUNS_PRIVATE_KEY could not be parsed as a valid key"

      assert error.message =~ "mix lightning.gen_worker_keys"
    end
  end

  # Helpers to read the in-process config that Config writes
  defp get_env(app) do
    Process.get(@config_key)
    |> Keyword.get(app)
  end

  defp get_env(app, key) do
    get_env(app)
    |> Enum.find(&match?({^key, _}, &1))
    |> case do
      {_, value} -> value
      nil -> nil
    end
  end

  defp reconfigure(envs) do
    Process.put({Config, :config}, [])
    Process.put({Config, :imports}, [])
    Process.delete(:dotenvy_vars)
    Dotenvy.source([envs])
    Lightning.Config.Bootstrap.configure()
  end

  defp endpoint_idle_timeout do
    :lightning
    |> get_env(LightningWeb.Endpoint)
    |> get_in([:http, :protocol_options, :idle_timeout])
  end
end
