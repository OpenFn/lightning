alias Lightning.Repo
alias Lightning.Collections
alias Lightning.Projects

IO.puts "### Indexes on collection_items table"
%{rows: rows} = Repo.query!("select indexname, indexdef from pg_indexes where tablename = 'collection_items'")
Enum.each(rows, &IO.puts(Enum.join(&1, ":\n")))

keys_count = 5_000
rounds = 300
# keys_count = 10_000
# rounds = 1

Repo.delete_all(Collections.Collection)

project =
  with nil <- Repo.get_by(Projects.Project, name: "bench") do
    user = Repo.get_by(Lightning.Accounts.User, email: "demo@openfn.org") || raise "This benchmark requires demo/known user"
    {:ok, project} = Projects.create_project(%{name: "bench", project_users: [%{user_id: user.id, role: :owner}]})
    project
  end

{:ok, collection1} =
  with {:error, :not_found} <- Collections.get_collection("bench1") do
    Collections.create_collection(%{"project_id" => project.id, "name" => "bench1"})
  end

{:ok, collection2} =
  with {:error, :not_found} <- Collections.get_collection("bench2") do
    Collections.create_collection(%{"project_id" => project.id, "name" => "bench2"})
  end

record1 = fn prefix, i ->
  i_str = String.pad_leading(to_string(i), 5, "0")
  %{
    "key" => "#{prefix}:foo#{i_str}:bar#{i_str}",
    "value" => Jason.encode!(%{
      someid1: "soo#{1_000_000 + i}",
      somefield1: "zar#{1_000_000 + i}",
      anotherfield1: "yaz#{1_000_000 + i}"})
  }
end

record2 = fn prefix, i ->
  i_str = String.pad_leading(to_string(i), 5, "0")
  %{
    "key" => "#{prefix}:foo#{i_str}:bar#{i_str}",
    "value" => Jason.encode!(%{
      someid2: "soo#{1_000_000 + i}",
      somefield2: "zar#{1_000_000 + i}",
      anotherfield2: "yaz#{1_000_000 + i}"})
  }
end

samples1 =
  1..keys_count * rounds
  |> Enum.map(fn i -> record1.("keyA", i) end)
  |> Enum.chunk_every(keys_count)

samples2 =
  1..keys_count * rounds
  |> Enum.map(fn i -> record2.("keyB", i) end)
  |> Enum.chunk_every(keys_count)

IO.puts("\n### Inserting #{rounds} rounds of 2x#{keys_count} with put_all...")

durations =
  Enum.zip(samples1, samples2)
  |> Enum.flat_map(fn {sample1, sample2} -> [{sample1, collection1}, {sample2, collection2}] end)
  |> Task.async_stream(fn {sample, collection} ->
    {duration, _res} = :timer.tc(fn ->
      {:ok, _n} = Collections.put_all(collection, sample)
    end)

    div(duration, 1_000)
  end, max_concurrency: 2, timeout: :infinity)
  |> Enum.map(fn {:ok, duration_ms} ->
    IO.puts("elapsed time: #{duration_ms}ms")
    duration_ms
  end)

IO.puts "Average: #{Statistics.mean(durations)}ms"
IO.puts "Std Deviation: #{Statistics.stdev(durations)}ms"
