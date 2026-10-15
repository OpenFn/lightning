defmodule LightningWeb.API.CodesTest do
  use ExUnit.Case, async: true

  alias LightningWeb.API.Codes

  @lib Path.expand("../../../lib", __DIR__)

  defp codes_set_in(dir) do
    "#{@lib}/#{dir}/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(fn file ->
      Regex.scan(~r/\bcode: :(\w+)/, File.read!(file), capture: :all_but_first)
    end)
    |> MapSet.new(fn [code] -> String.to_atom(code) end)
  end

  test "every code lib/lightning sets with code: is in a code list" do
    # `not_ready` is set but never sent as an entry (spec §6.2).
    known = MapSet.new([:not_ready | Codes.entry_codes()])

    assert MapSet.difference(codes_set_in("lightning"), known) == MapSet.new()
  end

  test "every code Validators lists is set somewhere in lib" do
    # An entry code may be set in lightning_web, where an API controller
    # validates the request itself (spec §7 item 3).
    set = MapSet.union(codes_set_in("lightning"), codes_set_in("lightning_web"))

    assert MapSet.difference(
             MapSet.new(Lightning.Validators.entry_codes()),
             set
           ) == MapSet.new()
  end
end
