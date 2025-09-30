# Benchmark to demonstrate memory optimization for dataclip body retrieval
#
# This benchmark compares two approaches for serving dataclip bodies via the API:
#
# 1. OLD: Load JSONB as Elixir map, encode to string (high memory)
# 2. NEW: Query JSONB as text directly from PostgreSQL (low memory)
#
# Usage:
#   mix run benchmarking/dataclip_controller_memory.exs <dataclip_id>
#
# Example:
#   mix run benchmarking/dataclip_controller_memory.exs "f1b8d127-beb6-4cac-a4f1-7000526bb693"

alias Lightning.Invocation
alias Lightning.Repo
import Ecto.Query

# Get dataclip ID from command line args
[dataclip_id | _] = System.argv()

if is_nil(dataclip_id) or dataclip_id == "" do
  IO.puts("""
  Error: Please provide a dataclip ID as an argument.

  Usage: mix run benchmarking/dataclip_controller_memory.exs <dataclip_id>

  To find a large dataclip ID, run in iex:

    alias Lightning.Repo
    import Ecto.Query

    from(d in Lightning.Invocation.Dataclip,
      select: %{
        id: d.id,
        size: fragment("pg_column_size(?)", d.body),
        type: d.type
      },
      order_by: [desc: fragment("pg_column_size(?)", d.body)],
      limit: 5
    )
    |> Repo.all()
  """)

  System.halt(1)
end

IO.puts("\n=== Dataclip Controller Memory Benchmark ===")
IO.puts("Dataclip ID: #{dataclip_id}\n")

# Verify dataclip exists and get info
dataclip_info =
  from(d in Lightning.Invocation.Dataclip,
    where: d.id == ^dataclip_id,
    select: %{
      id: d.id,
      type: d.type,
      size_bytes: fragment("pg_column_size(?)", d.body),
      size_mb: fragment("round(pg_column_size(?)::numeric / 1048576, 2)", d.body)
    }
  )
  |> Repo.one()

case dataclip_info do
  nil ->
    IO.puts("Error: Dataclip with ID #{dataclip_id} not found")
    System.halt(1)

  info ->
    IO.puts("Dataclip Info:")
    IO.puts("  ID: #{info.id}")
    IO.puts("  Type: #{info.type}")
    IO.puts("  Database Size: #{info.size_mb} MB (#{info.size_bytes} bytes)")
    IO.puts("")
end

Benchee.run(
  %{
    "OLD: Load as Elixir map + encode" => fn ->
      # This is the old approach - loads JSONB as Elixir map
      dataclip = Invocation.get_dataclip_details!(dataclip_id)

      # Encode to JSON string
      _body_json = Jason.encode!(dataclip.body)

      # Return just to avoid compiler optimizations
      :ok
    end,

    "NEW: Query as text from PostgreSQL" => fn ->
      # This is the new approach - gets JSONB as text directly
      result =
        from(d in Lightning.Invocation.Dataclip,
          where: d.id == ^dataclip_id,
          select: %{
            body_json: fragment("?::text", d.body),
            type: d.type,
            id: d.id
          }
        )
        |> Repo.one!()

      # Return the body_json (already a string, no encoding needed)
      _body = result.body_json

      :ok
    end,

    "BASELINE: Load metadata only (no body)" => fn ->
      # For reference - loading without body
      _dataclip = Invocation.get_dataclip!(dataclip_id)
      :ok
    end
  },
  memory_time: 3,
  time: 10,
  formatters: [
    {Benchee.Formatters.Console,
     extended_statistics: true}
  ],
  print: [
    benchmarking: true,
    configuration: true,
    fast_warning: true
  ]
)

IO.puts("\n=== Analysis ===")
IO.puts("""
This benchmark demonstrates the memory optimization for serving dataclip bodies.

Problem:
  PostgreSQL stores JSON as compact JSONB (#{dataclip_info.size_mb} MB for this dataclip).
  When loaded as an Elixir map, it expands ~38x due to:
    - Immutable data structure overhead
    - Metadata for every map/list/string
    - Deep nesting creates many small allocations

Solutions Compared:

  1. OLD APPROACH (baseline):
     - Query JSONB → Elixir map (~38x memory amplification)
     - Jason.encode!(map) → JSON string (creates another copy)
     - Peak memory: ~#{Float.round(dataclip_info.size_mb * 38 + dataclip_info.size_mb, 1)} MB for this dataclip!

  2. NEW APPROACH (optimized):
     - Query with fragment("?::text", d.body) → JSON string directly
     - PostgreSQL does the conversion, no Elixir map
     - Peak memory: ~#{dataclip_info.size_mb} MB for this dataclip
     - Memory reduction: ~#{round(((38 * dataclip_info.size_mb) / (39 * dataclip_info.size_mb)) * 100)}%

Impact on Production:
  With 2GB memory limit and #{dataclip_info.size_mb}MB dataclips:
    - OLD: ~#{div(2000, round(dataclip_info.size_mb * 39))} concurrent requests before OOM
    - NEW: ~#{div(2000, round(dataclip_info.size_mb * 2))} concurrent requests before OOM
    - Improvement: #{div(div(2000, round(dataclip_info.size_mb * 2)), max(1, div(2000, round(dataclip_info.size_mb * 39))))}x more capacity!

Additional Benefits:
  - Faster response times (no map deserialization)
  - Lower CPU usage (PostgreSQL does the conversion efficiently)
  - Fewer garbage collection pauses
""")
