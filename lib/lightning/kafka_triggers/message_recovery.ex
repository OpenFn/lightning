defmodule Lightning.KafkaTriggers.MessageRecovery do
  @moduledoc """
  This module contains functionality to recover Kafka messages that have been
  persisted to the file system. It should only be used to process files that
  originate from a trusted source (i.e. Lightning's Kafka pipeline.)

  It expects to be pointed at a directory structure that looks as follows:

  base_path
  |_ <workflow_id>
    |_ <trigger_id>_<topic>_<partition>_<offset>.json
    |_ <trigger_id>_<topic>_<partition>_<offset>.json
  |_ <workflow_id>

  This is the structure that the Kafka pipeline will use when writing the
  messages to the file system. After each message is successfully processed,
  the file extension will be changed from `.json` to `json.recovered`. Recovered
  files will not be processed again. They are retained for the purposes of 
  double-checking the recovery process and can be deleted once this has been
  done.

  If a file has not had the extension changed, this means that it experienced
  an error during reprocessing. These files can be reprocessed if you think the
  error was transient. 

  Usage: 

    alias Lightning.KafkaTriggers.MessageRecovery
    case MessageRecovery.recover_messages(Lightning.Config.kafka_alternate_storage_file_path) do
      :ok -> # Success code
      {:error, error_count} -> # Failure code
    end
  """

  alias Broadway.Message
  alias Lightning.KafkaTriggers.Pipeline

  # Dialyzer is having trouble with the type definition for Broadway.Message
  # and is using one that is different to what is defined within the
  # Broadway code base.
  @dialyzer {:no_match, recover_messages: 1}
  def recover_messages(base_dir_path) do
    error_count =
      find_recoverable_files(base_dir_path)
      |> Enum.reduce(0, fn file_path, error_counter ->
        %{"data" => data, "metadata" => metadata} =
          deserialise_contents(file_path)

        metadata = convert_keys_to_atoms(metadata)

        message = build_broadway_message(data, metadata)

        Pipeline.handle_message(
          nil,
          message,
          %{trigger_id: extract_trigger_id(file_path)}
        )
        |> case do
          %{status: :ok} ->
            File.rename!(file_path, "#{file_path}.recovered")
            error_counter

          _any_error_state ->
            error_counter + 1
        end
      end)

    if error_count == 0, do: :ok, else: {:error, error_count}
  end

  defp find_recoverable_files(base_dir_path) do
    base_dir_path
    |> File.ls!()
    |> Enum.map(&Path.join(base_dir_path, &1))
    |> Enum.filter(&File.dir?/1)
    |> Enum.flat_map(fn dir_path ->
      File.ls!(dir_path)
      |> Enum.map(&Path.join(dir_path, &1))
    end)
    |> Enum.filter(fn file_path -> Path.extname(file_path) == ".json" end)
  end

  defp deserialise_contents(file_path) do
    File.read!(file_path) |> Jason.decode!()
  end

  defp convert_keys_to_atoms(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, String.to_atom(key), value)
    end)
  end

  def build_broadway_message(data, metadata) do
    %Message{
      acknowledger: Broadway.NoopAcknowledger.init(),
      data: data,
      metadata: metadata
    }
  end

  def extract_trigger_id(file_path) do
    Path.basename(file_path)
    |> String.split("_")
    |> List.first()
    |> String.to_atom()
  end
end
