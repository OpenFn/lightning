defmodule FakeRambo do
  @moduledoc """
  Mock implementation of Rambo.

  The Cachex cache that backs `stub_run/1` is started under each test's
  ExUnit supervisor via `FakeRambo.Setup.start_cache!/0`, so it lives for
  exactly one test. This avoids the previous failure mode where the cache's
  ETS table was owned by whichever test first called `Cachex.start_link/1`
  and disappeared once that test exited, breaking unrelated subsequent
  tests.
  """

  @cache_name :fake_rambo_cache

  defmodule Setup do
    @moduledoc false

    @doc """
    Starts a Cachex instance for `FakeRambo` under the current test's
    ExUnit supervisor. Must be called from a test setup or test body.
    """
    def start_cache! do
      ExUnit.Callbacks.start_supervised!(
        {Cachex, name: FakeRambo.cache_name()},
        restart: :temporary
      )

      :ok
    end
  end

  defmodule Helpers do
    @moduledoc false

    def stub_run(res) do
      Cachex.put(FakeRambo.cache_name(), :res, res)
    end
  end

  @doc false
  def cache_name, do: @cache_name

  def run(command, args, opts) do
    send(self(), {command, args, opts})

    case Cachex.get(@cache_name, :res) do
      {:ok, nil} -> {:ok, %{out: "", status: 0}}
      {:ok, res} -> res
      {:error, _} -> {:ok, %{out: "", status: 0}}
    end
  end
end
