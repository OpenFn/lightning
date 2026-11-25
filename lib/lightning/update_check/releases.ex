defmodule Lightning.UpdateCheck.Releases do
  @moduledoc """
  Pure helpers for picking full releases out of an image repository's tags
  and comparing them with the running version.

  A full release is a tag shaped like `X.Y.Z` with no pre-release suffix.
  Older images were tagged `vX.Y.Z`, so a leading `v` is accepted.
  `2.20.0-pre`, `edge`, `latest` and branch tags are not releases.
  """

  @doc """
  Parses a full-release tag into a `Version`, or returns `:error` for
  anything else.
  """
  @spec parse(String.t()) :: {:ok, Version.t()} | :error
  def parse("v" <> rest), do: parse_release(rest)
  def parse(tag) when is_binary(tag), do: parse_release(tag)

  defp parse_release(string) do
    case Version.parse(string) do
      {:ok, %Version{pre: [], build: nil} = version} -> {:ok, version}
      _other -> :error
    end
  end

  @doc """
  Parses a version as something reports it, such as a worker or the running
  app. Unlike `parse/1` it keeps pre-releases. A leading `v` is dropped, so
  `"v1.2.3"` and `"1.2.3"` are the same version.
  """
  @spec parse_version(String.t() | nil) :: {:ok, Version.t()} | :error
  def parse_version("v" <> rest), do: Version.parse(rest)
  def parse_version(version) when is_binary(version), do: Version.parse(version)
  def parse_version(_version), do: :error

  @doc """
  Returns the full-release tags as `{tag, version}` pairs, newest first.
  """
  @spec stable_tags([String.t()]) :: [{String.t(), Version.t()}]
  def stable_tags(tags) do
    tags
    |> Enum.flat_map(fn tag ->
      case parse(tag) do
        {:ok, version} -> [{tag, version}]
        :error -> []
      end
    end)
    |> Enum.sort_by(fn {_tag, version} -> version end, {:desc, Version})
  end

  @doc """
  Whether `latest` is a newer version than `current`.

  `current` is the running app's version string, which may carry a
  pre-release suffix (`2.20.0-pre`) or a leading `v`. A version that can't be
  parsed, or a missing `latest`, is never behind.
  """
  @spec newer?(Version.t() | nil, String.t() | nil) :: boolean()
  def newer?(nil, _current), do: false

  def newer?(%Version{} = latest, current) do
    case parse_version(current) do
      {:ok, running} -> Version.compare(latest, running) == :gt
      :error -> false
    end
  end
end
