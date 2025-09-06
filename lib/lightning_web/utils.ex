defmodule LightningWeb.Utils do
  @moduledoc """
  Helper functions to deal with forms, query params, and dynamic plug setups.

  This module contains:

    * Functions to build and decode query parameters (`build_params_for_field/3` and `decode_one/2`)
    * A macro to set up multiple plugs dynamically (`add_dynamic_plugs/1`)
  """

  alias Phoenix.HTML.Form
  alias Plug.Conn.Query

  require Logger

  def pluralize_with_s(n, string) when n <= 1, do: string
  def pluralize_with_s(_integer, string), do: "#{string}s"

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

  def noreply(socket), do: {:noreply, socket}
  def reply(socket), do: {:reply, socket}
  def ok(socket), do: {:ok, socket}

  @doc """
  Standard **503 Service Unavailable** response for transient DB outages
  during webhook handling.

  This function is typically called inside a `with_webhook_retry/2` error branch
  when retries against the database have been exhausted.

  ## Options

    * `:message` — custom response message, may include `"%{s}"` placeholder
      which will be replaced with the retry-after value.
    * `:halt?` — whether to halt the connection after sending the response.
      Defaults to `true`.
  """
  @spec respond_service_unavailable(
          Plug.Conn.t(),
          Exception.t(),
          map(),
          keyword()
        ) ::
          Plug.Conn.t()
  def respond_service_unavailable(
        conn,
        %DBConnection.ConnectionError{} = error,
        context,
        opts \\ []
      ) do
    halt? = Keyword.get(opts, :halt?, true)

    message =
      Keyword.get(
        opts,
        :message,
        "Temporary database issue. Please retry in %{s}s."
      )

    retry_after =
      Lightning.Config.webhook_retry(:timeout_ms) |> div(1000) |> max(1)

    :telemetry.execute(
      [:lightning, :webhook, :db_unavailable],
      %{count: 1},
      Map.merge(context, %{retry_after: retry_after})
    )

    Lightning.Sentry.capture_exception(error,
      extra: Map.merge(context, %{retry_after: retry_after}),
      tags: %{type: "webhook", op: to_string(Map.get(context, :op, :unknown))},
      fingerprint: [
        "webhook-db-unavailable",
        to_string(Map.get(context, :op, :unknown))
      ]
    )

    Logger.error(
      "webhook #{Map.get(context, :op, "op=unknown")} exhausted retries " <>
        Enum.map_join(context, " ", fn {k, v} -> "#{k}=#{v}" end) <>
        " error=#{Exception.message(error)}"
    )

    body = %{
      error: :service_unavailable,
      message: String.replace(message, "%{s}", Integer.to_string(retry_after)),
      retry_after: retry_after
    }

    conn =
      conn
      |> Plug.Conn.put_resp_header("retry-after", Integer.to_string(retry_after))
      |> Plug.Conn.put_status(:service_unavailable)
      |> Phoenix.Controller.json(body)

    if halt?, do: Plug.Conn.halt(conn), else: conn
  end

  @doc """
  Normalizes a color string to a `#RRGGBB` uppercase hex.

  Accepts:
    * `#RGB`, `RGB`
    * `#RRGGBB`, `RRGGBB`
    * Any other value -> fallback #79B2D6
  """
  @spec normalize_hex(nil | binary() | any()) :: binary()
  def normalize_hex(nil), do: "#79B2D6"

  def normalize_hex(val) when is_binary(val) do
    val
    |> String.trim()
    |> String.trim_leading("#")
    |> String.upcase()
    |> case do
      <<r::binary-size(1), g::binary-size(1), b::binary-size(1)>> = s ->
        if valid_hex?(s), do: "##{r <> r}#{g <> g}#{b <> b}", else: "#79B2D6"

      <<r::binary-size(2), g::binary-size(2), b::binary-size(2), _rest::binary>> =
          s ->
        if valid_hex?(String.slice(s, 0, 6)),
          do: "##{r}#{g}#{b}",
          else: "#79B2D6"

      <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> = s ->
        if valid_hex?(s), do: "##{r}#{g}#{b}", else: "#79B2D6"

      _ ->
        "#79B2D6"
    end
  end

  def normalize_hex(_), do: "#79B2D6"

  defp valid_hex?(str), do: String.match?(str, ~r/^[0-9A-F]+$/)
end
