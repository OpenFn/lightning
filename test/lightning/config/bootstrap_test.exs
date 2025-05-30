defmodule Lightning.Config.BootstrapTest do
  use ExUnit.Case, async: true

  alias Lightning.Config.Bootstrap

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
      Process.put(@opts_key, {:prod, ""})

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
      # Defaults to 60 seconds if idle_timeout is not set
      Dotenvy.source([
        %{"SECRET_KEY_BASE" => "Foo"},
        %{"DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE"}
      ])

      Bootstrap.configure()

      idle_timeout =
        :lightning
        |> get_env(LightningWeb.Endpoint)
        |> get_in([:http, :protocol_options, :idle_timeout])

      assert idle_timeout == 60_000

      # Default to 60 seconds if idle timeout is not an integer
      Dotenvy.source([
        %{"IDLE_TIMEOUT" => ""},
        %{"SECRET_KEY_BASE" => "Foo"},
        %{"DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE"}
      ])

      Bootstrap.configure()

      idle_timeout =
        :lightning
        |> get_env(LightningWeb.Endpoint)
        |> get_in([:http, :protocol_options, :idle_timeout])

      assert idle_timeout == 60_000

      # Converts provided value to milliseconds
      Dotenvy.source([
        %{"IDLE_TIMEOUT" => "240"},
        %{"SECRET_KEY_BASE" => "Foo"},
        %{"DATABASE_URL" => "ecto://USER:PASS@HOST/DATABASE"}
      ])

      Bootstrap.configure()

      idle_timeout =
        :lightning
        |> get_env(LightningWeb.Endpoint)
        |> get_in([:http, :protocol_options, :idle_timeout])

      assert idle_timeout == 240_000
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

  # A helper function to get a value from the process dictionary
  # that is stored by the Config module.
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
end
