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
    @type t :: {
            samples :: [String.t()]
          }

    @spec new(samples :: [String.t()]) :: t()
    def new(samples) do
      {samples}
    end

    @spec samples(state :: t()) :: [String.t()]
    def samples({samples}), do: samples

    @spec scrub(data :: String.t(), state :: t()) :: String.t()
    def scrub(nil, _state), do: nil

    def scrub(string, {samples}) do
      samples
      |> Enum.reduce(string, fn x, acc ->
        String.replace(acc, x, "***", global: true)
      end)
    end
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

  def samples(agent) do
    Agent.get(agent, &State.samples/1)
  end

  def scrub(agent, lines) when is_list(lines) do
    samples = samples(agent)
    lines |> Enum.map(fn line -> State.scrub(line, {samples}) end)
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
    base64_secrets =
      samples
      |> cartesian_pairs()
      |> Enum.map(fn [x, y] ->
        "#{x}:#{y}"
        |> Base.encode64()
      end)

    Enum.concat([samples, base64_secrets])
    |> Enum.sort_by(&String.length/1, :desc)
  end

  defp cartesian_pairs(items) do
    Enum.flat_map(items, fn item ->
      items |> Enum.map(&[item, &1])
    end)
  end
end
