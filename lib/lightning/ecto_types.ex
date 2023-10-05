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

defmodule Lightning.LogMessage do
  @moduledoc """
  A custom type to handle JSON log messages.

  Currently the underlying database type is a string, and workers may send
  either a string, or a JSON object. This type will encode JSON objects to
  string.

  > #### Messages are always strings {: .info}
  >
  > While this type allows JSON objects to be sent, the model will always return
  > strings. This type is a stand-in until we want to add a JSONB column to the
  > underlying table.
  """
  use Ecto.Type
  def type, do: :string

  @doc """
  Cast a millisecond Unix timestamp to a DateTime.
  """
  def cast(d) when is_binary(d), do: Ecto.Type.cast(:string, d)

  def cast(d) when is_map(d) or is_list(d) do
    Jason.encode(d)
  end

  def load(d) do
    Ecto.Type.load(:string, d)
  end

  def dump(d) do
    Ecto.Type.dump(:string, d)
  end
end
