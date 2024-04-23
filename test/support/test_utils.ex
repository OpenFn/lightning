defmodule Lightning.TestUtils do
  @moduledoc false

  @doc """
  Assert that the given context has the given keys, otherwise raise an error.

  Useful when writing test cases that have large contexts and pattern matching
  produces large match errors.
  """
  @spec assert_context_keys(map(), list(atom())) :: :ok
  def assert_context_keys(context, keys) do
    for k <- keys do
      ExUnit.Assertions.assert(
        Map.has_key?(context, k),
        "expected context to have key #{inspect(k)}"
      )
    end

    :ok
  end
end
