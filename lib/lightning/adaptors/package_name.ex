defmodule Lightning.Adaptors.PackageName do
  @moduledoc """
  NPM-style package-name parsing and worker wire-shape recomposition for
  the `Lightning.Adaptors.*` subsystem.

  This module is the single source of truth for the legacy
  `AdaptorRegistry.resolve_adaptor/1` and `resolve_package_name/1`
  contracts, ported to read through the `Lightning.Adaptors` facade.

  `parse/1` splits `"name@version"` strings; `to_wire/1` resolves the
  `latest` literal through `Lightning.Adaptors.resolve_version/2`,
  preserves `"name@local"` as a literal regardless of source, and emits
  `"name@local"` under a `:local` strategy source.
  """

  alias Lightning.Adaptors
  alias Lightning.Adaptors.Config

  @package_name_regex ~r/(@?[\/\d\n\w-]+)(?:@([\d\.\w-]+))?$/

  @spec parse(nil) :: {nil, nil}
  def parse(nil), do: {nil, nil}

  @spec parse(String.t()) :: {String.t() | nil, String.t() | nil}
  def parse(package_name) when is_binary(package_name) do
    case Regex.run(@package_name_regex, package_name) do
      [_, name, version] -> {name, version}
      [_, _name] -> {package_name, nil}
      _ -> {nil, nil}
    end
  end

  @spec to_wire(String.t() | nil) :: String.t()
  def to_wire(adaptor) do
    case parse(adaptor) do
      {nil, nil} -> ""
      {name, version} -> recompose(name, version, adaptor)
    end
  end

  defp recompose(name, "local", _original), do: "#{name}@local"

  defp recompose(name, version, original) do
    case Config.current_source() do
      :local ->
        "#{name}@local"

      _ ->
        case version do
          "latest" ->
            case Adaptors.resolve_version(name, "latest") do
              {:ok, resolved} -> "#{name}@#{resolved}"
              {:error, _} -> "#{name}@latest"
            end

          nil ->
            original

          _concrete ->
            original
        end
    end
  end
end
