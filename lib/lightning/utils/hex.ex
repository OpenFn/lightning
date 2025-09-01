defmodule Lightning.Validators.Hex do
  @moduledoc """
  Flexible validator for **hex strings** with configurable length.

  By default it expects **12 lowercase** hex characters (`0-9`, `a-f`), which
  matches our common “head hash” format. You can change both the **length**
  (fixed integer or inclusive range) and the **letter case** via options.

  ## Length

  Pass either:
  * a positive integer (exact length), or
  * an inclusive `Range` (min..max length).

  ## Case handling

  Use the `:case` option:
  * `:lower` (default) – allow only `a-f`
  * `:upper` – allow only `A-F`
  * `:any`   – allow `a-f` or `A-F`

  ## Examples

      iex> Lightning.Validators.Hex.valid?("deadbeefcafe")
      true

      iex> Lightning.Validators.Hex.valid?("DEADBEEFCAFE")
      false

      iex> Lightning.Validators.Hex.valid?("DEADBEEFCAFE", case: :upper)
      true

      iex> Lightning.Validators.Hex.valid?("a1", 1..2)
      true

      iex> Lightning.Validators.Hex.valid?("xyz", 3)
      false

      iex> Lightning.Validators.Hex.format()
      ~r/^[0-9a-f]{12}$/

      iex> Lightning.Validators.Hex.format(8)
      ~r/^[0-9a-f]{8}$/

      iex> Lightning.Validators.Hex.format(8..64, case: :any)
      ~r/^[0-9A-Fa-f]{8,64}$/

  ## Ecto usage

      changeset
      |> Ecto.Changeset.validate_format(:hash, Lightning.Validators.Hex.format())
  """

  @default_len 12

  @typedoc "Length can be a positive integer (exact) or an inclusive range."
  @type length_spec :: pos_integer() | Range.t()

  @typedoc "Case handling for hex letters."
  @type case_opt :: :lower | :upper | :any

  @doc """
  Returns `true` if `s` is hex of the requested length and case.

  Accepts convenience forms:

  * `valid?(s)` — uses default length (#{@default_len}) and `case: :lower`
  * `valid?(s, len_or_range)` — custom length, lowercase only
  * `valid?(s, case: :upper | :any)` — default length with custom case
  * `valid?(s, len_or_range, opts)` — full control
  """
  @spec valid?(term) :: boolean
  @spec valid?(term, length_spec) :: boolean
  @spec valid?(term, keyword) :: boolean
  @spec valid?(term, length_spec, keyword) :: boolean
  def valid?(s), do: valid?(s, @default_len, [])

  def valid?(s, opts) when is_list(opts),
    do: valid?(s, @default_len, opts)

  def valid?(s, len_or_range)
      when is_integer(len_or_range) or is_struct(len_or_range, Range),
      do: valid?(s, len_or_range, [])

  def valid?(s, len_or_range, opts) when is_binary(s),
    do: len_or_range |> build_regex(opts) |> Regex.match?(s)

  def valid?(_, _len_or_range, _opts), do: false

  @doc """
  Returns a compiled **Regex** for hex strings.

  Accepts convenience forms:

  * `format()` — default length (#{@default_len}), lowercase
  * `format(len_or_range)` — custom length, lowercase
  * `format(case: :upper | :any)` — default length with custom case
  * `format(len_or_range, opts)` — full control
  """
  @spec format() :: Regex.t()
  @spec format(length_spec) :: Regex.t()
  @spec format(keyword) :: Regex.t()
  @spec format(length_spec, keyword) :: Regex.t()
  def format(), do: build_regex(@default_len, [])

  def format(opts) when is_list(opts),
    do: build_regex(@default_len, opts)

  def format(len_or_range)
      when is_integer(len_or_range) or is_struct(len_or_range, Range),
      do: build_regex(len_or_range, [])

  def format(len_or_range, opts),
    do: build_regex(len_or_range, opts)

  @doc false
  @spec build_regex(length_spec, keyword) :: Regex.t()
  defp build_regex(len_or_range, opts) do
    cls = hex_class(Keyword.get(opts, :case, :lower))
    q = quantifier(len_or_range)
    Regex.compile!("^#{cls}#{q}$")
  end

  @doc false
  defp hex_class(:lower), do: "[0-9a-f]"
  defp hex_class(:upper), do: "[0-9A-F]"
  defp hex_class(:any), do: "[0-9A-Fa-f]"
  defp hex_class(_), do: "[0-9a-f]"

  @doc false
  defp quantifier(len) when is_integer(len) and len > 0, do: "{#{len}}"

  defp quantifier(%Range{first: min, last: max} = r)
       when is_integer(min) and is_integer(max) and min > 0 and max >= min and
              r.step in [1, nil],
       do: "{#{min},#{max}}"

  defp quantifier(other),
    do: raise(ArgumentError, "invalid length_spec: #{inspect(other)}")
end
