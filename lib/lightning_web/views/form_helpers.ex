defmodule LightningWeb.FormHelpers do
  @moduledoc """
  Conveniences for building forms.
  """

  use Phoenix.HTML

  defimpl Phoenix.HTML.Safe, for: Map do
    @doc """
    Extension to Phoenix's protocols to allow editing of a JSONB/map field.
    """
    def to_iodata(data) do
      Jason.encode!(data || "")
    end
  end

  # defimpl Phoenix.HTML.Safe, for: String.Chars do
  #   @doc """
  #   Extension to Phoenix's protocols to allow viewing of Array of Strings of a JSONB/map field.
  #   """
  #   def to_iodata(data) do
  #     data |> IO.inspect 
  #   end
  # end
end
