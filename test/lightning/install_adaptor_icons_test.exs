defmodule Lightning.InstallAdaptorIconsTest do
  use Lightning.DataCase, async: false

  alias Mix.Tasks.Lightning.InstallAdaptorIcons

  setup do
    Mix.shell(Mix.Shell.Process)

    Lightning.AdaptorData.Cache.invalidate("icon_manifest")
    Lightning.AdaptorData.Cache.invalidate("icon")
    :ok
  end

  @tag :capture_log
  test "refreshes icon manifest and reports count" do
    InstallAdaptorIcons.run([])

    assert_receive {:mix_shell, :info, [msg]}
    assert msg =~ "Adaptor icons refreshed successfully."
    assert msg =~ "adaptors in manifest."

    # Verify manifest was stored in DB
    assert {:ok, entry} =
             Lightning.AdaptorData.get("icon_manifest", "all")

    assert entry.content_type == "application/json"
    manifest = Jason.decode!(entry.data)
    assert is_map(manifest)
  end
end
