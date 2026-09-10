defmodule Lightning.Adaptors.IconField do
  @moduledoc """
  Schema column names for an icon shape.

  Every module that reaches for an icon column — the catalogue schema,
  the store's projections, the scheduler's record merges, the controller
  and the URL builder — goes through here, so `:square` and
  `:rectangle` mean the same columns everywhere and no column name is
  built by interpolating an atom.
  """

  @type shape :: :square | :rectangle

  @spec ext(shape()) :: atom()
  def ext(:square), do: :icon_square_ext
  def ext(:rectangle), do: :icon_rectangle_ext

  @spec sha256(shape()) :: atom()
  def sha256(:square), do: :icon_square_sha256
  def sha256(:rectangle), do: :icon_rectangle_sha256

  @spec etag(shape()) :: atom()
  def etag(:square), do: :icon_square_etag
  def etag(:rectangle), do: :icon_rectangle_etag
end
