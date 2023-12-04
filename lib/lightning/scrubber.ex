defmodule Lightning.Scrubber do
  @moduledoc """
  Process used to scrub strings of sensitive information.

  Can be started via `start_link/1`.

  ```
  {:ok, scrubber} =
    Lightning.Scrubber.start_link(
      samples:
        Lightning.Credentials.sensitive_values_for(credential)
    )
  ```

  Takes an optional `:name` key, in case you need to name the process.
  """
  defmodule State do
    @moduledoc false
    @typep samples :: [String.t()]
    @type t :: {samples()}

    @spec new(samples :: [String.t()]) :: t()
    def new(samples) do
      {samples}
    end

    @spec add_samples(state :: t(), samples()) :: [String.t()]
    def add_samples({samples}, new_samples), do: {samples ++ new_samples}

    @spec scrub(state :: t(), data :: String.t()) :: String.t()
    def scrub(nil, _state), do: nil

    def scrub(string, {samples}) when is_binary(string) do
      samples
      |> Enum.reduce(string, fn x, acc ->
        String.replace(acc, x, "***", global: true)
      end)
    end

    def scrub(data, state) when is_map(data) do
      Map.new(data, fn {k, v} ->
        {scrub(k, state), scrub(v, state)}
      end)
    end

    def scrub(data, state), do: scrub(to_string(data), state)
  end

  use Agent

  @spec start_link(opts :: [samples: [String.t()], name: nil | GenServer.name()]) ::
          Agent.on_start()
  def start_link(opts) do
    samples = Keyword.get(opts, :samples, [])

    server_opts =
      Keyword.get(opts, :name)
      |> case do
        nil ->
          []

        name ->
          [name: name]
      end

    Agent.start_link(
      fn -> State.new(samples |> encode_samples()) end,
      server_opts
    )
  end

  def add_samples(agent, new_samples) do
    Agent.update(agent, &State.add_samples(&1, new_samples))
  end

  def scrub(agent, lines) when is_list(lines) do
    state = Agent.get(agent, & &1)
    lines |> Enum.map(fn line -> State.scrub(line, state) end)
  end

  def scrub(agent, data) do
    agent |> Agent.get(&State.scrub(data, &1))
  end

  @doc """
  Prepare a list of sensitive samples (strings) into a potentially bigger list
  composed of variations a sample may appear.
  """
  @spec encode_samples(samples :: [String.t()]) :: [String.t()]
  def encode_samples(samples) do
    stringified_samples =
      samples
      |> Enum.filter(fn x -> not is_boolean(x) end)
      |> Enum.map(fn x -> if is_integer(x), do: Integer.to_string(x), else: x end)

    base64_secrets =
      stringified_samples
      |> cartesian_pairs()
      |> Enum.map(fn [x, y] ->
        "#{x}:#{y}"
        |> Base.encode64()
      end)

    Enum.concat([stringified_samples, base64_secrets])
    |> Enum.sort_by(&String.length/1, :desc)
  end

  defp cartesian_pairs(items) do
    Enum.flat_map(items, fn item ->
      items |> Enum.map(&[item, &1])
    end)
  end
end
