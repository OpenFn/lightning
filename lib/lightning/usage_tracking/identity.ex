defmodule Lightning.UsageTracking.Identity do
  @moduledoc """
  Hashes the UUIDs that usage reports carry in place of cleartext identifiers.
  """

  def hash(uuid), do: Base.encode16(:crypto.hash(:sha256, uuid))
end
