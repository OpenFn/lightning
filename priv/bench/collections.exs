alias Lightning.Repo
alias Lightning.Collections
alias Lightning.Projects

keys_count = 5_000

Repo.delete_all(Collections.Collection)

project =
  with nil <- Repo.get_by(Projects.Project, name: "benchee") do
    user = Repo.get_by(Lightning.Accounts.User, email: "demo@openfn.org")
    {:ok, project} = Projects.create_project(%{name: "benchee", project_users: [%{user_id: user.id, role: :owner}]})
    project
  end

{:ok, collection} =
  with {:error, :not_found} <- Collections.get_collection("benchee") do
    Collections.create_collection(%{"project_id" => project.id, "name" => "benchee"})
  end

IO.puts("\n### Setup:")
IO.puts("Generating items for benchee collection...")

record = fn prefix, i ->
  i_str = String.pad_leading(to_string(i), 5, "0")
  {"#{prefix}:foo#{i_str}:bar#{i_str}", Jason.encode!(%{fieldA: "value#{1_000_000 + i}"})}
end

sampleA = Enum.map(1..keys_count, fn i -> record.("keyA", i) end)
sampleB = Enum.map(1..keys_count, fn i -> record.("keyB", i) end)
sampleC1 = Enum.map(1..keys_count, fn i -> record.("keyC", i) end)
sampleC2 =
  keys_count..keys_count * 2
  |> Enum.map(fn i -> record.("keyC", i) end)
  |> Enum.map(fn {k, v} -> %{"key" => k, "value" => v} end)

:timer.tc(fn ->
  [sampleA, sampleB, sampleC1]
  |> Enum.map(fn sample ->
    Task.async(fn ->
      Enum.with_index(sample, fn {key, value}, idx ->
        if rem(idx, 1000) == 0, do: IO.puts("Inserting " <> key)
        :ok = Collections.put(collection, key, value)
      end)
      :ok
    end)
  end)
  |> Task.await_many(:infinity)
end)
|> tap(fn {duration, _res} ->
  IO.puts("Inserted 3 x #{keys_count} shuffled items (w/ unsorted keys).")
  IO.puts("elapsed time: #{div(duration, 1_000)}ms\n")
end)

IO.puts("Inserting #{length(sampleC2)} items with put_all...")
:timer.tc(fn ->
  {:ok, _n} = Collections.put_all(collection, sampleC2)
end)
|> tap(fn {duration, _res} ->
  IO.puts("elapsed time: #{div(duration, 1_000)}ms\n")
end)

sampleD = Enum.map(1..keys_count, fn i -> record.("keyD", i) end)

IO.puts("Inserting sampleD (w/ sorted keys)...")
:timer.tc(fn ->
  sampleD
  |> Enum.chunk_every(1000)
  |> Enum.map(fn sample ->
    Task.async(fn ->
      Enum.each(sample, fn {k, v} -> Collections.put(collection, k, v) end)
    end)
  end)
  |> Task.await_many(:infinity)
end)
|> tap(fn {duration, _res} ->
  IO.puts("elapsed time: #{div(duration, 1000)}ms\n")
end)

IO.puts("Upserting sampleD...")
:timer.tc(fn ->
  sampleD
  |> Enum.chunk_every(1000)
  |> Enum.map(fn sample ->
    Task.async(fn ->
      Enum.each(sample, fn {k, v} -> Collections.put(collection, k, v) end)
    end)
  end)
  |> Task.await_many(:infinity)
end)
|> tap(fn {duration, _res} ->
  IO.puts("elapsed time: #{div(duration, 1000)}ms\n")
end)

stream_all =
  fn ->
    Stream.unfold(nil, fn cursor ->
      case Collections.get_all(collection, %{cursor: cursor, limit: 500}) do
        [] -> nil
        list -> {list, List.last(list).updated_at}
      end
    end)
    |> Enum.to_list()
    |> List.flatten()
  end

stream_match_all =
  fn ->
    Stream.unfold(nil, fn cursor ->
      case Collections.get_all(collection, %{cursor: cursor, limit: 500}, "key*") do
        [] -> nil
        list -> {list, List.last(list).updated_at}
      end
    end)
    |> Enum.to_list()
    |> List.flatten()
  end

stream_match_prefix =
  fn ->
    Stream.unfold(nil, fn cursor ->
      case Collections.get_all(collection, %{cursor: cursor, limit: 500}, "keyA*") do
        [] -> nil
        list -> {list, List.last(list).updated_at}
      end
    end)
    |> Enum.to_list()
    |> List.flatten()
  end

stream_match_trigram =
  fn ->
    Stream.unfold(nil, fn cursor ->
        case Collections.get_all(collection, %{cursor: cursor, limit: 500}, "keyB*bar*") do
        [] -> nil
        list -> {list, List.last(list).updated_at}
      end
    end)
    |> Enum.to_list()
    |> List.flatten()
  end

# Process.exit(self(), :normal)

IO.puts("\n### Round record count ({microsecs, count}):")
:timer.tc(fn -> stream_all.() |> Enum.count() end) |> then(&IO.puts("stream_all: #{&1}"))
:timer.tc(fn -> stream_match_all.() |> Enum.count() end) |> then(&IO.puts("stream_match_all: #{&1}"))
:timer.tc(fn -> stream_match_prefix.() |> Enum.count() end) |> then(&IO.puts("stream_match_prefix: #{&1}"))
:timer.tc(fn -> stream_match_trigram.() |> Enum.count() end) |> then(&IO.puts("stream_match_trigram: #{&1}"))
IO.puts("\n")

Benchee.run(
  %{
    "stream_all" => stream_all,
    "stream_match_all" => stream_match_all,
    "stream_match_prefix" => stream_match_prefix,
    "stream_match_trigram" => stream_match_trigram
  },
  warmup: 2,
  time: 5,
  parallel: 1
)

Benchee.run(
  %{
    "stream_all" => stream_all,
    "stream_match_all" => stream_match_all,
    "stream_match_prefix" => stream_match_prefix,
    "stream_match_trigram" => stream_match_trigram
  },
  warmup: 2,
  time: 5,
  parallel: 4
)
