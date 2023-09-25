defmodule Lightning.VersionControl.GithubError do
  @moduledoc """
  Github Error exception
  """
  defexception [:code, :message, :meta]

  @impl true
  def exception(msg) when is_binary(msg) do
    new(:uknown, msg, %{})
  end

  @impl true
  def exception([message: _msg] = opts) do
    struct(__MODULE__, opts)
  end

  @impl true
  def message(error) do
    error.message
  end

  def new(code, msg, meta) when is_binary(msg) do
    %__MODULE__{code: code, message: msg, meta: Map.new(meta)}
  end

  def installation_not_found(msg, meta \\ %{}) do
    new(:installation_not_found, msg, meta)
  end

  def misconfigured(msg, meta \\ %{}) do
    new(:misconfigured, msg, meta)
  end

  def invalid_pem(msg, meta \\ %{}) do
    new(:invalid_pem, msg, meta)
  end
end
