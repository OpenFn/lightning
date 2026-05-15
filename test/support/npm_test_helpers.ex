defmodule Lightning.Adaptors.NPMTestHelpers do
  @moduledoc """
  Shared test helpers for `Lightning.Adaptors.NPM` and its sub-module
  test files.
  """

  @doc """
  Build an in-memory `.tar.gz` archive from a list of `{path, body}`
  tuples and return the raw compressed bytes.

  The tarball is written to a unique path under `System.tmp_dir!/0`,
  read back, and cleaned up before returning. Used by the tarball
  sub-module test and the orchestrator test to feed Bypass responses.
  """
  @spec build_tarball([{String.t(), iodata()}]) :: binary()
  def build_tarball(entries) do
    tar_path =
      Path.join(
        System.tmp_dir!(),
        "npm_adaptor_test_#{System.unique_integer([:positive])}.tar.gz"
      )

    files =
      Enum.map(entries, fn {name, body} -> {to_charlist(name), body} end)

    :ok = :erl_tar.create(to_charlist(tar_path), files, [:compressed])
    bytes = File.read!(tar_path)
    File.rm!(tar_path)
    bytes
  end
end
