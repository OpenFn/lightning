defmodule Lightning.Services.AdapterHelper do
  @moduledoc """
  Maps the module to be used for the extension service.
  """

  def adapter(extension_key) do
    with nil <- :persistent_term.get({__MODULE__, extension_key}, nil) do
      :lightning
      |> Application.fetch_env!(Lightning.Extensions)
      |> Enum.each(fn {key, module_name} ->
        :persistent_term.put({__MODULE__, key}, module_name)
      end)

      :persistent_term.get({__MODULE__, extension_key})
    end
  end
end
