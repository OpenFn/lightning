defmodule Lightning.Adaptors do
  @moduledoc """
  Adaptor registry
  """

  @type config :: %{
          strategy: {module(), term()},
          cache: Cachex.t()
        }

  def all(config \\ %{}) do
    {_, result} =
      Cachex.fetch(config[:cache], :adaptors, fn _key ->
        {module, strategy_config} = split_strategy(config.strategy)
        {:ok, adaptors} = module.fetch_adaptors(strategy_config)

        adaptor_names =
          adaptors
          |> Enum.map(fn adaptor ->
            adaptor.name
          end)

        {:commit, adaptor_names}
      end)

    result
  end

  defp split_strategy(strategy) do
    case strategy do
      {module, config} -> {module, config}
      module -> {module, []}
    end
  end

  def packages_filter(name) do
    name not in [
      "@openfn/language-devtools",
      "@openfn/language-template",
      "@openfn/language-fhir-jembi",
      "@openfn/language-collections"
    ] &&
      Regex.match?(~r/@openfn\/language-\w+/, name)
  end
end
