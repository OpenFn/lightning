defmodule Lightning.Collaboration.Utils do
  @moduledoc false

  @doc """
  Deciphers a Yjs protocol message into its constituent parts.

  This function handles two main categories of Yjs protocol messages:

  ## Sync Messages
  Sync messages are used for document state synchronization between clients.
  They contain three possible message types:

  - `:sync_step1` - Initial synchronization request containing an encoded state
    vector. Used to initiate the sync process by advertising what the client
    currently knows about the document state.

  - `:sync_step2` - Response to sync_step1 containing the document state that
    the requesting client needs to get up to date. Contains the actual document
    updates.

  - `:sync_update` - Incremental document updates that are broadcast to all
    connected clients when changes occur. Contains encoded document diffs.

  ## Awareness Messages
  Awareness messages contain information about client presence and state:

  - `:awareness` - Contains encoded client awareness data such as cursor
    positions, selections, user information, and other ephemeral state that
    helps coordinate collaborative editing sessions.

  ## Returns

  - `{:sync_step1, binary}` - Initial sync message with encoded state vector
  - `{:sync_step2, binary}` - Sync response with document state updates
  - `{:sync_update, binary}` - Incremental document update
  - `{:awareness, binary}` - Client awareness/presence information
  - `{:error, reason}` - Decoding failed

  The returned binary data is filtered to contain only printable characters
  and whitespace for safe string representation.

  ## Examples

      iex> decipher_message(sync_step1_binary)
      {:sync_step1, "filtered_printable_content"}

      iex> decipher_message(awareness_binary)
      {:awareness, "user_presence_data"}

      iex> decipher_message(invalid_binary)
      {:error, :invalid_message}
  """
  @spec decipher_message(binary()) :: {atom(), binary()} | {:error, any()}
  def decipher_message(payload) do
    case Yex.Sync.message_decode(payload) do
      {:ok, {:sync, {type, binary}}} ->
        {type, safe_binary_to_string(binary)}

      {:ok, {:awareness, binary}} ->
        {:awareness, safe_binary_to_string(binary)}

      # For some reason the :custom message can't be found in the typespecs
      {:ok, other} ->
        {:unknown, other}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp safe_binary_to_string(binary) do
    binary
    |> :binary.bin_to_list()
    # printable + whitespace
    |> Enum.filter(&(&1 in 32..126 or &1 in [9, 10, 13]))
    |> List.to_string()
  end
end
