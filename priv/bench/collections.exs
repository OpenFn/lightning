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
  with {:error, :collection_not_found} <- Collections.get_collection("benchee") do
    Collections.create_collection(project.id, "benchee")
  end

IO.puts("\n### Setup:")
IO.puts("Generating items for benchee collection...")

record = fn prefix, i ->
  i_str = String.pad_leading(to_string(i), 5, "0")
  {"#{prefix}:foo#{i_str}:bar#{i_str}", Jason.encode!(%{fieldA: "value#{1_000_000 + i}"})}
end

sampleA = Enum.map(1..keys_count, fn i -> record.("keyA", i) end)
sampleB = Enum.map(1..keys_count, fn i -> record.("keyB", i) end)
sampleC = Enum.map(1..keys_count * 2, fn i -> record.("keyC", i) end)

begin = System.monotonic_time(:millisecond)

Enum.shuffle(sampleA ++ sampleB ++ sampleC)
|> Enum.each(fn {key, value} ->
  :ok = Collections.put(collection, key, value)
end)

IO.puts("Inserted 4 x #{keys_count} items (w/ unsorted keys).")
IO.puts("elapsed time: #{System.monotonic_time(:millisecond)-begin}ms\n")

sampleD = Enum.map(1..keys_count, fn i -> record.("keyD", i) end)

begin = System.monotonic_time(:millisecond)
IO.puts("Inserting sampleD (w/ sorted keys)...")
Enum.each(sampleD, fn {k, v} -> Collections.put(collection, k, v) end)
IO.puts("elapsed time: #{System.monotonic_time(:millisecond)-begin}ms\n")

begin = System.monotonic_time(:millisecond)
IO.puts("Upserting sampleD...")
Enum.each(sampleD, fn {k, v} -> Collections.put(collection, k, v) end)
IO.puts("elapsed time: #{System.monotonic_time(:millisecond)-begin}ms\n")

stream_all =
  fn ->
    Stream.unfold(nil, fn cursor ->
      case Repo.transaction(fn -> Collections.stream_all(collection, cursor) |> Enum.to_list() end) do
        {:ok, []} -> nil
        {:ok, list} -> {list, List.last(list).updated_at}
      end
    end)
    |> Enum.to_list()
    |> List.flatten()
  end

stream_match_all =
  fn ->
    Stream.unfold(nil, fn cursor ->
      case Repo.transaction(fn -> Collections.stream_match(collection, "key*", cursor) |> Enum.to_list() end) do
        {:ok, []} -> nil
        {:ok, list} -> {list, List.last(list).updated_at}
      end
    end)
    |> Enum.to_list()
    |> List.flatten()
  end

stream_match_prefix =
  fn ->
    Stream.unfold(nil, fn cursor ->
      case Repo.transaction(fn -> Collections.stream_match(collection, "keyA*", cursor) |> Enum.to_list() end) do
        {:ok, []} -> nil
        {:ok, list} -> {list, List.last(list).updated_at}
      end
    end)
    |> Enum.to_list()
    |> List.flatten()
  end

stream_match_trigram =
  fn ->
    Stream.unfold(nil, fn cursor ->
      case Repo.transaction(fn -> Collections.stream_match(collection, "keyB*bar*", cursor) |> Enum.to_list() end) do
        {:ok, []} -> nil
        {:ok, list} -> {list, List.last(list).updated_at}
      end
    end)
    |> Enum.to_list()
    |> List.flatten()
  end


IO.puts("\n### Round record count:")
stream_all.() |> Enum.count() |> IO.inspect(label: "stream_all")
stream_match_all.() |> Enum.count() |> IO.inspect(label: "stream_match_all")
stream_match_prefix.() |> Enum.count() |> IO.inspect(label: "stream_match_prefix")
stream_match_trigram.() |> Enum.count() |> IO.inspect(label: "stream_match_trigram")
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
