defmodule Lightning.PartitionTableServiceTest do
  use Lightning.DataCase, async: false

  import Lightning.Factories

  alias Lightning.PartitionTableService, as: Service

  describe "perform" do
    test "adds additional partitions" do
      parent = "work_orders"

      drop_range_partitions(parent)

      add_partitions(parent)

      now = DateTime.utc_now()

      new_partitions =
        [
          now |> build_partition_name(parent),
          now |> date_with_offset(1) |> build_partition_name(parent),
          now |> date_with_offset(2) |> build_partition_name(parent)
        ]

      expected = modified_relations(new_partitions, all_relations())

      Service.perform(%Oban.Job{
        args: %{"add_headroom" => %{"weeks" => 2}}
      })

      assert all_relations() == expected
    end

    test "removes obsolete partitions" do
      parent = "work_orders"

      now = DateTime.now!("Etc/UTC")

      drop_range_partitions(parent)

      new_range_partitions =
        -2..3
        |> generate_partition_properties(now)
        |> Enum.map(&partition_name(&1, parent))

      new_partitions = ["#{parent}_default" | new_range_partitions]

      expected = modified_relations(new_partitions, all_relations())

      generate_partitions(-6..3, now, parent)

      Service.perform(%Oban.Job{
        args: %{"drop_older_than" => %{"weeks" => -2}}
      })

      assert all_relations() == expected
    end
  end

  test "gets a list of partitions for a given parent" do
    parent = "work_orders"

    drop_range_partitions(parent)

    add_partitions(parent)

    expected = [
      "#{parent}_2023_01",
      "#{parent}_2023_02",
      "#{parent}_2023_03",
      "#{parent}_default"
    ]

    assert Service.get_partitions("work_orders") |> Enum.sort() == expected
  end

  test "tables_to_add returns tables that do not already exist" do
    now = DateTime.now!("Etc/UTC")

    parent = "work_orders"

    drop_range_partitions(parent)

    existing_partition_properties =
      0..3
      |> Enum.map(&date_with_offset(now, &1))
      |> generate_partition_properties()

    generate_partitions(existing_partition_properties, parent)

    expected_additional_partitions =
      4..6
      |> Enum.map(&date_with_offset(now, &1))
      |> generate_partition_properties()
      |> Enum.map(fn properties ->
        {_, _, from, to} = properties

        {
          partition_name(properties, parent),
          from |> DateTime.to_date() |> Date.to_string(),
          to |> DateTime.to_date() |> Date.to_string()
        }
      end)
      |> Enum.sort_by(fn {a, _, _} -> a end, :asc)

    proposed_partitions = Service.tables_to_add(parent, 6) |> Enum.sort()

    assert proposed_partitions == expected_additional_partitions
  end

  test "add_headroom - all" do
    now = DateTime.now!("Etc/UTC")

    parent = "work_orders"

    drop_range_partitions(parent)

    expected_partitions =
      0..3
      |> Enum.map(&date_with_offset(now, &1))
      |> generate_partition_properties()
      |> Enum.map(&partition_name(&1, parent))

    expected = modified_relations(expected_partitions, all_relations())

    Service.add_headroom(:all, 3)

    assert all_relations() == expected
  end

  test "add_headroom - parent specified" do
    now = DateTime.now!("Etc/UTC")

    parent = "work_orders"

    drop_range_partitions(parent)

    new_partitions =
      0..3
      |> Enum.map(&date_with_offset(now, &1))
      |> generate_partition_properties()
      |> Enum.map(fn {_, _, from, _} -> from end)
      |> Enum.map(&build_partition_name(&1, parent))

    expected = modified_relations(new_partitions, all_relations())

    Service.add_headroom(:work_orders, 3)

    assert all_relations() == expected
  end

  test "remove_empty" do
    parent = "work_orders"

    now = DateTime.now!("Etc/UTC")

    drop_range_partitions(parent)

    expected_range_partitions =
      -2..3
      |> generate_partition_properties(now)
      |> Enum.map(&partition_name(&1, parent))

    new_partitions = ["#{parent}_default" | expected_range_partitions]

    expected = modified_relations(new_partitions, all_relations())

    generate_partitions(-6..3, now, parent)

    weeks_ago = Timex.shift(DateTime.utc_now(), weeks: -2)

    Service.remove_empty(parent, weeks_ago)

    assert all_relations() == expected
  end

  describe "list partitions" do
    test "returns partitions of the specified table" do
      drop_range_partitions("work_orders")

      add_partitions("work_orders")

      sort_fn = fn [name, _expression] -> name end

      expected =
        [
          [
            "work_orders_2023_01",
            "FOR VALUES FROM ('2023-01-01 00:00:00') TO ('2023-01-31 00:00:00')"
          ],
          [
            "work_orders_2023_02",
            "FOR VALUES FROM ('2023-02-01 00:00:00') TO ('2023-02-28 00:00:00')"
          ],
          [
            "work_orders_2023_03",
            "FOR VALUES FROM ('2023-03-01 00:00:00') TO ('2023-03-31 00:00:00')"
          ]
        ]
        |> Enum.sort_by(sort_fn, :asc)

      partitions =
        Service.find_range_partitions("work_orders")
        |> Enum.sort_by(sort_fn, :asc)

      assert partitions == expected
    end
  end

  describe "partitions_older_than" do
    test "it returns partition tables that end before the given datetime" do
      parent = "work_orders"
      bound = ~U[2023-04-29 23:59:59Z]
      partitions = input_partitions(parent)
      expected = ["#{parent}_2023_01", "#{parent}_2023_02", "#{parent}_2023_03"]

      assert Service.partitions_older_than(partitions, bound) == expected
    end

    defp input_partitions(parent) do
      [
        [
          "#{parent}_2023_01",
          "FOR VALUES FROM ('2023-01-01 00:00:00') TO ('2023-01-31 00:00:00')"
        ],
        [
          "#{parent}_2023_02",
          "FOR VALUES FROM ('2023-02-01 00:00:00') TO ('2023-02-28 00:00:00')"
        ],
        [
          "#{parent}_2023_03",
          "FOR VALUES FROM ('2023-03-01 00:00:00') TO ('2023-03-31 00:00:00')"
        ],
        [
          "#{parent}_2023_04",
          "FOR VALUES FROM ('2023-04-01 00:00:00') TO ('2023-04-30 00:00:00')"
        ],
        [
          "#{parent}_2023_05",
          "FOR VALUES FROM ('2023-05-01 00:00:00') TO ('2023-05-31 00:00:00')"
        ]
      ]
    end
  end

  describe "drop_empty_partition" do
    test "drops the named partition" do
      parent = "work_orders"

      drop_range_partitions(parent)

      add_partitions(parent)

      expected =
        [
          "#{parent}",
          "#{parent}_2023_01",
          "#{parent}_2023_03",
          "#{parent}_default",
          "#{parent}_monolith"
        ]
        |> Enum.sort()

      Service.drop_empty_partition(parent, "#{parent}_2023_02")

      assert associated_relations(all_relations(), parent) == expected
    end

    test "does nothing if the table is not empty" do
      parent = "work_orders"

      drop_range_partitions(parent)

      add_partitions(parent)

      expected =
        [
          "#{parent}",
          "#{parent}_2023_01",
          "#{parent}_2023_02",
          "#{parent}_2023_03",
          "#{parent}_default",
          "#{parent}_monolith"
        ]
        |> Enum.sort()

      insert(:workorder, inserted_at: ~U[2023-02-15 10:00:00Z])

      Service.drop_empty_partition(parent, "#{parent}_2023_02")

      assert associated_relations(all_relations(), parent) == expected
    end

    test "errors out if the parent contains unexpected chars" do
      parent = "work_orders"

      drop_range_partitions(parent)

      add_partitions(parent)

      assert_raise(
        ArgumentError,
        fn ->
          Service.drop_empty_partition("#{parent} --", "#{parent}_2023_02")
        end
      )

      expected =
        [
          "#{parent}",
          "#{parent}_2023_01",
          "#{parent}_2023_02",
          "#{parent}_2023_03",
          "#{parent}_default",
          "#{parent}_monolith"
        ]
        |> Enum.sort()

      assert associated_relations(all_relations(), parent) == expected
    end

    test "errors out if the partition contains unexpected chars" do
      parent = "work_orders"

      drop_range_partitions(parent)

      add_partitions(parent)

      assert_raise(
        ArgumentError,
        fn ->
          Service.drop_empty_partition(parent, "#{parent}_2023_2 --")
        end
      )

      expected =
        [
          "#{parent}",
          "#{parent}_2023_01",
          "#{parent}_2023_02",
          "#{parent}_2023_03",
          "#{parent}_default",
          "#{parent}_monolith"
        ]
        |> Enum.sort()

      assert associated_relations(all_relations(), parent) == expected
    end
  end

  defp all_relations() do
    Repo.query!(~S[
      SELECT c.relname
      FROM pg_catalog.pg_class c
      LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      LEFT JOIN pg_catalog.pg_am am ON am.oid = c.relam
      WHERE c.relkind IN ('r','p','')
      AND n.nspname <> 'pg_catalog'
      AND n.nspname !~ '^pg_toast'
      AND n.nspname <> 'information_schema'
      AND pg_catalog.pg_table_is_visible(c.oid);
    ]).rows
    |> List.flatten()
    |> Enum.sort()
  end

  defp week(date) do
    {_year, week} = Timex.iso_week(date)

    week
  end

  defp build_partition_name(date, parent) do
    {year, week} = Timex.iso_week(date)

    padded_week = week |> Integer.to_string() |> String.pad_leading(2, "0")

    "#{parent}_#{year}_#{padded_week}"
  end

  defp drop_range_partitions(parent) do
    all_relations()
    |> Enum.filter(&(&1 =~ ~r/\A#{parent}_[2d]/))
    |> Enum.each(fn partition ->
      Repo.query!("ALTER TABLE #{parent} DETACH PARTITION #{partition};")
      Repo.query!("DROP TABLE #{partition};")
    end)
  end

  defp add_partitions(parent) do
    [
      {"2023", "1", "2023-01-01", "2023-01-31"},
      {"2023", "2", "2023-02-01", "2023-02-28"},
      {"2023", "3", "2023-03-01", "2023-03-31"}
    ]
    |> Enum.each(&create_range_partition(&1, parent))

    create_default_partition(parent)
  end

  defp create_range_partition(partition_properties, parent) do
    {_year, _num, from, to} = partition_properties

    Repo.query!("""
    CREATE TABLE #{partition_name(partition_properties, parent)}
    PARTITION OF #{parent}
    FOR VALUES FROM ('#{from}') TO ('#{to}')
    """)
  end

  defp partition_name({year, num, _, _}, parent) when is_binary(num) do
    padded_num = num |> String.pad_leading(2, "0")

    "#{parent}_#{year}_#{padded_num}"
  end

  defp partition_name({year, num, _, _}, parent) when is_integer(num) do
    padded_num = num |> Integer.to_string() |> String.pad_leading(2, "0")

    "#{parent}_#{year}_#{padded_num}"
  end

  defp create_default_partition(parent) do
    Repo.query!("""
    CREATE TABLE #{parent}_default
    PARTITION OF #{parent}
    DEFAULT
    """)
  end

  defp associated_relations(relations, parent) do
    relations
    |> Enum.filter(&(&1 =~ ~r/\A#{parent}/))
    |> Enum.sort()
  end

  defp generate_partition_properties(dates) do
    dates
    |> Enum.map(fn from ->
      shifted_from = from |> shift_to_monday()
      to = range_end(shifted_from)

      {from.year, week(from), shifted_from, to}
    end)
  end

  defp generate_partition_properties(range, now) do
    range
    |> Enum.map(fn week_offset ->
      from = date_with_offset(now, week_offset) |> shift_to_monday()
      to = range_end(from)

      {from.year, normalise_counter(week_offset), from, to}
    end)
  end

  defp normalise_counter(counter) when counter < 0 do
    "minus_#{abs(counter)}"
  end

  defp normalise_counter(counter) when counter >= 0 do
    "#{counter}"
  end

  defp generate_partitions(properties, parent) do
    properties
    |> Enum.map(&create_range_partition(&1, parent))

    create_default_partition(parent)
  end

  defp generate_partitions(range, now, parent) do
    range
    |> generate_partition_properties(now)
    |> Enum.map(&create_range_partition(&1, parent))

    create_default_partition(parent)
  end

  defp date_with_offset(now, offset) do
    DateTime.add(now, 7 * offset, :day)
  end

  defp range_end(range_start) do
    DateTime.add(range_start, 7, :day)
  end

  defp shift_to_monday(date) do
    date |> Timex.beginning_of_week(:mon)
  end

  defp modified_relations(new_relations, existing_relations) do
    [new_relations | existing_relations] |> List.flatten() |> Enum.sort()
  end
end
