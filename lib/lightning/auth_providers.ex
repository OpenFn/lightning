defmodule Lightning.AuthProviders do
  @moduledoc """
  Context module for dealing with external Auth Providers.
  """
  import Ecto.Query

  alias Lightning.AuthProviders.AuthConfig
  alias Lightning.AuthProviders.Handler
  alias Lightning.AuthProviders.Store
  alias Lightning.AuthProviders.WellKnown
  alias Lightning.Repo

  @spec get_existing() :: AuthConfig.t() | nil
  def get_existing do
    from(ap in AuthConfig) |> Repo.one()
  end

  @spec get_existing(name :: String.t()) :: AuthConfig.t() | nil
  def get_existing(name) do
    from(ap in AuthConfig, where: ap.name == ^name) |> Repo.one()
  end

  def new do
    %AuthConfig{}
  end

  def create(attrs) do
    %AuthConfig{}
    |> AuthConfig.changeset(attrs)
    |> Repo.insert()
  end

  def update(model, attrs) do
    with {:ok, model} <- model |> AuthConfig.changeset(attrs) |> Repo.update() do
      # Drop the handler from the cache, forcing it to be reinitialised
      # next time it's requested.
      create_handler(model)

      {:ok, model}
    end
  end

  def delete!(model) do
    model |> Repo.delete!()
  end

  @spec get_handler(name :: String.t()) ::
          {:ok, Handler.t()} | {:error, :not_found}
  def get_handler(name) do
    store_impl().get_handler(name, &find_and_build/1)
  end

  @spec get_handlers() ::
          {:ok, [Handler.t()]}
  def get_handlers do
    store_impl().get_handlers()
  end

  @spec create_handler(handler_or_config :: Handler.t() | AuthConfig.t()) ::
          {:ok, Handler.t()} | {:error, term()}
  def create_handler(%AuthConfig{name: name} = config) do
    with {:ok, handler} <- Handler.from_model(config) do
      store_impl().put_handler(name, handler)
    end
  end

  def create_handler(%Handler{name: name} = handler) do
    store_impl().put_handler(name, handler)
  end

  @spec remove_handler(name_or_handler :: String.t() | Handler.t()) ::
          {:ok, true}
  def remove_handler(%Handler{name: name}) do
    remove_handler(name)
  end

  def remove_handler(name) when is_binary(name) do
    store_impl().remove_handler(name)
  end

  def build_handler(name, opts) do
    opts =
      Keyword.new(opts, fn
        {:discovery_url, v} -> {:wellknown, WellKnown.fetch!(v)}
        {k, v} -> {k, v}
      end)

    Handler.new(name, opts)
  end

  @doc """
  Retrieve the authorization url for a given handler or handler name.
  """
  @spec get_authorize_url(String.t() | Handler.t()) :: String.t() | nil
  def get_authorize_url(name) when is_binary(name) do
    case get_handler(name) do
      {:ok, handler} -> get_authorize_url(handler)
      {:error, :not_found} -> nil
    end
  end

  def get_authorize_url(%Handler{} = handler) do
    Handler.authorize_url(handler)
  end

  defp find_and_build(name) do
    get_existing(name)
    |> Handler.from_model()
  end

  @spec store_impl() :: Store
  defp store_impl do
    Application.get_env(
      :lightning,
      :auth_providers_store,
      Store
    )
  end
end
