defmodule Lightning.AuditHelpers do
  @moduledoc false

  @doc """
  Disable transaction capture for the duration of the block.
  """
  defmacro with_disabled_audit(do: block) do
    quote do
      disable_transaction_capture()
      res = unquote(block)
      enable_transaction_capture()
      res
    end
  end

  @doc """
  Insert a 'blank' audit record.

  This is useful when transaction capture is enabled, and you are using
  factories to create records in your tests. This will ensure that the
  you can still capture audit records for the transaction, _and_ use ExMachina
  factories to create records in your tests.

  An alternative approach would be to use `with_disabled_audit/1` which
  disables transaction capture just for that call.

  See [Testing / Bypassing Carbonite](https://github.com/bitcrowd/carbonite?tab=readme-ov-file#testing--bypassing-carbonite)
  """
  def insert_empty_audit() do
    Carbonite.insert_transaction(Lightning.Repo, %{},
      carbonite_prefix: Lightning.Config.audit_schema()
    )
  end

  def enable_transaction_capture(context) when is_map(context) do
    if context |> Map.get(:disable_audit) do
      disable_transaction_capture()
      context
    else
      enable_transaction_capture()
      context
    end
  end

  def enable_transaction_capture() do
    override_mode(:capture)
  end

  def disable_transaction_capture() do
    override_mode(:ignore)
  end

  defp override_mode(mode) do
    Carbonite.override_mode(Lightning.Repo,
      to: mode,
      carbonite_prefix: Lightning.Config.audit_schema()
    )
  end
end
