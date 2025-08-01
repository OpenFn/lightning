defmodule Lightning.VersionControl.GithubError do
  @moduledoc """
  GitHub Error exception
  """
  @type t :: %__MODULE__{}
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

  def invalid_oauth_token(msg, meta \\ %{}) do
    new(:invalid_oauth_token, msg, meta)
  end

  def file_not_found(msg, meta \\ %{}) do
    new(:file_not_found, msg, meta)
  end

  def repo_secret_not_found(msg, meta \\ %{}) do
    new(:repo_secret_not_found, msg, meta)
  end

  def api_error(msg, meta \\ %{}) do
    new(:api_error, msg, meta)
  end

  @impl Exception
  def message(%__MODULE__{code: code, message: message, meta: meta}) do
    meta_str =
      case map_size(meta) do
        0 -> ""
        _ -> " (#{inspect(meta)})"
      end

    "[#{code}] #{message}#{meta_str}"
  end
end
