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

  @doc """
  Inspect a process and its links.

  - `depth` - The depth of the process to inspect.
  """
  @spec inspect_process(pid(), depth :: integer()) :: map()
  def inspect_process(pid, depth \\ 0) do
    build_process_info(pid, depth, true)
    |> IO.inspect(syntax_colors: IO.ANSI.syntax_colors(), pretty: true)
  end

  defp build_process_info(pid, depth, is_root) do
    info = Process.info(pid)

    process_module =
      case Process.info(pid, :dictionary) do
        {:dictionary, dict} ->
          dict[:"$initial_call"] || dict[:"$ancestors"]

        _ ->
          case Process.info(pid, :initial_call) do
            {:initial_call, {mod, _fun, _arity}} -> mod
            _ -> :unknown
          end
      end

    links =
      info[:links]
      |> List.wrap()
      |> Enum.map(fn link ->
        if depth > 0 do
          %{link => build_process_info(link, depth - 1, false)}
        else
          link
        end
      end)

    %{
      name: info[:registered_name],
      module: process_module,
      alive?: Process.alive?(pid),
      monitors: length(info[:monitors] || []),
      monitored_by: length(info[:monitored_by] || []),
      links: links
    }
    |> then(fn map ->
      if is_root do
        Map.put(map, :self, self()) |> Map.put(:pid, pid)
      else
        map
      end
    end)
  end
end
