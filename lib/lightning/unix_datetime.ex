defmodule Lightning.UnixDateTime do
  @moduledoc """
  A custom DateTime type for Ecto that uses millisecond Unix timestamps.

  NodeJS uses millisecond Unix timestamps, and Ecto has a choice of either
  second or microsecond precision. This module allows millisecond precision
  integers to be used as DateTime values without losing precision.

  All functions fallback on the default Ecto types conversion functions.
  """
  use Ecto.Type
  def type, do: :utc_datetime_usec

  @doc """
  Cast a millisecond Unix timestamp to a DateTime.
  """
  def cast(u) when is_integer(u) do
    DateTime.from_unix(u, :millisecond)
    |> case do
      {:ok, dt} ->
        {:ok, dt |> DateTime.add(0, :microsecond)}

      e ->
        e
    end
  end

  def cast(u), do: Ecto.Type.cast(:utc_datetime_usec, u)

  def load(u) do
    Ecto.Type.load(:utc_datetime_usec, u)
  end

  def dump(u) do
    Ecto.Type.dump(:utc_datetime_usec, u)
  end
end
