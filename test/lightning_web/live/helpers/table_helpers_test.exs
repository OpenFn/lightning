defmodule LightningWeb.Live.Helpers.TableHelpersTest do
  use ExUnit.Case, async: true

  alias LightningWeb.Live.Helpers.TableHelpers

  describe "sort_field/3" do
    test "resolves known keys and defaults unknown/nil without interning" do
      assert TableHelpers.sort_field("enabled", [:name, :enabled], :name) ==
               :enabled

      assert TableHelpers.sort_field(nil, [:name, :enabled], :name) == :name

      key = "totally_unknown_#{System.unique_integer([:positive])}"
      assert TableHelpers.sort_field(key, [:name, :enabled], :name) == :name
      # The unknown key must never be turned into an atom (atom-table DoS).
      assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
    end
  end

  describe "sort_direction/1" do
    test "maps asc/desc and defaults everything else to :asc" do
      assert TableHelpers.sort_direction("asc") == :asc
      assert TableHelpers.sort_direction("desc") == :desc
      assert TableHelpers.sort_direction("sideways") == :asc
      assert TableHelpers.sort_direction(nil) == :asc
    end
  end
end
