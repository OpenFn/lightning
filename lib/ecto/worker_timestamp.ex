defmodule Lightning.Ecto.WorkerTimestamp do
  @moduledoc """
  The worker sends timestamps in form of unix microseconds.
  This module is responsible for coverting this type to DateTime
  """
  use Ecto.Type

  def type, do: :utc_datetime_usec

  def cast(timestamp) when is_binary(timestamp) do
    timestamp
    |> String.to_integer()
    |> DateTime.from_unix(:microsecond)
    |> case do
      {:ok, datetime} ->
        {:ok, datetime}

      _error ->
        :error
    end
  end

  def cast(%DateTime{} = timestamp) do
    {:ok, timestamp}
  end

  def cast(_), do: :error

  def dump(timestamp) do
    cast(timestamp)
  end

  def load(datetime) do
    {:ok, datetime |> DateTime.to_unix(:microsecond) |> to_string()}
  end
end
