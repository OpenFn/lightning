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

  @doc """
  Merge the given setups into the given context.
  Just works a bit like `setup` on ExUnit.Case.

  Useful when writing tests, which have some nice setups but you need to
  make a new context inside the test.

  Use with care, chances are you should be writing another test or refactoring
  the tests to use tags.
  """
  defmacro merge_setups(context, fns) do
    fns =
      Enum.map(fns, fn f ->
        quote do
          fn c -> unquote(f)(c) end
        end
      end)

    quote do
      unquote(fns)
      |> Enum.reduce(unquote(context), fn f, context ->
        Map.merge(context, f.(context))
      end)
    end
  end
end
