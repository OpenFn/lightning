defmodule Lightning.Services.CollectionHook do
  @moduledoc """
  Callbacks for additional processing on collections operations.
  """
  @behaviour Lightning.Extensions.CollectionHooking

  import Lightning.Services.AdapterHelper

  @impl true
  def handle_create(attrs) do
    adapter().handle_create(attrs)
  end

  @impl true
  def handle_delete(collection) do
    adapter().handle_delete(collection)
  end

  @impl true
  def handle_put_items(collection, requested_size) do
    adapter().handle_put_items(collection, requested_size)
  end

  @impl true
  def handle_delete_items(collection, requested_size) do
    adapter().handle_delete_items(collection, requested_size)
  end

  defp adapter, do: adapter(:collection_hook)
end
