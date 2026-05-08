defmodule Lightning.Workflows.YamlFormat.Importer do
  @moduledoc """
  Phase 5 import bridge.

  Sits between an inbound document (raw YAML string or already-parsed JSON
  map) and `Lightning.Projects.Provisioner.import_document/4`. Handles
  format detection (v1 vs v2) and the v2-specific UUID injection step that
  lets the Provisioner stay UUID-required.

  Two callers in scope:

    * `LightningWeb.API.ProvisioningController.create/2` — accepts JSON
      payloads which are either the legacy provisioner shape (treated as
      `:v1` and passed through unchanged) or v2 canonical shape.
    * Future YAML upload entrypoints — accept a raw YAML string of either
      version.
  """

  alias Lightning.Projects.Project
  alias Lightning.Projects.Provisioner
  alias Lightning.Workflows.YamlFormat

  @type input :: binary() | map()
  @type actor ::
          Lightning.Accounts.User.t()
          | Lightning.VersionControl.ProjectRepoConnection.t()

  @doc """
  Translate `input` into a provisioner-shaped document, using
  `existing_project` to preserve UUIDs by stable name where possible.

  Returns `{:ok, provisioner_doc}` on success, or any `{:error, _}` produced
  by `YamlFormat.parse_project/1`.
  """
  @spec to_provisioner_doc(input(), Project.t() | nil) ::
          {:ok, map()} | {:error, term()}
  def to_provisioner_doc(input, existing_project) do
    with {:ok, parsed_doc} <- YamlFormat.parse_project(input) do
      {:ok, YamlFormat.to_provisioner_doc(parsed_doc, existing_project)}
    end
  end

  @doc """
  Convenience that runs `to_provisioner_doc/2` and forwards into
  `Provisioner.import_document/4`. Returns whatever the provisioner
  returns, or a parse-stage error.
  """
  @spec import_document(
          Project.t() | nil,
          actor(),
          input(),
          keyword()
        ) ::
          {:ok, Project.t()} | {:error, term()}
  def import_document(project, actor, input, opts \\ []) do
    with {:ok, doc} <- to_provisioner_doc(input, project) do
      Provisioner.import_document(project, actor, doc, opts)
    end
  end
end
