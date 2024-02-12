defmodule Lightning.UnixDateTime do
  @moduledoc """
  A custom DateTime type for Ecto that uses millisecond Unix timestamps.

  NodeJS uses millisecond Unix timestamps, and Ecto has a choice of either
  second or microsecond precision. This module allows millisecond precision
  integers to be used as DateTime values without losing precision.

  Microsecond timestamps can also be parsed, but currently they are expected
  to be provided as strings. This is because Javascript can't represent
  microsecond timestamps as an integer and BigInt can't be represented
  as a JSON value.

  All functions fallback on the default Ecto types conversion functions.
  """
  use Ecto.Type
  def type, do: :utc_datetime_usec

  @doc """
  Cast a Unix timestamp to a DateTime.

  Accepts integers and strings, and will try to parse the string as an  integer.
  If the integer is 13 digits long, it will be parsed as a millisecond
  timestamp, and as a microsecond timestamp if it is 16 digits long.
  """
  def cast(u) do
    cond do
      is_integer(u) ->
        DateTime.from_unix(u, :millisecond)

      is_struct(u, DateTime) ->
        {:ok, u}

      byte_size(u) == 13 ->
        String.to_integer(u)
        |> DateTime.from_unix(:millisecond)

      byte_size(u) == 16 ->
        String.to_integer(u)
        |> DateTime.from_unix(:microsecond)

      true ->
        :error
    end
    |> case do
      {:ok, dt} ->
        Ecto.Type.cast(:utc_datetime_usec, dt)

      e ->
        e
    end
  end

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

  In the case of JSON objects we serialize them to a string, and in the case of
  arrays we serialize them individually and join them with a space.
  """
  use Ecto.Type
  def type, do: :string

  def cast(d) when is_binary(d), do: Ecto.Type.cast(:string, d)

  def cast(d) when is_integer(d),
    do: Ecto.Type.cast(:string, d |> Integer.to_string())

  def cast(d) when is_list(d) do
    {:ok,
     d
     |> Enum.map(&cast/1)
     |> Enum.map(fn {:ok, v} -> v end)
     |> Enum.intersperse(" ")
     |> IO.iodata_to_binary()}
  end

  def cast(d) when is_map(d) or is_list(d) or is_nil(d) do
    Jason.encode(d)
  end

  def load(d) do
    Ecto.Type.load(:string, d)
  end

  def dump(d) do
    Ecto.Type.dump(:string, d)
  end
end
