defmodule Lightning.Extensions.CollectionHooking do
  @moduledoc """
  Callbacks for additional processing on collections operations.
  """
  alias Lightning.Collections.Collection

  @type limit_error :: {:error, :exceeds_limit, Lightning.Extensions.Message.t()}

  @callback handle_create(attrs :: map()) :: :ok | limit_error()

  @callback handle_delete(
              project_id :: Ecto.UUID.t(),
              delta_size :: neg_integer()
            ) :: :ok

  @callback handle_put_items(Collection.t(), delta_size :: integer()) ::
              :ok | limit_error()

  @callback handle_delete_items(Collection.t(), delta_size :: neg_integer()) ::
              :ok
end
