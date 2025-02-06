defmodule Lightning.Extensions.CollectionHook do
  @moduledoc """
  Callbacks for additional processing on collections operations.
  """
  @behaviour Lightning.Extensions.CollectionHooking

  @impl true
  def handle_create(_attrs), do: :ok

  @impl true
  def handle_delete(_project_id, _size), do: :ok

  @impl true
  def handle_put_items(_col, _size), do: :ok

  @impl true
  def handle_delete_items(_col, _size), do: :ok
end
