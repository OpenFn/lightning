defmodule Lightning.AdaptorIconsTest do
  use Lightning.DataCase, async: false

  import Mox

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "adaptor_icons_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    previous = Application.get_env(:lightning, :adaptor_icons_path)
    Application.put_env(:lightning, :adaptor_icons_path, tmp_dir)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:lightning, :adaptor_icons_path, previous),
        else: Application.delete_env(:lightning, :adaptor_icons_path)

      File.rm_rf(tmp_dir)
    end)

    %{target_dir: tmp_dir}
  end

  describe "refresh/0" do
    test "returns error when HTTP request fails" do
      Mox.expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:error, :econnrefused}
      end)

      assert {:error, :econnrefused} = Lightning.AdaptorIcons.refresh()
    end

    test "returns error on non-200 HTTP status" do
      Mox.expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %Tesla.Env{status: 500, body: ""}}
      end)

      assert {:error, "HTTP 500"} = Lightning.AdaptorIcons.refresh()
    end

    test "cleans up temp directory on failure" do
      tmp_base = Path.join(System.tmp_dir!(), "lightning-adaptor")

      entries_before =
        if File.exists?(tmp_base), do: File.ls!(tmp_base), else: []

      Mox.expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:error, :timeout}
      end)

      Lightning.AdaptorIcons.refresh()

      # No new temp dirs should be left after refresh
      entries_after = if File.exists?(tmp_base), do: File.ls!(tmp_base), else: []
      new_entries = entries_after -- entries_before

      assert new_entries == [],
             "Expected no new temp dirs, found: #{inspect(new_entries)}"
    end
  end
end
