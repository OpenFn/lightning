defmodule Lightning.Projects.SandboxMergeBackstopTest do
  use Lightning.DataCase, async: true
  use Mimic

  import Ecto.Query
  import ExUnit.CaptureLog
  import Lightning.Factories

  alias Lightning.Credentials.Scoping
  alias Lightning.Projects.Provisioner
  alias Lightning.Projects.Sandboxes
  alias Lightning.Workflows.Job

  # Coverage for the sandbox-merge backstop `reject_out_of_project_credentials/1`
  # in `Sandboxes.merge/4`. On the live merge path the provisioner guard inside
  # `Provisioner.import_document/4` fires FIRST over a superset scan and rolls
  # back before the backstop runs — so the backstop only fires when that
  # upstream guard has regressed and silently passed a poisoned cross-project
  # job row.
  #
  # To exercise the backstop we simulate exactly that regression: we stub
  # `Provisioner.import_document/4` to plant a cross-project job row on the
  # target (inside the merge transaction) and return `{:ok, target}`, then drive
  # the real `Sandboxes.merge/4`. The stub IS the threat model the backstop
  # guards, not a convenience mock.

  describe "merge/4 out-of-project credential backstop" do
    test "a backstop-triggered merge failure is diagnosable and rolls back" do
      actor = insert(:user)
      source = insert(:project, name: "sandbox")
      target = insert(:project, name: "target")

      # Credentials owned by an unrelated project; the stub plants them on
      # target jobs so the backstop's project-wide scan flags them.
      other = insert(:project)
      foreign_keychain = insert(:keychain_credential, project: other)
      foreign_project_credential = insert(:project_credential, project: other)

      # Pre-generated so we can assert the ids appear in the log without needing
      # to read the (rolled-back) rows afterwards. Two separate jobs because the
      # DB `credential_exclusivity` constraint forbids one job holding both a
      # keychain and a project credential at once.
      keychain_job_id = Ecto.UUID.generate()
      credential_job_id = Ecto.UUID.generate()

      # Simulate the upstream-guard regression: import "succeeds" but leaves two
      # cross-project job references persisted on the target.
      Mimic.stub(Provisioner, :import_document, fn target, _actor, _doc, _opts ->
        workflow = insert(:workflow, project: target, name: "poisoned")

        insert(:job,
          id: keychain_job_id,
          workflow: workflow,
          keychain_credential: foreign_keychain,
          project_credential: nil
        )

        insert(:job,
          id: credential_job_id,
          workflow: workflow,
          project_credential: foreign_project_credential,
          keychain_credential: nil
        )

        {:ok, target}
      end)

      {result, log} =
        with_log(fn -> Sandboxes.merge(source, target, actor) end)

      # The caller gets the generic typed reason; the diagnostic detail goes
      # to the log only.
      assert result == {:error, :merge_failed}

      # The failure log must carry the shared human-readable field messages
      # and the offending job ids, not only an inspect'd violations tuple.
      assert log =~ Scoping.violation_message(:keychain_credential_id)
      assert log =~ Scoping.violation_message(:project_credential_id)
      assert log =~ keychain_job_id
      assert log =~ credential_job_id

      # Rollback proof: the planted cross-project rows did not survive.
      refute Repo.exists?(
               from(j in Job,
                 where: j.id in ^[keychain_job_id, credential_job_id]
               )
             )
    end
  end
end
