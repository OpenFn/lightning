defmodule Lightning.SandboxMergeHelpers do
  @moduledoc """
  DB-inserting builders shared by the sandbox keychain merge test files.

  These plant real projects, credentials, keychains and workflows so cases can
  drive `Lightning.Projects.Sandboxes.merge/4` end-to-end and assert observable
  behaviour. (Distinct from `Lightning.MergeProjectsHelpers`, which builds
  plain-map state structures for the state-file merge path.)
  """

  import Lightning.Factories

  alias Lightning.Credentials.Scoping
  alias Lightning.Repo
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Workflow

  def new_actor_and_parent!(role \\ :owner) do
    actor = insert(:user)
    parent = insert(:project, name: "parent")
    insert(:project_user, project: parent, user: actor, role: role)
    {actor, parent}
  end

  # Parent with a minimal workflow so provisioning has something to clone.
  def parent_with_minimal_workflow! do
    {actor, parent} = new_actor_and_parent!()
    workflow = insert(:workflow, project: parent, name: "Alpha")
    insert(:trigger, workflow: workflow, type: :webhook, enabled: true)
    {actor, parent}
  end

  # Credential + project_credential + keychain owned by `project`, so a test
  # can plant a keychain that exists only in that project.
  def insert_project_keychain!(project, actor, name, path \\ "$.user_id") do
    cred = insert(:credential, body: %{"token" => name}, user: actor)
    insert(:project_credential, project: project, credential: cred)

    insert(:keychain_credential,
      project: project,
      created_by: actor,
      name: name,
      path: path,
      default_credential: cred
    )
  end

  # Parent project with one workflow whose job uses a parent-owned keychain.
  # Provisioning clones this keychain into the sandbox (it is used by a job),
  # giving us a sandbox-owned keychain that name-matches the parent's.
  def parent_with_keychain_job! do
    {actor, parent} = new_actor_and_parent!()

    cred = insert(:credential, body: %{"token" => "secret"}, user: actor)
    pc = insert(:project_credential, project: parent, credential: cred)

    workflow = insert(:workflow, project: parent, name: "Alpha")
    trigger = insert(:trigger, workflow: workflow, type: :webhook, enabled: true)

    kc =
      insert(:keychain_credential,
        project: parent,
        created_by: actor,
        name: "kc-main",
        path: "$.org_id",
        default_credential: cred
      )

    job =
      insert(:job,
        workflow: workflow,
        name: "A1",
        adaptor: "@openfn/language-common@latest",
        keychain_credential: kc,
        project_credential: nil
      )

    insert(:edge,
      workflow: workflow,
      source_trigger_id: trigger.id,
      target_job_id: job.id,
      condition_type: :always,
      enabled: true
    )

    %{
      actor: actor,
      parent: parent,
      cred: cred,
      pc: pc,
      kc: kc,
      workflow: workflow,
      job: job
    }
  end

  # Adds a brand-new workflow to the sandbox whose (single) job uses the given
  # keychain. This is the path that copies the keychain verbatim today. It sets
  # `keychain_credential_id` via `Ecto.Changeset.change/2`, deliberately
  # bypassing `Job.changeset` validation — this is how we plant references the
  # normal write path would reject (see the out-of-project backstop test).
  def add_new_keychain_workflow!(sandbox, keychain, wf_name) do
    new_wf = insert(:simple_workflow, project: sandbox, name: wf_name)
    [new_job] = Repo.preload(new_wf, :jobs).jobs

    new_job
    |> Ecto.Changeset.change(
      project_credential_id: nil,
      keychain_credential_id: keychain.id
    )
    |> Repo.update!()

    new_job
  end

  def merged_job!(parent, wf_name, job_name) do
    wf = Repo.get_by!(Workflow, project_id: parent.id, name: wf_name)
    Repo.get_by!(Job, workflow_id: wf.id, name: job_name)
  end

  def keychain_scoping_violations(project, job) do
    Scoping.out_of_project_references(project.id, [
      %{key: job.id, keychain_credential_id: job.keychain_credential_id}
    ])
  end
end
