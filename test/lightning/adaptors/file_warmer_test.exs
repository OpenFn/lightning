defmodule Lightning.Adaptors.FileWarmerTest do
  use ExUnit.Case, async: true

  alias Lightning.Adaptors.FileWarmer

  describe "execute/1" do
    test "returns :ignore when persist_path is not configured" do
      config = %{}
      assert FileWarmer.execute(config) == :ignore
    end

    test "returns :ignore when persist_path is nil" do
      config = %{persist_path: nil}
      assert FileWarmer.execute(config) == :ignore
    end

    test "returns :ignore when cache file does not exist" do
      config = %{persist_path: "/tmp/nonexistent_cache.bin"}
      assert FileWarmer.execute(config) == :ignore
    end

    test "successfully restores cache from valid binary file" do
      persist_path = "/tmp/file_warmer_test_#{:rand.uniform(10000)}.bin"

      # Create test data
      test_pairs = [
        {"adaptors", ["@openfn/language-http", "@openfn/language-dhis2"]},
        {"@openfn/language-http:versions", %{"1.0.0" => %{"version" => "1.0.0"}}},
        {"@openfn/language-dhis2:schema", %{"type" => "object"}}
      ]

      # Serialize and write to file
      binary_data = :erlang.term_to_binary(test_pairs)
      File.write!(persist_path, binary_data)

      config = %{persist_path: persist_path}

      assert {:ok, restored_pairs} = FileWarmer.execute(config)
      assert restored_pairs == test_pairs

      # Clean up
      File.rm(persist_path)
    end

    test "returns :ignore when file read fails" do
      # Create a file, then remove read permissions (on Unix systems)
      persist_path = "/tmp/file_warmer_read_test_#{:rand.uniform(10000)}.bin"
      File.write!(persist_path, "test data")
      File.chmod!(persist_path, 0o000)

      config = %{persist_path: persist_path}

      assert FileWarmer.execute(config) == :ignore

      # Clean up (restore permissions first)
      File.chmod!(persist_path, 0o644)
      File.rm(persist_path)
    end

    test "returns :ignore when binary deserialization fails" do
      persist_path = "/tmp/file_warmer_corrupt_test_#{:rand.uniform(10000)}.bin"

      # Write invalid binary data
      File.write!(persist_path, "invalid binary data")

      config = %{persist_path: persist_path}

      assert FileWarmer.execute(config) == :ignore

      # Clean up
      File.rm(persist_path)
    end

    test "handles empty cache file" do
      persist_path = "/tmp/file_warmer_empty_test_#{:rand.uniform(10000)}.bin"

      # Write empty list
      binary_data = :erlang.term_to_binary([])
      File.write!(persist_path, binary_data)

      config = %{persist_path: persist_path}

      assert {:ok, []} = FileWarmer.execute(config)

      # Clean up
      File.rm(persist_path)
    end
  end

  describe "integration with Cachex" do
    test "populates cache with restored data when used as warmer" do
      import Cachex.Spec

      persist_path = "/tmp/file_warmer_cachex_test_#{:rand.uniform(10000)}.bin"

      # Create test data and save to file
      test_pairs = [
        {"adaptors", ["@openfn/language-test"]},
        {"@openfn/language-test:versions", %{"1.0.0" => %{"version" => "1.0.0"}}}
      ]

      binary_data = :erlang.term_to_binary(test_pairs)
      File.write!(persist_path, binary_data)

      config = %{persist_path: persist_path}

      # Start cache with FileWarmer
      cache_name = :"file_warmer_integration_#{:rand.uniform(10000)}"

      start_supervised!(
        {Cachex,
         [
           cache_name,
           [
             warmers: [
               warmer(
                 state: config,
                 module: Lightning.Adaptors.FileWarmer,
                 required: true
               )
             ]
           ]
         ]}
      )

      # Verify cache contents
      {:ok, adaptors_list} = Cachex.get(cache_name, "adaptors")
      assert adaptors_list == ["@openfn/language-test"]

      {:ok, versions} = Cachex.get(cache_name, "@openfn/language-test:versions")
      assert versions == %{"1.0.0" => %{"version" => "1.0.0"}}

      # Clean up
      File.rm(persist_path)
    end

    test "cache remains empty when FileWarmer returns :ignore" do
      import Cachex.Spec

      config = %{persist_path: "/tmp/nonexistent_file.bin"}

      # Start cache with FileWarmer pointing to non-existent file
      cache_name = :"file_warmer_ignore_#{:rand.uniform(10000)}"

      start_supervised!(
        {Cachex,
         [
           cache_name,
           [
             warmers: [
               warmer(
                 state: config,
                 module: Lightning.Adaptors.FileWarmer,
                 required: false
               )
             ]
           ]
         ]}
      )

      # Verify cache is empty
      {:ok, adaptors_list} = Cachex.get(cache_name, "adaptors")
      assert adaptors_list == nil
    end
  end
end