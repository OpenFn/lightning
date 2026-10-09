defmodule Lightning.Collections.Audit do
  @moduledoc """
  Audit events for collections: who created one, and who renamed it.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "collection",
    events: ["created", "updated"]
end
