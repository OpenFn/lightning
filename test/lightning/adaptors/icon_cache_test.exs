defmodule Lightning.Adaptors.IconCacheTest do
  use ExUnit.Case, async: false

  alias Lightning.Adaptors.IconCache

  @parent_key Lightning.Adaptors

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "lightning_icon_cache_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)

    original = Application.get_env(:lightning, @parent_key, [])

    Application.put_env(
      :lightning,
      @parent_key,
      Keyword.put(original, :icon_path, root)
    )

    on_exit(fn ->
      Application.put_env(:lightning, @parent_key, original)
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  @sha :crypto.hash(:sha256, "x")
  @sha8 @sha |> Base.encode16(case: :lower) |> binary_part(0, 8)

  describe "path/5" do
    test "joins Config.icon_path with source/name/shape.sha8.ext", %{root: root} do
      assert IconCache.path(:npm, "salesforce", :square, "png", @sha) ==
               Path.join([root, "npm", "salesforce", "square.#{@sha8}.png"])
    end

    test "handles names containing a slash like @openfn/language-foo", %{
      root: root
    } do
      assert IconCache.path(:npm, "@openfn/language-foo", :square, "png", @sha) ==
               Path.join([
                 root,
                 "npm",
                 "@openfn",
                 "language-foo",
                 "square.#{@sha8}.png"
               ])
    end

    test "source-partitions paths for the same name", %{root: root} do
      npm_path = IconCache.path(:npm, "salesforce", :square, "png", @sha)
      local_path = IconCache.path(:local, "salesforce", :square, "png", @sha)

      assert npm_path ==
               Path.join([root, "npm", "salesforce", "square.#{@sha8}.png"])

      assert local_path ==
               Path.join([root, "local", "salesforce", "square.#{@sha8}.png"])

      refute npm_path == local_path
    end

    test "is pure — nothing is created on disk", %{root: root} do
      _ = IconCache.path(:npm, "never-written", :rectangle, "svg", @sha)

      assert File.ls!(root) == []
    end
  end

  describe "cached?/5" do
    test "returns false when the file does not exist" do
      refute IconCache.cached?(:npm, "definitely-missing", :square, "png", @sha)
    end

    test "returns true after write!/6 places bytes for that sha" do
      write("cached-pkg", "x")

      assert IconCache.cached?(:npm, "cached-pkg", :square, "png", @sha)
    end

    test "returns false when only another sha is on disk" do
      write("stale-pkg", "old")

      refute IconCache.cached?(:npm, "stale-pkg", :square, "png", @sha)
    end

    test "stays source-partitioned: a write to :npm doesn't satisfy :local" do
      write("split-pkg", "x")

      assert IconCache.cached?(:npm, "split-pkg", :square, "png", @sha)
      refute IconCache.cached?(:local, "split-pkg", :square, "png", @sha)
    end
  end

  describe "write!/6" do
    test "writes bytes and returns the path they can be read back from" do
      bytes = :crypto.strong_rand_bytes(2_048)

      path = write("round-trip", bytes)

      assert path ==
               IconCache.path(
                 :npm,
                 "round-trip",
                 :square,
                 "png",
                 :crypto.hash(:sha256, bytes)
               )

      assert File.read!(path) == bytes
    end

    test "removes the superseded file for the same shape and extension" do
      old_path = write("rotated", "first")
      new_path = write("rotated", "second")

      refute old_path == new_path
      assert File.read!(new_path) == "second"
      refute File.exists?(old_path)
    end

    test "removes the superseded file even when the extension changed" do
      old_path = write("re-ext", "first")

      new_path =
        IconCache.write!(
          :npm,
          "re-ext",
          :square,
          "svg",
          "second",
          :crypto.hash(:sha256, "second")
        )

      assert String.ends_with?(new_path, ".svg")
      assert File.exists?(new_path)
      refute File.exists?(old_path)
    end

    test "removes a pre-sha legacy file for the same shape" do
      new_path = write("legacy", "bytes")
      legacy = Path.join(Path.dirname(new_path), "square.png")
      File.write!(legacy, "old")

      write("legacy", "bytes")

      refute File.exists?(legacy)
      assert File.exists?(new_path)
    end

    test "leaves the other shape alone when sweeping" do
      square = write("two-shapes", "sq")
      rectangle = write("two-shapes", "rect", :rectangle)

      assert File.exists?(square)
      assert File.exists?(rectangle)
    end

    test "creates intermediate directories for scoped names" do
      path = write("@openfn/language-http", "abc")

      assert File.read!(path) == "abc"
    end

    test "is atomic: concurrent writers produce no half-written file and no leftover temps",
         %{root: root} do
      payloads =
        for i <- 0..49 do
          :crypto.strong_rand_bytes(16_384) <> <<i::32>>
        end

      paths =
        payloads
        |> Enum.map(fn bytes ->
          Task.async(fn -> write("concurrent", bytes) end)
        end)
        |> Task.await_many(10_000)

      dir = Path.dirname(hd(paths))
      on_disk = File.ls!(dir)

      refute on_disk == [], "the sweep left nothing behind"

      for file <- on_disk do
        refute String.ends_with?(file, ".tmp"),
               "leftover temp files in #{dir}: #{inspect(on_disk)}"

        assert File.read!(Path.join(dir, file)) in payloads,
               "#{file} matches no written payload — write was not atomic"
      end

      _ = root
    end
  end

  describe "path/5 name validation" do
    test "refuses names that would escape the cache root", %{root: root} do
      for name <- ["..", "../..", "@openfn/..", ".hidden", "@../evil"] do
        assert_raise ArgumentError, ~r/unsafe adaptor name/, fn ->
          IconCache.path(:npm, name, :square, "png", <<0::256>>)
        end

        assert_raise ArgumentError, fn -> write(name, "bytes") end
      end

      assert File.ls!(root) == []
    end
  end

  defp write(name, bytes, shape \\ :square) do
    IconCache.write!(
      :npm,
      name,
      shape,
      "png",
      bytes,
      :crypto.hash(:sha256, bytes)
    )
  end
end
