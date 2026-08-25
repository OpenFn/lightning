defmodule Lightning.Adaptors.ConfigTest do
  use ExUnit.Case, async: true

  alias Lightning.Adaptors.Config

  @parent_key Lightning.Adaptors

  describe "current_source/0" do
    test "returns :local when strategy is Lightning.Adaptors.Local" do
      put_parent(:strategy, Lightning.Adaptors.Local)

      assert Config.current_source() == :local
    end

    test "returns :npm for any other strategy module" do
      put_parent(:strategy, Lightning.Adaptors.NPM)
      assert Config.current_source() == :npm

      put_parent(:strategy, SomeOther.Strategy)
      assert Config.current_source() == :npm
    end
  end

  describe "icon_path/0" do
    test "resolves a {:tmp, suffix} tuple against System.tmp_dir!/0" do
      put_parent(:icon_path, {:tmp, "lightning/adaptor_icons_under_test"})

      assert Config.icon_path() ==
               Path.join(System.tmp_dir!(), "lightning/adaptor_icons_under_test")
    end

    test "returns a plain binary path verbatim" do
      put_parent(:icon_path, "/var/lib/lightning/adaptor_icons")

      assert Config.icon_path() == "/var/lib/lightning/adaptor_icons"
    end
  end

  describe "strategy_opts/1" do
    test "reads the strategy module's own Application key" do
      put_strategy_opts(SomeStrategy.Module, repo_path: "/tmp/local-adaptors")

      assert Config.strategy_opts(SomeStrategy.Module) ==
               [repo_path: "/tmp/local-adaptors"]
    end

    test "returns [] when the strategy module's Application key is unset" do
      clear_strategy_opts(UnsetStrategy.Module)

      assert Config.strategy_opts(UnsetStrategy.Module) == []
    end
  end

  describe "defaults when unset" do
    test "refresh_interval/0 defaults to :timer.hours(1)" do
      delete_parent_key(:refresh_interval)

      assert Config.refresh_interval() == :timer.hours(1)
    end

    test "cache_timeout_ms/0 defaults to 15_000" do
      delete_parent_key(:cache_timeout_ms)

      assert Config.cache_timeout_ms() == 15_000
    end
  end

  defp put_parent(key, value) do
    original = Application.get_env(:lightning, @parent_key, [])

    Application.put_env(
      :lightning,
      @parent_key,
      Keyword.put(original, key, value)
    )

    on_exit(fn ->
      Application.put_env(:lightning, @parent_key, original)
    end)
  end

  defp delete_parent_key(key) do
    original = Application.get_env(:lightning, @parent_key, [])
    Application.put_env(:lightning, @parent_key, Keyword.delete(original, key))

    on_exit(fn ->
      Application.put_env(:lightning, @parent_key, original)
    end)
  end

  defp put_strategy_opts(mod, value) do
    original = Application.get_env(:lightning, mod, :__unset__)
    Application.put_env(:lightning, mod, value)

    on_exit(fn ->
      restore_app_env(mod, original)
    end)
  end

  defp clear_strategy_opts(mod) do
    original = Application.get_env(:lightning, mod, :__unset__)
    Application.delete_env(:lightning, mod)

    on_exit(fn ->
      restore_app_env(mod, original)
    end)
  end

  defp restore_app_env(mod, :__unset__),
    do: Application.delete_env(:lightning, mod)

  defp restore_app_env(mod, value),
    do: Application.put_env(:lightning, mod, value)
end
