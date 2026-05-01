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
  end
end
