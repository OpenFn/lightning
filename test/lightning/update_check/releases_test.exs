defmodule Lightning.UpdateCheck.ReleasesTest do
  use ExUnit.Case, async: true

  alias Lightning.UpdateCheck.Releases

  describe "stable_tags/1" do
    test "keeps only full releases, newest first" do
      tags = [
        "latest",
        "edge",
        "v2.9.0",
        "v2.20.0-pre",
        "v2.19.2",
        "v2-sync-pre1",
        "pre-otp-rebase-5106",
        "v2.10.0",
        "2.19.1"
      ]

      assert Releases.stable_tags(tags) |> Enum.map(&elem(&1, 0)) ==
               ["v2.19.2", "2.19.1", "v2.10.0", "v2.9.0"]
    end

    test "returns an empty list when there are no releases" do
      assert Releases.stable_tags(["latest", "edge", "v3.0.0-pre"]) == []
    end
  end

  describe "newer?/2" do
    test "compares the latest release with the running version" do
      latest = Version.parse!("2.19.2")

      assert Releases.newer?(latest, "2.19.1")
      assert Releases.newer?(latest, "2.19.2-pre")
      refute Releases.newer?(latest, "2.19.2")
      refute Releases.newer?(latest, "2.20.0-pre")
      refute Releases.newer?(latest, "2.20.0")
    end

    test "accepts a running version with a leading v" do
      latest = Version.parse!("2.19.2")

      assert Releases.newer?(latest, "v2.19.1")
      refute Releases.newer?(latest, "v2.19.2")
    end

    test "is false when either side is unknown" do
      refute Releases.newer?(nil, "2.19.1")
      refute Releases.newer?(Version.parse!("2.19.2"), "not-a-version")
      refute Releases.newer?(Version.parse!("2.19.2"), nil)
    end
  end
end
