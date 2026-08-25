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

  describe "path/4" do
    test "joins Config.icon_path with source/name/shape.ext", %{root: root} do
      assert IconCache.path(:npm, "salesforce", :square, "png") ==
               Path.join([root, "npm", "salesforce", "square.png"])
    end

    test "handles names containing a slash like @openfn/language-foo", %{
      root: root
    } do
      assert IconCache.path(:npm, "@openfn/language-foo", :square, "png") ==
               Path.join([
                 root,
                 "npm",
                 "@openfn",
                 "language-foo",
                 "square.png"
               ])
    end

    test "source-partitions paths for the same name", %{root: root} do
      npm_path = IconCache.path(:npm, "salesforce", :square, "png")
      local_path = IconCache.path(:local, "salesforce", :square, "png")

      assert npm_path == Path.join([root, "npm", "salesforce", "square.png"])

      assert local_path ==
               Path.join([root, "local", "salesforce", "square.png"])

      refute npm_path == local_path
    end

    test "is pure — nothing is created on disk", %{root: root} do
      _ = IconCache.path(:npm, "never-written", :rectangle, "svg")

      assert File.ls!(root) == []
    end
  end

  describe "cached?/4" do
    test "returns false when the file does not exist" do
      refute IconCache.cached?(:npm, "definitely-missing", :square, "png")
    end

    test "returns true after write!/5 places the file" do
      {:ok, _sha} = IconCache.write!(:npm, "cached-pkg", :square, "png", "x")

      assert IconCache.cached?(:npm, "cached-pkg", :square, "png")
    end

    test "stays source-partitioned: a write to :npm doesn't satisfy :local" do
      {:ok, _} = IconCache.write!(:npm, "split-pkg", :square, "png", "x")

      assert IconCache.cached?(:npm, "split-pkg", :square, "png")
      refute IconCache.cached?(:local, "split-pkg", :square, "png")
    end
  end

  describe "write!/5" do
    test "writes bytes and a round-trip read returns them" do
      bytes = :crypto.strong_rand_bytes(2_048)

      {:ok, _sha} =
        IconCache.write!(:npm, "round-trip", :square, "png", bytes)

      assert File.read!(IconCache.path(:npm, "round-trip", :square, "png")) ==
               bytes
    end

    test "returns the sha256 of the supplied bytes as a 32-byte binary" do
      bytes = "hello, icon"

      {:ok, sha} = IconCache.write!(:npm, "sha-test", :square, "png", bytes)

      assert sha == :crypto.hash(:sha256, bytes)
      assert byte_size(sha) == 32
    end

    test "is latest-only: a subsequent write for the same key overwrites" do
      {:ok, _} = IconCache.write!(:npm, "overwrite", :square, "png", "first")
      {:ok, _} = IconCache.write!(:npm, "overwrite", :square, "png", "second")

      assert File.read!(IconCache.path(:npm, "overwrite", :square, "png")) ==
               "second"
    end

    test "creates intermediate directories for scoped names" do
      {:ok, _} =
        IconCache.write!(:npm, "@openfn/language-http", :square, "png", "abc")

      assert File.read!(
               IconCache.path(:npm, "@openfn/language-http", :square, "png")
             ) == "abc"
    end

    test "is atomic: concurrent writers produce no half-written file and no leftover temps",
         %{root: root} do
      payloads =
        for i <- 0..49 do
          :crypto.strong_rand_bytes(16_384) <> <<i::32>>
        end

      payloads
      |> Enum.map(fn bytes ->
        Task.async(fn ->
          IconCache.write!(:npm, "concurrent", :square, "png", bytes)
        end)
      end)
      |> Task.await_many(10_000)

      final_path = IconCache.path(:npm, "concurrent", :square, "png")
      final = File.read!(final_path)

      assert final in payloads,
             "final file does not match any written payload — write was not atomic"

      dir = Path.dirname(final_path)

      assert dir |> File.ls!() |> Enum.reject(&(&1 == "square.png")) == [],
             "leftover temp files in #{dir}: #{inspect(File.ls!(dir))}"

      _ = root
    end
  end
end
