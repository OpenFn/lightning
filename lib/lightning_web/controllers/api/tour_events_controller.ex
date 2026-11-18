defmodule LightningWeb.API.TourEventsController do
  @moduledoc """
  Receives tour telemetry events from the React frontend and republishes
  them as `[:lightning, :ui, :tour]` telemetry events.

  Nothing is persisted; the counter metric registered in
  `LightningWeb.Telemetry` is the only consumer.
  """
  use LightningWeb, :controller

  require Logger

  @events ~w(button_shown button_clicked tour_started tour_completed
             tour_abandoned spotlight_shown notice_shown)

  # {param name, metadata key, expected type}
  @optional_fields [
    {"page", :page, :string},
    {"element", :element, :string},
    {"tab", :tab, :string},
    {"reason", :reason, :string},
    {"step_index", :step_index, :integer},
    {"steps_total", :steps_total, :integer}
  ]

  def create(conn, params) do
    with {:ok, event} <- validate_event(params),
         {:ok, fields} <- validate_fields(params) do
      metadata =
        fields
        |> Map.put(:event, event)
        |> Map.put(:user_id, conn.assigns.current_user.id)

      :telemetry.execute([:lightning, :ui, :tour], %{count: 1}, metadata)

      Logger.debug(fn -> "Tour event #{event}: #{inspect(fields)}" end)

      send_resp(conn, :no_content, "")
    else
      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})
    end
  end

  defp validate_event(%{"event" => event}) when event in @events,
    do: {:ok, event}

  defp validate_event(%{"event" => _event}), do: {:error, "unknown event"}

  defp validate_event(_params), do: {:error, "event is required"}

  defp validate_fields(params) do
    Enum.reduce_while(@optional_fields, {:ok, %{}}, fn
      {param, key, type}, {:ok, acc} ->
        case Map.get(params, param) do
          nil ->
            {:cont, {:ok, acc}}

          value when type == :string and is_binary(value) ->
            {:cont, {:ok, Map.put(acc, key, value)}}

          value when type == :integer and is_integer(value) ->
            {:cont, {:ok, Map.put(acc, key, value)}}

          _value ->
            {:halt, {:error, "#{param} must be #{type_label(type)}"}}
        end
    end)
  end

  defp type_label(:string), do: "a string"
  defp type_label(:integer), do: "an integer"
end
