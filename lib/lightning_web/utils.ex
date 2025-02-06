defmodule LightningWeb.Utils do
  @moduledoc """
  Helper functions to deal with forms, query params, and dynamic plug setups.

  This module contains:

    * Functions to build and decode query parameters (`build_params_for_field/3` and `decode_one/2`)
    * A macro to set up multiple plugs dynamically (`add_dynamic_plugs/1`)
  """

  alias Phoenix.HTML.Form
  alias Plug.Conn.Query

  @doc """
  Builds nested parameters for the given `form` field with the specified `value`.

  Internally:

    1. Obtains the param name for the `field` using `Form.input_name(form, field)`.
    2. Uses `decode_one/2` to decode the `{param_name, value}` tuple into a map.

  ## Examples

      iex> form = # some %Phoenix.HTML.Form{} struct
      iex> LightningWeb.Utils.build_params_for_field(form, :username, "jane_doe")
      %{"user" => %{"username" => "jane_doe"}}

  """
  def build_params_for_field(form, field, value) do
    name = Form.input_name(form, field)
    decode_one({name, value})
  end

  @doc """
  Decodes a single `{key, value}` pair into a nested map suitable for query/form data.

  This function leverages `Plug.Conn.Query.decode_each/2` and `Query.decode_done/2`
  to parse the key and value into the expected nested structure.

  If an accumulator (`acc`) is provided, it will merge the newly decoded structure
  into `acc`. Otherwise, a new map is returned.

  ## Examples

      iex> LightningWeb.Utils.decode_one({"user[username]", "jane_doe"})
      %{"user" => %{"username" => "jane_doe"}}

      iex> LightningWeb.Utils.decode_one({"user[username]", "jane_doe"}, %{"user" => %{"admin" => false}})
      %{"user" => %{"admin" => false, "username" => "jane_doe"}}

  """
  def decode_one({key, value}, acc \\ %{}) do
    Query.decode_each({key, value}, Query.decode_init())
    |> Query.decode_done(acc)
  end

  @doc """
  Sets up multiple plugs using `Replug`.

  Accepts a list of plug configurations, where each configuration is a tuple:

      {PlugModule, opts}

  * `PlugModule` is the module implementing the plug.
  * `opts` can be a keyword list of options or a tuple like `{module, function}`
    for dynamic plug configuration.

  This macro will iterate over the provided list, calling `plug Replug, plug: plug, opts: opts`
  for each item.

  ## Examples

      @pre_session_plugs Application.compile_env(:my_app, :pre_session_plugs, [])
      add_dynamic_plugs(@pre_session_plugs)

  """
  defmacro add_dynamic_plugs(plugs) do
    quote do
      for {plug, opts} <- unquote(plugs) do
        plug Replug, plug: plug, opts: opts
      end
    end
  end
end
