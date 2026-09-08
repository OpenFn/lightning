defmodule Lightning.Credentials.SandboxCannotReadParentValuesTest do
  @moduledoc """
  The exposure this whole change exists to close, written as the attack.

  A sandbox holds a reference to every one of its parent's credentials. It used
  to read values by matching its own environment *name* against the credential's
  bodies, and that name is an ordinary project setting, editable by whoever
  administers the sandbox. Since creating a sandbox makes you its owner, an
  editor on a production project could manufacture owner rights for themselves
  on a project holding references to that project's credentials, type the
  parent's environment name into a text box, and decrypt its production values.

  27 sandboxes across 13 customer projects were in that state.
  """
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Credentials.Resolver

  setup do
    owner = insert(:user)
    parent = insert(:project, env: "main", project_users: [%{user: owner}])

    credential =
      insert(:credential, name: "Production DHIS2", schema: "raw", user: owner)
      |> with_body(%{name: "main", body: %{"password" => "production-secret"}})

    [production_body] =
      Repo.preload(credential, :credential_bodies).credential_bodies

    insert(:project_credential,
      project: parent,
      credential: credential,
      credential_body_id: production_body.id
    )

    %{owner: owner, parent: parent, credential: credential}
  end

  # A run in the sandbox against the cloned credential, which is what a webhook
  # call or a cron fire would produce once the sandbox is turned on.
  defp run_in(project, credential) do
    share =
      Repo.get_by!(Lightning.Projects.ProjectCredential,
        project_id: project.id,
        credential_id: credential.id
      )

    %{jobs: [job]} =
      workflow =
      build(:workflow, project: project)
      |> with_job(%{project_credential: share})
      |> insert()

    %{runs: [run]} =
      insert(:workorder, workflow: workflow)
      |> with_run(%{dataclip: insert(:dataclip), starting_job: job})

    run
  end

  test "a sandbox naming its parent's environment still reads nothing", %{
    owner: owner,
    parent: parent,
    credential: credential
  } do
    {:ok, sandbox} =
      Lightning.Projects.Sandboxes.provision(parent, owner, %{name: "sbx"})

    # The attack: make the sandbox's environment the parent's.
    {:ok, sandbox} = Lightning.Projects.update_project(sandbox, %{env: "main"})
    assert sandbox.env == parent.env

    run = run_in(sandbox, credential)

    assert {:error, {:no_credential_grant, _credential}} =
             Resolver.resolve_credential(run, credential.id)
  end

  test "the parent still reads its own values", %{
    parent: parent,
    credential: credential
  } do
    run = run_in(parent, credential)

    assert {:ok, resolved} = Resolver.resolve_credential(run, credential.id)
    assert resolved.body == %{"password" => "production-secret"}
  end

  test "a sandbox reads values once it is granted its own", %{
    owner: owner,
    parent: parent,
    credential: credential
  } do
    {:ok, sandbox} =
      Lightning.Projects.Sandboxes.provision(parent, owner, %{name: "sbx"})

    {:ok, _} =
      Lightning.Credentials.update_credential(
        credential,
        %{
          "credential_bodies" => [
            %{"name" => "main", "body" => %{"password" => "production-secret"}},
            %{"name" => "dev", "body" => %{"password" => "sandbox-secret"}}
          ]
        },
        owner
      )

    grant_body!(sandbox, credential, "dev")

    run = run_in(sandbox, credential)

    assert {:ok, resolved} = Resolver.resolve_credential(run, credential.id)

    # Its own values, and only those, whatever anything is named.
    assert resolved.body == %{"password" => "sandbox-secret"}
  end
end
