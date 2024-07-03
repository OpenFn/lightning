defmodule Lightning.Services.AdapterHelper do
  @moduledoc """
  Maps the module to be used for the extension service.
  """

  def adapter(extension_key) do
    case :persistent_term.get({__MODULE__, extension_key}, nil) do
      nil ->
        :lightning
        |> Application.get_env(Lightning.Extensions, [])
        |> Keyword.get(extension_key, :not_found)
        |> case do
          :not_found ->
            nil

          value ->
            :persistent_term.put({__MODULE__, extension_key}, value)
            value
        end

      value ->
        value
    end
  end
end
