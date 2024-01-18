defmodule LightningWeb.Utils do
  @moduledoc """
  Helper functions to deal with forms and query params.
  """
  alias Phoenix.HTML.Form
  alias Plug.Conn.Query

  def build_params_for_field(form, field, value) do
    name = Form.input_name(form, field)

    decode_one({name, value})
  end

  def decode_one({key, value}, acc \\ %{}) do
    Query.decode_each({key, value}, Query.decode_init())
    |> Query.decode_done(acc)
  end
end
