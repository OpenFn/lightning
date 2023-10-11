defmodule LightningWeb.Utils do
  def build_params_for_field(form, field, value) do
    alias Phoenix.HTML.Form

    name = Form.input_name(form, field)

    decode_one({name, value})
  end

  def decode_one({key, value}, acc \\ %{}) do
    alias Plug.Conn.Query

    Query.decode_each({key, value}, Query.decode_init())
    |> Query.decode_done(acc)
  end
end
