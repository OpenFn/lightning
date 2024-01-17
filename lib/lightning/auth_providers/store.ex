defmodule Lightning.AuthProviders.Store do
  @moduledoc """
  Store module for caching Handlers.

  Since Handlers often have to fetch their `.well-known` files when being
  initialized we cache these in order to avoid repeatedly making HTTP requests
  to a providers API.
  """
  alias Lightning.AuthProviders.Handler

  @type finder :: (name :: String.t() -> {:ok, Handler.t()} | {:error, term()})

  @spec get_handlers() :: {:ok, [Handler.t()]}
  def get_handlers do
    {:ok,
     Cachex.execute!(cache_name(), fn cache ->
       Cachex.keys!(cache) |> Enum.map(&Cachex.get!(cache, &1))
     end)}
  end

  @spec get_handler(key :: String.t(), default :: finder()) ::
          {:ok, Handler.t()} | {:error, :not_found}
  def get_handler(name, finder \\ &default/1) do
    case Cachex.get(cache_name(), name) do
      {:ok, nil} ->
        case finder.(name) do
          {:ok, handler} ->
            put_handler(name, handler)

          {:error, :not_found} = e ->
            e
        end

      {:ok, :not_found} ->
        {:error, :not_found}

      {:ok, val} ->
        {:ok, val}
    end
  end

  @spec put_handler(
          name :: String.t(),
          handler :: Handler.t()
        ) ::
          {:ok, Handler.t()}
  def put_handler(name, %Handler{} = handler) do
    {:ok, _} = Cachex.put(cache_name(), name, handler, ttl: :timer.minutes(30))
    {:ok, handler}
  end

  @spec remove_handler(name :: String.t()) ::
          {:ok, true}
  def remove_handler(name) do
    Cachex.del(cache_name(), name)
  end

  defp cache_name do
    :auth_providers
  end

  defp default(_name) do
    {:error, :not_found}
  end
end
