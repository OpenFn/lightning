defmodule Lightning.Schema do
  @moduledoc """
  Defines the database schema and primary key type for Thunderbolt schemas.
  """
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      import Ecto.Changeset

      @schema_prefix "public"
      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime]
    end
  end
end
