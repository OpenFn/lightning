defmodule LightningWeb.Live.Helpers.TableHelpersTest do
  use ExUnit.Case, async: true

  alias LightningWeb.Live.Helpers.TableHelpers

  describe "sort_items/4" do
    test "sorts DateTime fields chronologically across a UTC month boundary" do
      # `<=`/`>=` (sort_items's compare_fn) does structural compare on
      # `DateTime`, which walks struct keys alphabetically (day before month
      # before year) and inverts at month boundaries. Pin chronological
      # ordering with timestamps that straddle April 30 / May 1.
      items = [
        %{name: "April", inserted_at: ~U[2026-04-30 23:10:00Z]},
        %{name: "May", inserted_at: ~U[2026-05-01 01:10:00Z]},
        %{name: "Earlier", inserted_at: ~U[2026-04-30 21:10:00Z]}
      ]

      sort_map = %{"inserted_at" => :inserted_at}

      asc = TableHelpers.sort_items(items, "inserted_at", "asc", sort_map)
      assert Enum.map(asc, & &1.name) == ["Earlier", "April", "May"]

      desc = TableHelpers.sort_items(items, "inserted_at", "desc", sort_map)
      assert Enum.map(desc, & &1.name) == ["May", "April", "Earlier"]
    end

    test "sorts function-keyed DateTime fields chronologically across a UTC month boundary" do
      # Same gotcha when the sort_map maps a key to a function returning a
      # DateTime, as with the admin projects "scheduled_deletion" sort.
      items = [
        %{name: "April", deletion: ~U[2026-04-30 23:10:00Z]},
        %{name: "May", deletion: ~U[2026-05-01 01:10:00Z]}
      ]

      sort_map = %{"deletion" => fn item -> item.deletion end}

      asc = TableHelpers.sort_items(items, "deletion", "asc", sort_map)
      assert Enum.map(asc, & &1.name) == ["April", "May"]

      desc = TableHelpers.sort_items(items, "deletion", "desc", sort_map)
      assert Enum.map(desc, & &1.name) == ["May", "April"]
    end

    test "sorts NaiveDateTime fields chronologically across a UTC month boundary" do
      items = [
        %{name: "April", at: ~N[2026-04-30 23:10:00]},
        %{name: "May", at: ~N[2026-05-01 01:10:00]}
      ]

      sort_map = %{"at" => :at}

      assert TableHelpers.sort_items(items, "at", "desc", sort_map)
             |> Enum.map(& &1.name) == ["May", "April"]
    end

    test "sorts Date fields chronologically across a month boundary" do
      items = [
        %{name: "April", on: ~D[2026-04-30]},
        %{name: "May", on: ~D[2026-05-01]}
      ]

      sort_map = %{"on" => :on}

      assert TableHelpers.sort_items(items, "on", "desc", sort_map)
             |> Enum.map(& &1.name) == ["May", "April"]
    end

    test "sorts Time fields chronologically" do
      items = [
        %{name: "Late", at: ~T[23:10:00]},
        %{name: "Early", at: ~T[01:10:00]}
      ]

      sort_map = %{"at" => :at}

      assert TableHelpers.sort_items(items, "at", "asc", sort_map)
             |> Enum.map(& &1.name) == ["Early", "Late"]
    end

    test "treats nil sort values as the lowest, both for missing fields and explicit nil" do
      items = [
        %{name: "Has", scheduled: ~U[2026-05-01 00:00:00Z]},
        %{name: "Nil", scheduled: nil},
        %{name: "Missing"}
      ]

      sort_map = %{"scheduled" => :scheduled}

      asc = TableHelpers.sort_items(items, "scheduled", "asc", sort_map)
      # Nil and missing both normalize to "", which is the empty-string lowest
      # value; "Has" comes last because its ISO 8601 timestamp sorts greater.
      assert List.last(asc).name == "Has"

      assert Enum.take(asc, 2) |> Enum.map(& &1.name) |> Enum.sort() == [
               "Missing",
               "Nil"
             ]
    end

    test "leaves order unchanged when the sort key is not in the sort_map" do
      # When sort_map has no entry for the key, sort_field falls back to the
      # raw string key. `get_sort_value/2`'s catch-all returns the field
      # unchanged, so every item gets the same value, and stable sort
      # preserves input order.
      items = [
        %{name: "First"},
        %{name: "Second"},
        %{name: "Third"}
      ]

      assert TableHelpers.sort_items(items, "unknown", "asc", %{})
             |> Enum.map(& &1.name) == ["First", "Second", "Third"]

      assert TableHelpers.sort_items(items, "unknown", "desc", %{})
             |> Enum.map(& &1.name) == ["First", "Second", "Third"]
    end

    test "sorts plain string fields lexicographically" do
      items = [
        %{name: "Bob"},
        %{name: "Alice"},
        %{name: "Charlie"}
      ]

      sort_map = %{"name" => :name}

      assert TableHelpers.sort_items(items, "name", "asc", sort_map)
             |> Enum.map(& &1.name) == ["Alice", "Bob", "Charlie"]

      assert TableHelpers.sort_items(items, "name", "desc", sort_map)
             |> Enum.map(& &1.name) == ["Charlie", "Bob", "Alice"]
    end

    test "keeps nil and a real 1970-01-01 timestamp cleanly separated" do
      # The sort-key normalizer returns a sentinel tuple ({0, _} for nil,
      # {1, _} for present) so nil rows can never tie with a real
      # `~U[1970-01-01]` row even though both would otherwise normalize
      # toward the empty string / unix epoch.
      items = [
        %{name: "Epoch", at: ~U[1970-01-01 00:00:00Z]},
        %{name: "Nil", at: nil}
      ]

      sort_map = %{"at" => :at}

      asc = TableHelpers.sort_items(items, "at", "asc", sort_map)
      assert Enum.map(asc, & &1.name) == ["Nil", "Epoch"]

      desc = TableHelpers.sort_items(items, "at", "desc", sort_map)
      assert Enum.map(desc, & &1.name) == ["Epoch", "Nil"]
    end
  end

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
