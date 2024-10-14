defmodule Lightning.KafkaTriggers.MessageRecovery do
  alias Lightning.KafkaTriggers.Pipeline

  def recover_messages(base_dir_path) do
    error_count =
      base_dir_path
      |> File.ls!()
      |> Enum.map(
        &Path.join(base_dir_path, &1)
      )
      |> Enum.filter(&File.dir?/1)
      |> Enum.flat_map(fn dir_path ->
        File.ls!(dir_path)
        |> Enum.map(&Path.join(dir_path, &1))
      end)
      |> Enum.filter(fn file_path -> Path.extname(file_path) == ".json" end)
      |> Enum.reduce(0, fn file_path, error_counter ->
        %{"data" => data, "metadata" => metadata} =
          File.read!(file_path)
          |> Jason.decode!()

        metadata =
          metadata
          |> Enum.reduce(%{}, fn {key, value}, acc ->
            Map.put(acc, String.to_atom(key), value)
          end)

        message =
          %Broadway.Message{
            acknowledger: %{},
            data: data,
            metadata: metadata
          }

        trigger_id =
          Path.basename(file_path)
          |> String.split("_")
          |> List.first()
          |> String.to_atom()

        %{status: status} = 
          Pipeline.handle_message(
            nil,
            message,
            %{trigger_id: trigger_id}
          )

        if status == :ok do
          File.rename!(file_path, "#{file_path}.recovered")
          error_counter
        else
          error_counter + 1
        end
      end)

    if error_count == 0, do: :ok, else: {:error, error_count}
  end
end
