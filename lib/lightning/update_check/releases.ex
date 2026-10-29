defmodule Lightning.UpdateCheck.Releases do
  @moduledoc """
  Pure helpers for picking full releases out of an image repository's tags
  and comparing them with the running version.

  A full release is a tag shaped like `vX.Y.Z` (the `v` is optional) with no
  pre-release suffix. `v2.20.0-pre`, `edge`, `latest` and branch tags are not
  releases.
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
  pre-release suffix (`2.20.0-pre`). A version that can't be parsed, or a
  missing `latest`, is never behind.
  """
  @spec newer?(Version.t() | nil, String.t() | nil) :: boolean()
  def newer?(nil, _current), do: false

  def newer?(%Version{} = latest, current) when is_binary(current) do
    case Version.parse(current) do
      {:ok, running} -> Version.compare(latest, running) == :gt
      :error -> false
    end
  end

  def newer?(%Version{}, _current), do: false
end
