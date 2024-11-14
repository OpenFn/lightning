defmodule Lightning.WorkOrders.ExportAudit do
  @moduledoc """
  Module to log history export actions as audit events.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "history_export",
    events: ["requested"]
end
