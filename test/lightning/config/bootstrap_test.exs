defmodule Lightning.Config.BootstrapTest do
  use ExUnit.Case, async: true

  alias Lightning.Config.Bootstrap

  import Mox
  import ExUnit.CaptureLog
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

  describe "source_envs/1" do
    @describetag :tmp_dir

    test "a file it can't parse stops the boot without quoting it", %{
      tmp_dir: tmp_dir
    } do
      {_, ec_pem} = JOSE.JWK.generate_key({:ec, "P-256"}) |> JOSE.JWK.to_pem()

      key_lines =
        ec_pem
        |> String.split("\n", trim: true)
        |> Enum.reject(&String.starts_with?(&1, "-----"))

      for {contents, secrets} <- [
            {"K=#{ec_pem}", key_lines},
            {~s(SECRET_KEY_BASE=s3cr3tPart"rest"\n), ["s3cr3tPart"]}
          ] do
        file = Path.join(tmp_dir, ".env")
        File.write!(file, contents)

        error =
          assert_raise RuntimeError, fn -> Bootstrap.source_envs([file]) end

        assert error.message ==
                 "Could not load #{file}: it is not a valid env file. " <>
                   "The parser's own message is left out because it quotes " <>
                   "the line it stopped at, which can be part of a secret. " <>
                   "The usual cause is a value that runs over several lines " <>
                   "without double quotes around it, such as a PEM key."

        for secret <- secrets, do: refute(error.message =~ secret)
      end
    end

    test "later files win, and the shell beats every file", %{
      tmp_dir: tmp_dir
    } do
      first = Path.join(tmp_dir, ".env")
      second = Path.join(tmp_dir, ".dev.env")

      File.write!(first, """
      SOURCE_ENVS_TEST_VAR=first
      SOURCE_ENVS_TEST_BASE=base
      PATH=from-a-file
      """)

      File.write!(second, """
      SOURCE_ENVS_TEST_VAR=second
      SOURCE_ENVS_TEST_REF=${SOURCE_ENVS_TEST_BASE}-ref
      """)

      Bootstrap.source_envs([first, second, Path.join(tmp_dir, "missing.env")])

      assert %{
               "SOURCE_ENVS_TEST_VAR" => "second",
               "SOURCE_ENVS_TEST_REF" => "base-ref",
               "PATH" => path
             } = Process.get(:dotenvy_vars)

      assert path == System.get_env("PATH")
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

    test "Repo socket options" do
      db = %{
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE"
      }

      reconfigure(db)
      assert repo_opt(:socket_options) == dead_socket_options(20_000)

      reconfigure(Map.put(db, "DATABASE_TIMEOUT", "30000"))
      assert repo_opt(:socket_options) == dead_socket_options(35_000)

      reconfigure(Map.put(db, "DATABASE_TCP_USER_TIMEOUT", "25000"))
      assert repo_opt(:socket_options) == dead_socket_options(25_000)

      reconfigure(Map.put(db, "ECTO_IPV6", "true"))

      assert repo_opt(:socket_options) ==
               [:inet6 | dead_socket_options(20_000)]

      reconfigure(Map.put(db, "DATABASE_TCP_USER_TIMEOUT", "0"))
      assert repo_opt(:socket_options) == []
    end

    test "rejects a DATABASE_TCP_USER_TIMEOUT the kernel would refuse" do
      for bad <- ["-1", "2147483648"] do
        assert_raise RuntimeError, ~r/DATABASE_TCP_USER_TIMEOUT/, fn ->
          reconfigure(%{
            "SECRET_KEY_BASE" => "Foo",
            "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE",
            "DATABASE_TCP_USER_TIMEOUT" => bad
          })
        end
      end
    end

    test "warns on Linux when DATABASE_TCP_USER_TIMEOUT is below DATABASE_TIMEOUT" do
      configure_with = fn tcp_user_timeout ->
        capture_log(fn ->
          reconfigure(%{
            "SECRET_KEY_BASE" => "Foo",
            "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE",
            "DATABASE_TCP_USER_TIMEOUT" => tcp_user_timeout
          })
        end)
      end

      assert configure_with.("5000") =~ "DATABASE_TCP_USER_TIMEOUT" == linux?()
      refute configure_with.("20000") =~ "DATABASE_TCP_USER_TIMEOUT"
    end

    test "Repo SSL is on by default and disabled by DISABLE_DB_SSL" do
      # SSL defaults on for managed Postgres; DISABLE_DB_SSL opts out
      reconfigure(%{
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE"
      })

      assert repo_opt(:ssl) == :tls_certificate_check.options("HOST")

      reconfigure(%{
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE",
        "DISABLE_DB_SSL" => "true"
      })

      assert repo_opt(:ssl) == false
    end

    test "prod endpoint URL defaults" do
      reconfigure(%{
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE"
      })

      endpoint = get_env(:lightning, LightningWeb.Endpoint)

      assert get_in(endpoint, [:url, :host]) == "example.com"
      assert get_in(endpoint, [:url, :port]) == 443
      assert get_in(endpoint, [:url, :scheme]) == "https"
    end

    test "prod endpoint URL env var overrides" do
      reconfigure(%{
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE",
        "URL_HOST" => "myapp.example.com",
        "URL_PORT" => "8443",
        "URL_SCHEME" => "http"
      })

      endpoint = get_env(:lightning, LightningWeb.Endpoint)

      assert get_in(endpoint, [:url, :host]) == "myapp.example.com"
      assert get_in(endpoint, [:url, :port]) == 8443
      assert get_in(endpoint, [:url, :scheme]) == "http"
    end

    test "PORT vs URL_PORT in prod" do
      reconfigure(%{
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE",
        "PORT" => "8080",
        "URL_PORT" => "443"
      })

      endpoint = get_env(:lightning, LightningWeb.Endpoint)

      assert get_in(endpoint, [:http, :port]) == 8080
      assert get_in(endpoint, [:url, :port]) == 443
    end

    test "DISABLE_DB_SSL true, DISABLE_DB_SSL_CERT_VERIFY not set" do
      reconfigure(%{
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE",
        "DISABLE_DB_SSL" => "true"
      })

      repo_env = get_env(:lightning, Lightning.Repo)

      assert get_in(repo_env, [:ssl]) == false
    end

    test "DISABLE_DB_SSL true, DISABLE_DB_SSL_CERT_VERIFY true" do
      reconfigure(%{
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE",
        "DISABLE_DB_SSL" => "true",
        "DISABLE_DB_SSL_CERT_VERIFY" => "true"
      })

      repo_env = get_env(:lightning, Lightning.Repo)

      assert get_in(repo_env, [:ssl]) == false
    end

    test "DISABLE_DB_SSL true, DISABLE_DB_SSL_CERT_VERIFY false" do
      reconfigure(%{
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE",
        "DISABLE_DB_SSL" => "true",
        "DISABLE_DB_SSL_CERT_VERIFY" => "false"
      })

      repo_env = get_env(:lightning, Lightning.Repo)

      assert get_in(repo_env, [:ssl]) == false
    end

    test "DISABLE_DB_SSL not set, DISABLE_DB_SSL_CERT_VERIFY not set" do
      reconfigure(%{
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE"
      })

      repo_env = get_env(:lightning, Lightning.Repo)

      assert get_in(repo_env, [:ssl]) == :tls_certificate_check.options("HOST")
    end

    test "DISABLE_DB_SSL false, DISABLE_DB_SSL_CERT_VERIFY not set" do
      reconfigure(%{
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE",
        "DISABLE_DB_SSL" => "false"
      })

      repo_env = get_env(:lightning, Lightning.Repo)

      assert get_in(repo_env, [:ssl]) == :tls_certificate_check.options("HOST")
    end

    test "DISABLE_DB_SSL not set, `DISABLE_DB_SSL_CERT_VERIFY true" do
      reconfigure(%{
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE",
        "DISABLE_DB_SSL_CERT_VERIFY" => "true"
      })

      repo_env = get_env(:lightning, Lightning.Repo)

      assert get_in(repo_env, [:ssl]) == [verify: :verify_none]
    end

    test "DISABLE_DB_SSL false, DISABLE_DB_SSL_CERT_VERIFY true" do
      reconfigure(%{
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE",
        "DISABLE_DB_SSL" => "false",
        "DISABLE_DB_SSL_CERT_VERIFY" => "true"
      })

      repo_env = get_env(:lightning, Lightning.Repo)

      assert get_in(repo_env, [:ssl]) == [verify: :verify_none]
    end

    test "DISABLE_DB_SSL not set, DISABLE_DB_SSL_CERT_VERIFY false" do
      reconfigure(%{
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE",
        "DISABLE_DB_SSL_CERT_VERIFY" => "false"
      })

      repo_env = get_env(:lightning, Lightning.Repo)

      assert get_in(repo_env, [:ssl]) == :tls_certificate_check.options("HOST")
    end

    test "DISABLE_DB_SSL false, DISABLE_DB_SSL_CERT_VERIFY false" do
      reconfigure(%{
        "SECRET_KEY_BASE" => "Foo",
        "DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE",
        "DISABLE_DB_SSL" => "false",
        "DISABLE_DB_SSL_CERT_VERIFY" => "false"
      })

      repo_env = get_env(:lightning, Lightning.Repo)

      assert get_in(repo_env, [:ssl]) == :tls_certificate_check.options("HOST")
    end
  end

  describe "endpoint URL configuration (dev)" do
    test "URL_HOST works in dev" do
      Dotenvy.source([%{"URL_HOST" => "dev-elixir.local"}])
      Bootstrap.configure()

      endpoint = get_env(:lightning, LightningWeb.Endpoint)

      assert get_in(endpoint, [:url, :host]) == "dev-elixir.local"
    end

    test "URL_SCHEME works in dev" do
      Dotenvy.source([%{"URL_SCHEME" => "https"}])
      Bootstrap.configure()

      endpoint = get_env(:lightning, LightningWeb.Endpoint)

      assert get_in(endpoint, [:url, :scheme]) == "https"
    end

    test "URL_PORT works in dev" do
      Dotenvy.source([%{"URL_PORT" => "8080"}])
      Bootstrap.configure()

      endpoint = get_env(:lightning, LightningWeb.Endpoint)

      assert get_in(endpoint, [:url, :port]) == 8080
    end

    test "PORT sets both http and url port in dev" do
      Dotenvy.source([%{"PORT" => "5000"}])
      Bootstrap.configure()

      endpoint = get_env(:lightning, LightningWeb.Endpoint)

      assert get_in(endpoint, [:http, :port]) == 5000
      assert get_in(endpoint, [:url, :port]) == 5000
    end

    test "PORT and URL_PORT can differ in dev" do
      Dotenvy.source([%{"PORT" => "5000", "URL_PORT" => "443"}])
      Bootstrap.configure()

      endpoint = get_env(:lightning, LightningWeb.Endpoint)

      assert get_in(endpoint, [:http, :port]) == 5000
      assert get_in(endpoint, [:url, :port]) == 443
    end

    test "dev defaults" do
      Dotenvy.source([%{}])
      Bootstrap.configure()

      endpoint = get_env(:lightning, LightningWeb.Endpoint)

      assert get_in(endpoint, [:url, :host]) == "localhost"
      assert get_in(endpoint, [:url, :scheme]) == "http"
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

      config = get_env(:lightning, Lightning.Mailer)

      assert config == [
               adapter: Swoosh.Adapters.SMTP,
               username: "foo",
               password: "bar",
               relay: "baz",
               tls: :always,
               tls_options: :tls_certificate_check.options("baz"),
               port: 587
             ]

      tls_options = Keyword.get(config, :tls_options)

      assert {:verify, :verify_peer} in tls_options
      assert is_list(Keyword.get(tls_options, :cacerts))
      assert Keyword.has_key?(tls_options, :customize_hostname_check)
    end
  end

  describe "adaptor registry" do
    test "raises when LOCAL_ADAPTORS is set to true but no repo path is set" do
      assert_raise RuntimeError,
                   ~r/ADAPTORS_STRATEGY is set to local, but neither ADAPTORS_LOCAL_REPO nor/,
                   fn ->
                     Dotenvy.source([%{"LOCAL_ADAPTORS" => "true"}])

                     Bootstrap.configure()
                   end
    end

    test "LOCAL_ADAPTORS=true with ADAPTORS_LOCAL_REPO boots the local strategy and only warns" do
      log =
        capture_log(fn ->
          Dotenvy.source([
            %{"LOCAL_ADAPTORS" => "true", "ADAPTORS_LOCAL_REPO" => "/path"}
          ])

          Bootstrap.configure()
        end)

      assert get_env(:lightning, Lightning.Adaptors)[:strategy] ==
               Lightning.Adaptors.Local

      assert get_env(:lightning, Lightning.Adaptors.Local)[:paths] == ["/path"]
      assert log =~ "LOCAL_ADAPTORS is deprecated"
    end

    test "OPENFN_ADAPTORS_REPO with LOCAL_ADAPTORS=true becomes the local strategy's single repo path" do
      Dotenvy.source([
        %{"OPENFN_ADAPTORS_REPO" => "/path", "LOCAL_ADAPTORS" => "true"}
      ])

      Bootstrap.configure()

      assert get_env(:lightning, Lightning.Adaptors.Local)[:paths] == ["/path"]
    end

    test "comma-separated OPENFN_ADAPTORS_REPO parses into an ordered list" do
      Dotenvy.source([
        %{
          "OPENFN_ADAPTORS_REPO" => "/private/repo,/canonical/adaptors",
          "LOCAL_ADAPTORS" => "true"
        }
      ])

      Bootstrap.configure()

      assert get_env(:lightning, Lightning.Adaptors.Local)[:paths] == [
               "/private/repo",
               "/canonical/adaptors"
             ]
    end

    test "OPENFN_ADAPTORS_REPO drops empty segments and trims whitespace" do
      Dotenvy.source([
        %{
          "OPENFN_ADAPTORS_REPO" => "  /a  ,  ,/b ",
          "LOCAL_ADAPTORS" => "true"
        }
      ])

      Bootstrap.configure()

      assert get_env(:lightning, Lightning.Adaptors.Local)[:paths] == [
               "/a",
               "/b"
             ]
    end
  end

  describe "adaptors NPM upstream URLs" do
    test "no keys are forced when nothing is set, so sub-modules' own @default_* wins" do
      Dotenvy.source([%{}])
      Bootstrap.configure()

      npm = get_env(:lightning, Lightning.Adaptors.NPM)

      refute Keyword.has_key?(npm, :registry_url)
      refute Keyword.has_key?(npm, :jsdelivr_url)
      refute Keyword.has_key?(npm, :github_url)
      refute Keyword.has_key?(npm, :github_ref)
      refute Keyword.has_key?(npm, :http_timeout)
    end

    test "are overridden by the ADAPTORS_NPM_* env vars" do
      Dotenvy.source([
        %{
          "ADAPTORS_NPM_REGISTRY_URL" => "http://localhost:4874/npm",
          "ADAPTORS_NPM_JSDELIVR_URL" => "http://localhost:4874/jsdelivr",
          "ADAPTORS_NPM_GITHUB_URL" => "http://localhost:4874/github",
          "ADAPTORS_NPM_GITHUB_REF" => "some-feature-branch"
        }
      ])

      Bootstrap.configure()

      npm = get_env(:lightning, Lightning.Adaptors.NPM)

      assert npm[:registry_url] == "http://localhost:4874/npm"
      assert npm[:jsdelivr_url] == "http://localhost:4874/jsdelivr"
      assert npm[:github_url] == "http://localhost:4874/github"
      assert npm[:github_ref] == "some-feature-branch"
    end

    test "ADAPTORS_NPM_HTTP_TIMEOUT sets http_timeout when present" do
      Dotenvy.source([%{"ADAPTORS_NPM_HTTP_TIMEOUT" => "5000"}])

      Bootstrap.configure()

      npm = get_env(:lightning, Lightning.Adaptors.NPM)

      assert npm[:http_timeout] == 5000
    end

    test "ADAPTORS_NPM_HTTP_TIMEOUT does not force a 0ms timeout when set but empty" do
      Dotenvy.source([%{"ADAPTORS_NPM_HTTP_TIMEOUT" => ""}])

      Bootstrap.configure()

      npm = get_env(:lightning, Lightning.Adaptors.NPM)

      refute Keyword.has_key?(npm, :http_timeout)
    end
  end

  describe "adaptors refresh interval" do
    test "ADAPTORS_REFRESH_INTERVAL_SECONDS sets refresh_interval in ms" do
      Dotenvy.source([%{"ADAPTORS_REFRESH_INTERVAL_SECONDS" => "60"}])

      Bootstrap.configure()

      assert get_env(:lightning, Lightning.Adaptors)[:refresh_interval] ==
               60_000
    end

    test "ADAPTORS_REFRESH_INTERVAL_SECONDS accepts 0 to disable the scheduler" do
      Dotenvy.source([%{"ADAPTORS_REFRESH_INTERVAL_SECONDS" => "0"}])

      Bootstrap.configure()

      assert get_env(:lightning, Lightning.Adaptors)[:refresh_interval] == 0
    end

    test "is not forced when unset, so config/test.exs's 0 is left alone" do
      Dotenvy.source([%{}])

      Bootstrap.configure()

      refute Keyword.has_key?(
               get_env(:lightning, Lightning.Adaptors),
               :refresh_interval
             )
    end

    test "does not set refresh_interval when set but empty" do
      Dotenvy.source([%{"ADAPTORS_REFRESH_INTERVAL_SECONDS" => ""}])

      Bootstrap.configure()

      refute Keyword.has_key?(
               get_env(:lightning, Lightning.Adaptors),
               :refresh_interval
             )
    end
  end

  describe "adaptors strategy" do
    test "defaults to the npm strategy when nothing is set" do
      Dotenvy.source([%{}])
      Bootstrap.configure()

      assert get_env(:lightning, Lightning.Adaptors)[:strategy] ==
               Lightning.Adaptors.NPM
    end

    test "ADAPTORS_STRATEGY=npm explicitly selects the npm strategy" do
      Dotenvy.source([%{"ADAPTORS_STRATEGY" => "npm"}])
      Bootstrap.configure()

      assert get_env(:lightning, Lightning.Adaptors)[:strategy] ==
               Lightning.Adaptors.NPM
    end

    test "ADAPTORS_STRATEGY=local selects the local strategy" do
      Dotenvy.source([
        %{"ADAPTORS_STRATEGY" => "local", "ADAPTORS_LOCAL_REPO" => "/path"}
      ])

      Bootstrap.configure()

      assert get_env(:lightning, Lightning.Adaptors)[:strategy] ==
               Lightning.Adaptors.Local
    end

    test "ADAPTORS_STRATEGY is trimmed of surrounding whitespace" do
      Dotenvy.source([
        %{"ADAPTORS_STRATEGY" => "  local  ", "ADAPTORS_LOCAL_REPO" => "/path"}
      ])

      Bootstrap.configure()

      assert get_env(:lightning, Lightning.Adaptors)[:strategy] ==
               Lightning.Adaptors.Local
    end

    test "ADAPTORS_STRATEGY=local with no repo path configured raises" do
      assert_raise RuntimeError,
                   ~r/ADAPTORS_STRATEGY is set to local, but neither ADAPTORS_LOCAL_REPO nor/,
                   fn ->
                     Dotenvy.source([%{"ADAPTORS_STRATEGY" => "local"}])

                     Bootstrap.configure()
                   end
    end

    test "does not write :strategy into the real application env in :test, so config/test.exs's mock survives" do
      Process.put({Config, :opts}, {:test, ""})

      Dotenvy.source([%{}])
      Bootstrap.configure()

      refute Keyword.has_key?(
               get_env(:lightning, Lightning.Adaptors),
               :strategy
             )
    end

    test "raises when ADAPTORS_STRATEGY is not npm or local" do
      assert_raise RuntimeError, ~r/ADAPTORS_STRATEGY/, fn ->
        Dotenvy.source([%{"ADAPTORS_STRATEGY" => "bogus"}])
        Bootstrap.configure()
      end
    end

    test "LOCAL_ADAPTORS=true with ADAPTORS_STRATEGY unset back-compats to the local strategy and warns" do
      log =
        capture_log(fn ->
          Dotenvy.source([
            %{"LOCAL_ADAPTORS" => "true", "OPENFN_ADAPTORS_REPO" => "/path"}
          ])

          Bootstrap.configure()
        end)

      assert get_env(:lightning, Lightning.Adaptors)[:strategy] ==
               Lightning.Adaptors.Local

      assert log =~ "ADAPTORS_STRATEGY=local"
    end

    test "ADAPTORS_STRATEGY explicitly set wins over the LOCAL_ADAPTORS back-compat" do
      log =
        capture_log(fn ->
          Dotenvy.source([
            %{
              "LOCAL_ADAPTORS" => "true",
              "OPENFN_ADAPTORS_REPO" => "/path",
              "ADAPTORS_STRATEGY" => "npm"
            }
          ])

          Bootstrap.configure()
        end)

      assert get_env(:lightning, Lightning.Adaptors)[:strategy] ==
               Lightning.Adaptors.NPM

      refute log =~ "ADAPTORS_STRATEGY=local"
    end
  end

  describe "adaptors icons path" do
    test "is unset when ADAPTORS_ICONS_PATH is not set" do
      Dotenvy.source([%{}])
      Bootstrap.configure()

      # A present-but-nil :icon_path would defeat
      # Lightning.Adaptors.Config's own default, so the key must be absent
      # entirely, not just nil.
      refute Keyword.has_key?(
               get_env(:lightning, Lightning.Adaptors),
               :icon_path
             )
    end

    test "ADAPTORS_ICONS_PATH sets and expands the icon path" do
      Dotenvy.source([%{"ADAPTORS_ICONS_PATH" => "./tmp/icons"}])
      Bootstrap.configure()

      assert get_env(:lightning, Lightning.Adaptors)[:icon_path] ==
               Path.expand("./tmp/icons")
    end
  end

  describe "adaptors local strategy repo paths" do
    test "defaults to an empty list when nothing is set" do
      Dotenvy.source([%{}])
      Bootstrap.configure()

      assert get_env(:lightning, Lightning.Adaptors.Local)[:paths] == []
    end

    test "ADAPTORS_LOCAL_REPO parses a comma-separated list" do
      Dotenvy.source([%{"ADAPTORS_LOCAL_REPO" => "/a,/b"}])
      Bootstrap.configure()

      assert get_env(:lightning, Lightning.Adaptors.Local)[:paths] == [
               "/a",
               "/b"
             ]
    end

    test "OPENFN_ADAPTORS_REPO back-compats to the local strategy paths and warns when ADAPTORS_STRATEGY=local" do
      log =
        capture_log(fn ->
          Dotenvy.source([
            %{
              "OPENFN_ADAPTORS_REPO" => "/path",
              "ADAPTORS_STRATEGY" => "local"
            }
          ])

          Bootstrap.configure()
        end)

      assert get_env(:lightning, Lightning.Adaptors.Local)[:paths] == ["/path"]
      assert log =~ "ADAPTORS_LOCAL_REPO"
    end

    test "a blank ADAPTORS_LOCAL_REPO falls back to OPENFN_ADAPTORS_REPO instead of discarding it" do
      log =
        capture_log(fn ->
          Dotenvy.source([
            %{
              "OPENFN_ADAPTORS_REPO" => "/path",
              "ADAPTORS_LOCAL_REPO" => " , ",
              "ADAPTORS_STRATEGY" => "local"
            }
          ])

          Bootstrap.configure()
        end)

      assert get_env(:lightning, Lightning.Adaptors.Local)[:paths] == ["/path"]
      assert log =~ "ADAPTORS_LOCAL_REPO"
    end

    test "ADAPTORS_LOCAL_REPO takes precedence over OPENFN_ADAPTORS_REPO" do
      Dotenvy.source([
        %{
          "OPENFN_ADAPTORS_REPO" => "/old",
          "ADAPTORS_LOCAL_REPO" => "/new"
        }
      ])

      Bootstrap.configure()

      assert get_env(:lightning, Lightning.Adaptors.Local)[:paths] == ["/new"]
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

  describe "max_sandbox_nesting_depth" do
    test "defaults to 5" do
      Dotenvy.source([%{}])
      Bootstrap.configure()
      assert get_env(:lightning, :max_sandbox_nesting_depth) == 5
    end

    test "can be set to a different value via MAX_SANDBOX_NESTING_DEPTH" do
      Dotenvy.source([%{"MAX_SANDBOX_NESTING_DEPTH" => "10"}])
      Bootstrap.configure()
      assert get_env(:lightning, :max_sandbox_nesting_depth) == 10
    end
  end

  describe "apollo timeouts" do
    test "fall back to the compiled defaults" do
      Dotenvy.source([%{}])
      Bootstrap.configure()

      apollo = get_env(:lightning, :apollo)

      assert apollo[:connect_timeout] == 5_000
      assert apollo[:idle_timeout] == 30_000
      assert apollo[:request_timeout] == 300_000
    end

    # The names are the contract DEPLOYMENT.md documents; a typo in one would
    # fall back to its default and ship without a failure anywhere.
    test "each one is read from its own variable" do
      Dotenvy.source([
        %{
          "APOLLO_CONNECT_TIMEOUT_MS" => "1000",
          "APOLLO_IDLE_TIMEOUT_MS" => "2000",
          "APOLLO_REQUEST_TIMEOUT_MS" => "3000"
        }
      ])

      Bootstrap.configure()

      apollo = get_env(:lightning, :apollo)

      assert apollo[:connect_timeout] == 1_000
      assert apollo[:idle_timeout] == 2_000
      assert apollo[:request_timeout] == 3_000
    end

    test "records APOLLO_TIMEOUT only when it is set" do
      Dotenvy.source([%{}])
      Bootstrap.configure()
      refute get_env(:lightning, :apollo_timeout_env_still_set)

      Dotenvy.source([%{"APOLLO_TIMEOUT" => "120000"}])
      Bootstrap.configure()
      assert get_env(:lightning, :apollo_timeout_env_still_set)
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

  describe "log_queue_queries" do
    test "defaults to false" do
      Dotenvy.source([%{}])
      Bootstrap.configure()
      assert get_env(:lightning, :log_queue_queries) == false
    end

    test "can be enabled via env var" do
      Dotenvy.source([%{"LOG_QUEUE_QUERIES" => "true"}])
      Bootstrap.configure()
      assert get_env(:lightning, :log_queue_queries) == true
    end

    test "can be explicitly disabled" do
      Dotenvy.source([%{"LOG_QUEUE_QUERIES" => "false"}])
      Bootstrap.configure()
      assert get_env(:lightning, :log_queue_queries) == false
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

  describe "channel proxy egress (philter) configuration" do
    test "defaults to blocking private networks and does not override allowed_hosts" do
      Dotenvy.source([%{}])
      Bootstrap.configure()

      assert get_env(:philter, :block_private_networks) == true
      # allowed_hosts left untouched so base/dev/test defaults survive
      assert get_env(:philter, :allowed_hosts) == nil
    end

    test "CHANNEL_BLOCK_PRIVATE_NETWORKS toggles the flag" do
      for {value, expected} <- [
            {"false", false},
            {"no", false},
            {"true", true},
            {"yes", true}
          ] do
        Dotenvy.source([%{"CHANNEL_BLOCK_PRIVATE_NETWORKS" => value}])
        Bootstrap.configure()
        assert get_env(:philter, :block_private_networks) == expected
      end
    end

    test "CHANNEL_BLOCK_PRIVATE_NETWORKS rejects garbage input" do
      Dotenvy.source([%{"CHANNEL_BLOCK_PRIVATE_NETWORKS" => "nope"}])

      assert_raise ArgumentError, fn -> Bootstrap.configure() end
    end

    test "CHANNEL_ALLOWED_HOSTS sets a single normalised host" do
      Dotenvy.source([%{"CHANNEL_ALLOWED_HOSTS" => "Internal.Svc."}])
      Bootstrap.configure()

      assert get_env(:philter, :allowed_hosts) == ["internal.svc"]
    end

    test "CHANNEL_ALLOWED_HOSTS parses a comma-separated list" do
      Dotenvy.source([
        %{"CHANNEL_ALLOWED_HOSTS" => "internal.svc, api.example.org"}
      ])

      Bootstrap.configure()

      assert get_env(:philter, :allowed_hosts) ==
               ["internal.svc", "api.example.org"]
    end

    test "CHANNEL_ALLOWED_HOSTS rejects a malformed entry" do
      Dotenvy.source([
        %{"CHANNEL_ALLOWED_HOSTS" => "internal.svc,https://bad.one"}
      ])

      assert_raise ArgumentError, fn -> Bootstrap.configure() end
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

  @rsa_private_key """
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

  describe "worker private key" do
    test "accepts the private key in the forms operators deliver" do
      for value <- operator_forms(@rsa_private_key) do
        reconfigure(%{"WORKER_RUNS_PRIVATE_KEY" => value})

        assert get_env(:lightning, :workers)[:private_key] == @rsa_private_key
      end
    end

    for {refusal, value_name, message} <- [
          {:empty, "an empty value",
           "WORKER_RUNS_PRIVATE_KEY is empty. Set it to the RSA private key that signs run tokens."},
          {:quoted, "a value in quotes",
           "WORKER_RUNS_PRIVATE_KEY starts and ends with a quote character. docker run --env-file and Compose's env_file with format: raw keep quotes as part of the value; remove them."},
          {:not_pem, "a value that is not a PEM",
           "WORKER_RUNS_PRIVATE_KEY is not a PEM key. Set it to the contents of the private key file, BEGIN and END lines included, or to that file base64-encoded."},
          {:truncated, "a PEM cut off before its END line",
           "WORKER_RUNS_PRIVATE_KEY has a BEGIN RSA PRIVATE KEY line but no END line, so only part of the key arrived. A file that holds one variable per line keeps only the first line of a multi-line value; base64-encode the PEM file on one line instead: openssl base64 -A -in FILE"},
          {:damaged, "a PEM whose body is not base64",
           "WORKER_RUNS_PRIVATE_KEY holds a PEM block whose body is not valid base64. Copy the private key file again."},
          {:several_blocks, "more than one PEM block",
           "WORKER_RUNS_PRIVATE_KEY holds more than one PEM block. Set it to the private key alone."},
          {:unknown_label, "a BEGIN line that lost its closing dashes",
           "WORKER_RUNS_PRIVATE_KEY has a BEGIN line that names no key type Lightning reads. Copy the private key file again, BEGIN and END lines included."},
          {:public_key, "an RSA public key",
           "WORKER_RUNS_PRIVATE_KEY holds a public key. Set it to the RSA private key that signs run tokens; its public key goes in the worker's WORKER_LIGHTNING_PUBLIC_KEY."},
          {:not_rsa, "a key that is not RSA",
           "WORKER_RUNS_PRIVATE_KEY is not an RSA key. Run tokens are signed with RS256, which needs an RSA private key."},
          {:not_a_key, "a PEM block that holds no key",
           "WORKER_RUNS_PRIVATE_KEY holds a PEM block that is not a key Lightning can read. Set it to the RSA private key that signs run tokens."}
        ] do
      test "stops the boot on #{value_name} and says what to set instead" do
        for value <- refused_pem_values(unquote(refusal)) do
          error =
            assert_raise RuntimeError, fn ->
              reconfigure(%{"WORKER_RUNS_PRIVATE_KEY" => value})
            end

          refute_quotes_key(error.message, value)

          assert error.message == """
                 #{unquote(message)}

                 You can generate new worker keys using: mix lightning.gen_worker_keys
                 """
        end
      end
    end
  end

  describe "GitHub App private key" do
    test "accepts the private key in the forms operators deliver" do
      for value <- operator_forms(@rsa_private_key) do
        reconfigure(%{"GITHUB_CERT" => value})

        assert get_env(:lightning, :github_app)[:cert] == @rsa_private_key
      end
    end

    test "turns GitHub sync off on an empty value, even when config holds a cert" do
      for value <- ["", "   "] do
        reconfigure(%{"GITHUB_CERT" => value})

        assert get_env(:lightning, :github_app)[:cert] == nil
      end
    end

    for {refusal, value_name, message} <- [
          {:quoted, "a value in quotes",
           "GITHUB_CERT starts and ends with a quote character. docker run --env-file and Compose's env_file with format: raw keep quotes as part of the value; remove them."},
          {:not_pem, "a value that is not a PEM",
           "GITHUB_CERT is not a PEM key. Set it to the contents of the GitHub App's private key file, BEGIN and END lines included, or to that file base64-encoded."},
          {:truncated, "a PEM cut off before its END line",
           "GITHUB_CERT has a BEGIN RSA PRIVATE KEY line but no END line, so only part of the key arrived. A file that holds one variable per line keeps only the first line of a multi-line value; base64-encode the PEM file on one line instead: openssl base64 -A -in private-key.pem"},
          {:damaged, "a PEM whose body is not base64",
           "GITHUB_CERT holds a PEM block whose body is not valid base64. Copy the GitHub App's private key file again."},
          {:several_blocks, "more than one PEM block",
           "GITHUB_CERT holds more than one PEM block. Set it to the GitHub App's private key alone."},
          {:unknown_label, "a BEGIN line that lost its closing dashes",
           "GITHUB_CERT has a BEGIN line that names no key type Lightning reads. Copy the GitHub App's private key file again, BEGIN and END lines included."}
        ] do
      test "stops the boot on #{value_name} and says what to set instead" do
        for value <- refused_pem_values(unquote(refusal)) do
          error =
            assert_raise RuntimeError, fn ->
              reconfigure(%{"GITHUB_CERT" => value})
            end

          refute_quotes_key(error.message, value)
          assert error.message == unquote(message)
        end
      end
    end
  end

  describe "service account" do
    @service_account_pem """
    -----BEGIN PUBLIC KEY-----
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0vx7agoebGcQSuuPiLJX
    ZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tS
    oc/BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ/2W+5JsGY4Hc5n9yBXArwl93lqt
    7/RN5w6Cf0h4QyQ5v+65YGjQR0/FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0
    zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt+bFTWhAI4vMQFh6WeZu0f
    M4lFd2NcRwr3XPksINHaQ+G/xBniIqbw0Ls1jF44+csFCur+kEgU8awapJzKnqDK
    gwIDAQAB
    -----END PUBLIC KEY-----
    """

    test "registers one service account and turns off first setup" do
      reconfigure(%{
        "SERVICE_ACCOUNT_PUBLIC_KEY" =>
          Base.encode64(@service_account_pem, padding: false)
      })

      assert %Lightning.ServiceAccount{
               id: "NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs"
             } = get_env(:lightning, :service_account)

      assert get_env(:lightning, :allow_first_setup) == false
    end

    test "schedules the pruning of seen assertions" do
      reconfigure(%{})

      crontab = get_env(:lightning, Oban)[:plugins][Oban.Plugins.Cron][:crontab]

      assert Enum.any?(
               crontab,
               &match?({_, Lightning.ServiceAccount.Assertion}, &1)
             )
    end

    test "registers none and leaves first setup on when unset" do
      reconfigure(%{})

      assert get_env(:lightning, :service_account) == nil
      assert get_env(:lightning, :allow_first_setup) == true
    end

    test "accepts the public key in the forms operators deliver" do
      for value <- operator_forms(@service_account_pem) do
        reconfigure(%{"SERVICE_ACCOUNT_PUBLIC_KEY" => value})

        assert %Lightning.ServiceAccount{
                 id: "NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs"
               } = get_env(:lightning, :service_account)
      end
    end

    for bits <- [2048, 4096] do
      test "accepts a #{bits}-bit RSA key" do
        reconfigure(%{
          "SERVICE_ACCOUNT_PUBLIC_KEY" => encoded_public_key(unquote(bits))
        })

        assert %Lightning.ServiceAccount{} =
                 get_env(:lightning, :service_account)
      end
    end

    for {refusal, value_name, message} <- [
          {:empty, "an empty value",
           "SERVICE_ACCOUNT_PUBLIC_KEY is empty. Set it to the service account's public key, or unset it to run without a service account."},
          {:quoted, "a value in quotes",
           "SERVICE_ACCOUNT_PUBLIC_KEY starts and ends with a quote character. docker run --env-file and Compose's env_file with format: raw keep quotes as part of the value; remove them."},
          {:not_pem, "a value that is not a PEM",
           "SERVICE_ACCOUNT_PUBLIC_KEY is not a PEM key. Set it to the contents of the public key file, BEGIN and END lines included, or to that file base64-encoded."},
          {:truncated, "a PEM cut off before its END line",
           "SERVICE_ACCOUNT_PUBLIC_KEY has a BEGIN PUBLIC KEY line but no END line, so only part of the key arrived. A file that holds one variable per line keeps only the first line of a multi-line value; base64-encode the PEM file on one line instead: openssl base64 -A -in sa_public.pem"},
          {:damaged, "a PEM whose body is not base64",
           "SERVICE_ACCOUNT_PUBLIC_KEY holds a PEM block whose body is not valid base64. Copy the public key file again."},
          {:several_blocks, "more than one PEM block",
           "SERVICE_ACCOUNT_PUBLIC_KEY holds more than one PEM block. Set it to the public key alone."},
          {:unknown_label, "a BEGIN line that lost its closing dashes",
           "SERVICE_ACCOUNT_PUBLIC_KEY has a BEGIN line that names no key type Lightning reads. Copy the public key file again, BEGIN and END lines included."},
          {:private_key, "a private key",
           "SERVICE_ACCOUNT_PUBLIC_KEY holds a private key. Set it to the public key instead: openssl pkey -in sa_private.pem -pubout"},
          {:not_rsa, "a key that is not RSA",
           "SERVICE_ACCOUNT_PUBLIC_KEY is not an RSA key. It must be an RSA public key of at least 2048 bits."},
          {:too_small, "an RSA key shorter than 2048 bits",
           "SERVICE_ACCOUNT_PUBLIC_KEY is a 1024-bit RSA key. Generate an RSA key pair of at least 2048 bits."},
          {:not_a_key, "a PEM block that holds no key",
           "SERVICE_ACCOUNT_PUBLIC_KEY holds a PEM block that is not a key Lightning can read. It must be an RSA public key of at least 2048 bits."}
        ] do
      test "stops the boot on #{value_name} and says what to set instead" do
        for value <- refused_service_account_keys(unquote(refusal)) do
          error =
            assert_raise RuntimeError, fn ->
              reconfigure(%{"SERVICE_ACCOUNT_PUBLIC_KEY" => value})
            end

          refute_quotes_key(error.message, value)
          assert error.message == unquote(message)
        end
      end
    end
  end

  describe "live debugger (dev)" do
    test "does not set :ip or :external_url by default" do
      Dotenvy.source([%{}])
      Bootstrap.configure()

      assert get_env(:live_debugger, :ip) == nil
      assert get_env(:live_debugger, :external_url) == nil
    end

    test "LIVE_DEBUGGER_IP is parsed into a tuple" do
      Dotenvy.source([%{"LIVE_DEBUGGER_IP" => "0.0.0.0"}])
      Bootstrap.configure()

      assert get_env(:live_debugger, :ip) == {0, 0, 0, 0}
    end

    test "LIVE_DEBUGGER_EXTERNAL_URL is stored as a string" do
      Dotenvy.source([
        %{"LIVE_DEBUGGER_EXTERNAL_URL" => "http://dev-elixir.local:4007"}
      ])

      Bootstrap.configure()

      assert get_env(:live_debugger, :external_url) ==
               "http://dev-elixir.local:4007"
    end

    test "both env vars can be set together" do
      Dotenvy.source([
        %{
          "LIVE_DEBUGGER_IP" => "0.0.0.0",
          "LIVE_DEBUGGER_EXTERNAL_URL" => "http://dev-elixir.local:4007"
        }
      ])

      Bootstrap.configure()

      assert get_env(:live_debugger, :ip) == {0, 0, 0, 0}

      assert get_env(:live_debugger, :external_url) ==
               "http://dev-elixir.local:4007"
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

  defp linux?, do: match?({:unix, :linux}, :os.type())

  defp dead_socket_options(tcp_user_timeout) do
    if linux?() do
      [
        {:keepalive, true},
        {:raw, 6, 4, <<5::32-native>>},
        {:raw, 6, 5, <<5::32-native>>},
        {:raw, 6, 18, <<tcp_user_timeout::32-native>>}
      ]
    else
      []
    end
  end

  defp repo_opt(key) do
    :lightning
    |> get_env(Lightning.Repo)
    |> Keyword.get(key)
  end

  defp encoded_public_key(bits) do
    bits |> public_pem() |> Base.encode64(padding: false)
  end

  defp public_pem(bits) do
    {_, pem} =
      {:rsa, bits}
      |> JOSE.JWK.generate_key()
      |> JOSE.JWK.to_public()
      |> JOSE.JWK.to_pem()

    pem
  end

  defp operator_forms(pem) do
    encoded = Base.encode64(pem)

    wrapped =
      encoded
      |> String.graphemes()
      |> Enum.chunk_every(76)
      |> Enum.map_join("\n", &Enum.join/1)

    [
      pem,
      String.replace(pem, "\n", "\r\n"),
      String.replace(pem, "\n", "\\n"),
      wrapped,
      encoded,
      Base.encode64(pem, padding: false)
    ]
  end

  defp refused_pem_values(:empty), do: ["", "   "]

  defp refused_pem_values(:quoted),
    do: [~s("#{Base.encode64(@rsa_private_key)}")]

  defp refused_pem_values(:not_pem),
    do: ["garbage", Base.encode64("not-a-pem-key-at-all", padding: false)]

  defp refused_pem_values(:truncated),
    do: [@rsa_private_key |> Base.encode64() |> String.slice(0, 76)]

  defp refused_pem_values(:damaged) do
    pem = """
    -----BEGIN PRIVATE KEY-----
    This is not valid base64 encoded key data!!!
    -----END PRIVATE KEY-----
    """

    [pem, Base.encode64(pem, padding: false)]
  end

  defp refused_pem_values(:several_blocks),
    do: [@rsa_private_key <> @rsa_private_key]

  defp refused_pem_values(:unknown_label),
    do: begin_line_without_closing_dashes(@rsa_private_key)

  defp refused_pem_values(:public_key) do
    {_, pkcs1} = @service_account_pem |> JOSE.JWK.from_pem() |> JOSE.JWK.to_pem()
    [@service_account_pem, Base.encode64(@service_account_pem), pkcs1]
  end

  defp refused_pem_values(:not_rsa) do
    ed25519 = """
    -----BEGIN PRIVATE KEY-----
    MC4CAQAwBQYDK2VwBCIEIGCa7P/7SXCoLXsmDPoRcfqU4aGVWkgFb8pWNVSPUNzR
    -----END PRIVATE KEY-----
    """

    ec = """
    -----BEGIN EC PRIVATE KEY-----
    MHcCAQEEIIGlRHKQphLqMvj/+/P5wXDqQj8u1fJzJqNQKJvqPRq9oAoGCCqGSM49
    AwEHoUQDQgAEgTyTZ5fzGh4x4L3KXqjJLLQI4j3TqvLUqh3ScxqL5qJqvLUqh3Sc
    xqL5qJqvLUqh3ScxqL5qJqvLUqh3ScxqLw==
    -----END EC PRIVATE KEY-----
    """

    [Base.encode64(ed25519, padding: false), ec]
  end

  defp refused_pem_values(:not_a_key) do
    body = Base.encode64(:crypto.strong_rand_bytes(64))
    pem = "-----BEGIN PRIVATE KEY-----\n#{body}\n-----END PRIVATE KEY-----\n"
    [pem, Base.encode64(pem)]
  end

  defp refused_service_account_keys(:empty), do: ["", "   "]

  defp refused_service_account_keys(:quoted),
    do: [~s("#{Base.encode64(@service_account_pem)}")]

  defp refused_service_account_keys(:not_pem),
    do: ["garbage", Base.encode64("not a key", padding: false)]

  defp refused_service_account_keys(:truncated),
    do: [@service_account_pem |> Base.encode64() |> String.slice(0, 76)]

  defp refused_service_account_keys(:damaged),
    do: [String.replace(@service_account_pem, "\nMIIB", "\n!IIB")]

  defp refused_service_account_keys(:several_blocks),
    do: [@service_account_pem <> @service_account_pem]

  defp refused_service_account_keys(:unknown_label),
    do: begin_line_without_closing_dashes(@service_account_pem)

  defp refused_service_account_keys(:private_key) do
    {_, pem} = JOSE.JWK.generate_key({:rsa, 2048}) |> JOSE.JWK.to_pem()
    [pem]
  end

  defp refused_service_account_keys(:not_rsa) do
    [
      """
      -----BEGIN PUBLIC KEY-----
      MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE7aBIw3Zoq85rGk4EC+MBrElUg/Ym
      rmZUyENZbakktntXDTlHKCREjMuHitBVcQg2xZJL+9zNCbL2Uaj3AkzIxQ==
      -----END PUBLIC KEY-----
      """
    ]
  end

  defp refused_service_account_keys(:too_small), do: [encoded_public_key(1024)]

  defp refused_service_account_keys(:not_a_key) do
    body = Base.encode64(:crypto.strong_rand_bytes(64))
    ["-----BEGIN PUBLIC KEY-----\n#{body}\n-----END PUBLIC KEY-----\n"]
  end

  defp begin_line_without_closing_dashes(pem) do
    [begin_line | rest] = String.split(pem, "\n", trim: true)
    lines = [String.trim_trailing(begin_line, "-") | rest]
    on_one_line = Enum.join(lines, " ")

    [
      on_one_line,
      Enum.join(lines, "\t"),
      Enum.join(lines, "\\n"),
      Base.encode64(on_one_line)
    ]
  end

  # Checks 16-character slices rather than the whole value, so a message that
  # quotes part of a key fails too, whether the key arrived as text or base64.
  defp refute_quotes_key(message, value) do
    texts =
      case Base.decode64(value, ignore: :whitespace, padding: false) do
        {:ok, decoded} -> [value, decoded]
        :error -> [value]
      end

    for text <- texts,
        [run] <- Regex.scan(~r/[A-Za-z0-9+\/=]{16,}/, text),
        offset <- 0..(byte_size(run) - 16) do
      slice = binary_part(run, offset, 16)
      refute String.contains?(message, slice), "message quotes #{slice}"
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
