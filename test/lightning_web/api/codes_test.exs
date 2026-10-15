defmodule LightningWeb.API.CodesTest do
  use ExUnit.Case, async: true

  alias LightningWeb.API.Codes

  @lib Path.expand("../../../lib/lightning", __DIR__)

  test "Validators lists exactly the codes lib/lightning sets with code:" do
    set =
      "#{@lib}/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(fn file ->
        Regex.scan(~r/\bcode: :(\w+)/, File.read!(file), capture: :all_but_first)
      end)
      |> MapSet.new(fn [code] -> String.to_atom(code) end)

    listed = Lightning.Validators.entry_codes()
    ecto_codes = Codes.entry_codes() -- listed

    # `not_ready` is set but never sent as an entry (spec §6.2).
    expected =
      MapSet.new([:not_ready | listed])
      |> MapSet.union(MapSet.intersection(set, MapSet.new(ecto_codes)))

    assert set == expected
  end
end
