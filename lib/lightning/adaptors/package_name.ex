defmodule Lightning.Adaptors.PackageName do
  @moduledoc """
  Parses `name@version` adaptor specs and renders them for the worker.
  """

  # `\A…\z` rather than `^…$`: `$` matches before a trailing newline.
  @strict_format ~r{\A(@?[\w.-]+(?:/[\w.-]+)?)(?:@([\w.-]+))?\z}

  @name_format ~r{\A@?[\w.-]+(?:/[\w.-]+)?\z}

  @doc """
  Returns the spec format: a package name plus optional `@version`, with
  no newlines or shell metacharacters.
  """
  @spec strict_format() :: Regex.t()
  def strict_format, do: @strict_format

  @doc """
  Returns the bare package-name format, with no `@version` suffix.
  """
  @spec name_format() :: Regex.t()
  def name_format, do: @name_format

  @doc """
  Splits a spec into `{name, version}`; `{nil, nil}` for `nil` or a
  malformed spec.
  """
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

  @doc """
  Renders a spec for the worker.

  `opts[:source]` of `:local` forces `name@local`. `opts[:latest]` is the
  concrete version for a `latest` spec, and is required for one under
  any other source. A `name@local` spec is always kept as is.
  """
  @spec to_wire(String.t() | nil, keyword()) :: String.t()
  def to_wire(adaptor, opts \\ []) do
    case parse(adaptor) do
      {nil, nil} ->
        ""

      {name, "local"} ->
        "#{name}@local"

      {name, version} ->
        cond do
          opts[:source] == :local -> "#{name}@local"
          version == "latest" -> "#{name}@#{Keyword.fetch!(opts, :latest)}"
          true -> adaptor
        end
    end
  end
end
