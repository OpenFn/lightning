defmodule Lightning.VersionControl.GithubError do
  @moduledoc """
  GitHub Error exception
  """
  defexception [:code, :message, :meta]

  def new(code, msg, meta) when is_binary(msg) do
    %__MODULE__{code: code, message: msg, meta: Map.new(meta)}
  end

  def installation_not_found(msg, meta \\ %{}) do
    new(:installation_not_found, msg, meta)
  end

  def misconfigured(msg, meta \\ %{}) do
    new(:misconfigured, msg, meta)
  end

  def invalid_certificate(msg, meta \\ %{}) do
    new(:invalid_certificate, msg, meta)
  end
end
