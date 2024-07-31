defmodule Lightning.Config.BootstrapTest do
  use ExUnit.Case, async: true

  alias Lightning.Config.Bootstrap

  @opts_key {Config, :opts}
  @config_key {Config, :config}
  @imports_key {Config, :imports}

  # Setup some process keys to behave like the Config module when a config is
  # evaluated
  setup do
    Process.put(@opts_key, {:prod, ""})
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

  # A helper function to get a value from the process dictionary
  # that is stored by the Config module.
  defp get_env(app, key) do
    Process.get(@config_key)
    |> Keyword.get(app)
    |> Enum.find(&match?({^key, _}, &1))
    |> case do
      {_, value} -> value
      nil -> nil
    end
  end
end
