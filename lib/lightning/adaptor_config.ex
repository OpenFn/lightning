defmodule Lightning.AdaptorConfig do
  defstruct [:value]

  defimpl Inspect, for: Lightning.AdaptorConfig do
    @keys_to_scrub ["password", "url", "user"]

    def inspect(%{value: %{} = config}, _opts) do
      scrubbed_map = scrub_keys(config)
      Kernel.inspect(scrubbed_map)
    end

    def inspect(%{value: nil}, _opts) do
      Kernel.inspect(nil)
    end

    defp scrub_keys(map = %{}) do
      map
      |> Enum.map(fn
        {k, _v} when k in @keys_to_scrub -> {k, "[FILTERED]"}
        {k, v} -> {k, scrub_keys(v)}
      end)
      |> Enum.into(%{})
    end

    defp scrub_keys([head | rest]) do
      [scrub_keys(head) | scrub_keys(rest)]
    end

    defp scrub_keys(not_a_map) do
      not_a_map
    end
  end
end
