defmodule Lightning.Adaptors.PackageName do
  @moduledoc """
  NPM-style package-name parsing and worker wire-shape recomposition for
  the `Lightning.Adaptors.*` subsystem.

  This module is the single source of truth for adaptor package name
  parsing and wire recomposition, read through the `Lightning.Adaptors`
  facade.

  `parse/1` splits `"name@version"` strings using the same strict,
  anchored format `strict_format/0` validates against, so a spec that
  reaches `to_wire/1` after passing changeset validation is guaranteed to
  parse to the same name — never a truncated or re-derived one. `to_wire/1`
  resolves the `latest` literal through `Lightning.Adaptors.resolve_version/2`,
  preserves `"name@local"` as a literal regardless of source, and emits
  `"name@local"` under a `:local` strategy source.
  """

  alias Lightning.Adaptors
  alias Lightning.Adaptors.Config

  # Anchored with \A…\z (NOT ^…$, since $ matches before a trailing \n).
  # Accepts scoped (@scope/name) and unscoped names with an optional
  # @version (semver, prerelease, or the tokens `latest` / `local`);
  # excludes newlines and shell metacharacters.
  @strict_format ~r{\A(@?[\w.-]+(?:/[\w.-]+)?)(?:@([\w.-]+))?\z}

  @doc """
  The strict, anchored package-name format: name plus optional `@version`,
  rejecting embedded newlines and shell metacharacters. Read through
  `Lightning.Adaptors.valid_format?/1` and
  `Lightning.Adaptors.parse_spec/1`.
  """
  @spec strict_format() :: Regex.t()
  def strict_format, do: @strict_format

  @spec parse(nil) :: {nil, nil}
  def parse(nil), do: {nil, nil}

  @spec parse(String.t()) :: {String.t() | nil, String.t() | nil}
  def parse(package_name) when is_binary(package_name) do
    case Regex.run(@strict_format, package_name) do
      [_, name, version] -> {name, version}
      [_, name] -> {name, nil}
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
