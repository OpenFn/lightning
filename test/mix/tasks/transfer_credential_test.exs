defmodule Mix.Tasks.Lightning.TransferCredentialTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories
  import ExUnit.CaptureIO

  alias Mix.Tasks.Lightning.TransferCredential

  # Helper to capture IO from functions that may call exit/1
  defp capture_io_with_exit(fun) do
    capture_io(fn ->
      try do
        fun.()
      catch
        :exit, _reason -> :ok
      end
    end)
  end

  describe "single transfer" do
    setup do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")
      project = insert(:project)

      credential =
        insert(:credential,
          name: "Test Credential",
          user: source
        )

      insert(:project_credential, project: project, credential: credential)

      %{source: source, target: target, project: project, credential: credential}
    end

    test "transfers by credential ID", %{credential: cred, target: target} do
      capture_io(fn ->
        TransferCredential.run([
          "--id",
          cred.id,
          "--to",
          target.email,
          "--format",
          "quiet"
        ])
      end)

      updated = Repo.get!(Lightning.Credentials.Credential, cred.id)
      assert updated.user_id == target.id
    end

    test "transfers by credential name", %{
      credential: cred,
      source: source,
      target: target
    } do
      capture_io(fn ->
        TransferCredential.run([
          "--name",
          cred.name,
          "--from",
          source.email,
          "--to",
          target.email,
          "--format",
          "quiet"
        ])
      end)

      updated = Repo.get!(Lightning.Credentials.Credential, cred.id)
      assert updated.user_id == target.id
    end

    test "transfers with rename", %{credential: cred, target: target} do
      capture_io(fn ->
        TransferCredential.run([
          "--id",
          cred.id,
          "--to",
          target.email,
          "--rename",
          "New Name",
          "--format",
          "quiet"
        ])
      end)

      updated = Repo.get!(Lightning.Credentials.Credential, cred.id)
      assert updated.user_id == target.id
      assert updated.name == "New Name"
    end

    test "dry run does not make changes", %{
      credential: cred,
      source: source,
      target: target
    } do
      capture_io(fn ->
        TransferCredential.run([
          "--id",
          cred.id,
          "--to",
          target.email,
          "--dry-run"
        ])
      end)

      updated = Repo.get!(Lightning.Credentials.Credential, cred.id)
      assert updated.user_id == source.id
    end

    test "outputs JSON format", %{credential: cred, target: target} do
      output =
        capture_io(fn ->
          TransferCredential.run([
            "--id",
            cred.id,
            "--to",
            target.email,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == true
      assert length(data["transfers"]) == 1
    end

    test "creates audit event", %{
      credential: cred,
      source: source,
      target: target
    } do
      capture_io(fn ->
        TransferCredential.run([
          "--id",
          cred.id,
          "--to",
          target.email,
          "--reason",
          "User offboarding",
          "--format",
          "quiet"
        ])
      end)

      audit =
        Repo.one(
          from(a in Lightning.Auditing.Audit,
            where: a.item_id == ^cred.id and a.event == "transferred",
            order_by: [desc: a.inserted_at],
            limit: 1
          )
        )

      assert audit != nil
      assert audit.metadata["from_user_email"] == source.email
      assert audit.metadata["to_user_email"] == target.email
      assert audit.metadata["reason"] == "User offboarding"
    end
  end

  describe "list mode" do
    test "lists credentials for a user" do
      user = insert(:user, email: "owner@example.com")
      insert(:credential, name: "Cred A", user: user)
      insert(:credential, name: "Cred B", user: user)

      output =
        capture_io(fn ->
          TransferCredential.run([
            "--list",
            "--from",
            user.email,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["user"] == user.email
      assert length(data["credentials"]) == 2
    end

    test "errors when user not found in list mode" do
      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--list",
            "--from",
            "nonexistent@example.com",
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "User not found"
    end

    test "filters by schema" do
      user = insert(:user, email: "owner@example.com")
      insert(:credential, name: "SF Cred", user: user, schema: "salesforce")
      insert(:credential, name: "Other Cred", user: user, schema: "raw")

      output =
        capture_io(fn ->
          TransferCredential.run([
            "--list",
            "--from",
            user.email,
            "--schema",
            "salesforce",
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert length(data["credentials"]) == 1
      assert hd(data["credentials"])["name"] == "SF Cred"
    end

    test "filters by project" do
      user = insert(:user, email: "owner@example.com")
      project = insert(:project)

      cred_in_project = insert(:credential, name: "In Project", user: user)
      insert(:credential, name: "Not In Project", user: user)

      insert(:project_credential, project: project, credential: cred_in_project)

      output =
        capture_io(fn ->
          TransferCredential.run([
            "--list",
            "--from",
            user.email,
            "--project",
            project.id,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert length(data["credentials"]) == 1
      assert hd(data["credentials"])["name"] == "In Project"
    end
  end

  describe "bulk transfer" do
    test "transfers all credentials from one user to another" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")

      cred1 = insert(:credential, name: "Cred 1", user: source)
      cred2 = insert(:credential, name: "Cred 2", user: source)

      capture_io(fn ->
        TransferCredential.run([
          "--all",
          "--from",
          source.email,
          "--to",
          target.email,
          "--format",
          "quiet"
        ])
      end)

      assert Repo.get!(Lightning.Credentials.Credential, cred1.id).user_id ==
               target.id

      assert Repo.get!(Lightning.Credentials.Credential, cred2.id).user_id ==
               target.id
    end

    test "skips credentials with naming conflicts" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")

      cred_conflict = insert(:credential, name: "Conflicting", user: source)
      insert(:credential, name: "Conflicting", user: target)
      cred_ok = insert(:credential, name: "No Conflict", user: source)

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--all",
            "--from",
            source.email,
            "--to",
            target.email,
            "--format",
            "json"
          ])
        end)

      # The non-conflicting one should be transferred
      assert Repo.get!(Lightning.Credentials.Credential, cred_ok.id).user_id ==
               target.id

      # The conflicting one should NOT be transferred
      assert Repo.get!(Lightning.Credentials.Credential, cred_conflict.id).user_id ==
               source.id

      # Output should mention the conflict
      assert output =~ "conflicts"
    end

    test "shows conflicts in table format" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")

      insert(:credential, name: "Conflicting", user: source)
      insert(:credential, name: "Conflicting", user: target)
      insert(:credential, name: "No Conflict", user: source)

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--all",
            "--from",
            source.email,
            "--to",
            target.email,
            "--format",
            "table"
          ])
        end)

      assert output =~ "Skipped due to naming conflicts"
      assert output =~ "Conflicting"
    end

    test "reports when no credentials found" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")

      # source has no credentials

      output =
        capture_io(fn ->
          TransferCredential.run([
            "--all",
            "--from",
            source.email,
            "--to",
            target.email,
            "--format",
            "table"
          ])
        end)

      assert output =~ "No credentials found"
    end

    test "reports when no credentials found in json format" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")

      output =
        capture_io(fn ->
          TransferCredential.run([
            "--all",
            "--from",
            source.email,
            "--to",
            target.email,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["message"] =~ "No credentials found"
    end

    test "errors when source user not found in bulk mode" do
      target = insert(:user, email: "target@example.com")

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--all",
            "--from",
            "nonexistent@example.com",
            "--to",
            target.email,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "User not found"
    end

    test "errors when target user not found in bulk mode" do
      source = insert(:user, email: "source@example.com")
      insert(:credential, name: "Test Cred", user: source)

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--all",
            "--from",
            source.email,
            "--to",
            "nonexistent@example.com",
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "User not found"
    end

    test "renames credentials on conflict when --rename-on-conflict is set" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")

      cred_conflict = insert(:credential, name: "Conflicting", user: source)
      insert(:credential, name: "Conflicting", user: target)

      capture_io_with_exit(fn ->
        TransferCredential.run([
          "--all",
          "--from",
          source.email,
          "--to",
          target.email,
          "--rename-on-conflict",
          "--format",
          "quiet"
        ])
      end)

      # The conflicting one should be transferred with new name
      updated = Repo.get!(Lightning.Credentials.Credential, cred_conflict.id)
      assert updated.user_id == target.id
      assert updated.name == "Conflicting (from source@example.com)"
    end

    test "rename-on-conflict in dry-run shows credentials to attempt" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")

      insert(:credential, name: "Conflicting", user: source)
      insert(:credential, name: "Conflicting", user: target)

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--all",
            "--from",
            source.email,
            "--to",
            target.email,
            "--rename-on-conflict",
            "--dry-run",
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["dry_run"] == true
      # In EAFP mode, dry-run shows all credentials to attempt
      # Renames happen at execution time on conflict
      assert length(data["transfers"]) == 1
    end

    test "rename-on-conflict still skips if renamed name also conflicts" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")

      cred_conflict = insert(:credential, name: "Conflicting", user: source)
      insert(:credential, name: "Conflicting", user: target)
      # Also create a credential with the renamed name
      insert(:credential,
        name: "Conflicting (from source@example.com)",
        user: target
      )

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--all",
            "--from",
            source.email,
            "--to",
            target.email,
            "--rename-on-conflict",
            "--format",
            "json"
          ])
        end)

      # Should still be owned by source (skipped due to double conflict)
      assert Repo.get!(Lightning.Credentials.Credential, cred_conflict.id).user_id ==
               source.id

      # Output should mention the conflict
      assert output =~ "conflicts"
    end
  end

  describe "validation" do
    test "rejects invalid UUID format" do
      assert_raise Mix.Error, ~r/Invalid UUID format/, fn ->
        TransferCredential.run([
          "--id",
          "not-a-uuid",
          "--to",
          "user@example.com"
        ])
      end
    end

    test "rejects invalid format option" do
      assert_raise Mix.Error, ~r/Invalid format/, fn ->
        TransferCredential.run(["--format", "xml"])
      end
    end

    test "rejects unknown options" do
      assert_raise Mix.Error, ~r/Unknown option/, fn ->
        TransferCredential.run(["--invalid-option=value"])
      end
    end

    test "rejects positional arguments" do
      assert_raise Mix.Error, ~r/Unexpected positional arguments/, fn ->
        TransferCredential.run(["MyCredential", "--to", "user@example.com"])
      end
    end

    test "requires target user" do
      user = insert(:user)
      cred = insert(:credential, user: user)

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run(["--id", cred.id, "--format", "json"])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "target user"
    end

    test "prevents transferring to same user" do
      user = insert(:user, email: "same@example.com")
      cred = insert(:credential, user: user)

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--id",
            cred.id,
            "--to",
            user.email,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "same"
    end
  end

  describe "undo" do
    test "dry run shows undo plan" do
      original_owner = insert(:user, email: "original@example.com")
      new_owner = insert(:user, email: "new@example.com")
      cred = insert(:credential, name: "Undo Dry Run", user: original_owner)

      # First, do the transfer
      capture_io(fn ->
        TransferCredential.run([
          "--id",
          cred.id,
          "--to",
          new_owner.email,
          "--format",
          "quiet"
        ])
      end)

      # Get the audit event
      audit =
        Repo.one(
          from(a in Lightning.Auditing.Audit,
            where: a.item_id == ^cred.id and a.event == "transferred",
            order_by: [desc: a.inserted_at],
            limit: 1
          )
        )

      # Dry run undo
      output =
        capture_io(fn ->
          TransferCredential.run([
            "--undo",
            audit.id,
            "--dry-run",
            "--format",
            "table"
          ])
        end)

      assert output =~ "Would undo transfer"
      assert output =~ "Undo Dry Run"

      # Credential should still be owned by new_owner
      assert Repo.get!(Lightning.Credentials.Credential, cred.id).user_id ==
               new_owner.id
    end

    test "reverses a previous transfer in json format" do
      original_owner = insert(:user, email: "original@example.com")
      new_owner = insert(:user, email: "new@example.com")
      cred = insert(:credential, name: "Undo JSON", user: original_owner)

      # First, do the transfer
      capture_io(fn ->
        TransferCredential.run([
          "--id",
          cred.id,
          "--to",
          new_owner.email,
          "--format",
          "quiet"
        ])
      end)

      # Get the audit event
      audit =
        Repo.one(
          from(a in Lightning.Auditing.Audit,
            where: a.item_id == ^cred.id and a.event == "transferred",
            order_by: [desc: a.inserted_at],
            limit: 1
          )
        )

      # Undo
      output =
        capture_io(fn ->
          TransferCredential.run([
            "--undo",
            audit.id,
            "--format",
            "json"
          ])
        end)

      assert output =~ "Transfer undone successfully"

      assert Repo.get!(Lightning.Credentials.Credential, cred.id).user_id ==
               original_owner.id
    end

    test "reverses a previous transfer" do
      original_owner = insert(:user, email: "original@example.com")
      new_owner = insert(:user, email: "new@example.com")
      cred = insert(:credential, name: "Undo Test", user: original_owner)

      # First, do the transfer
      capture_io(fn ->
        TransferCredential.run([
          "--id",
          cred.id,
          "--to",
          new_owner.email,
          "--format",
          "quiet"
        ])
      end)

      # Get the audit event
      audit =
        Repo.one(
          from(a in Lightning.Auditing.Audit,
            where: a.item_id == ^cred.id and a.event == "transferred",
            order_by: [desc: a.inserted_at],
            limit: 1
          )
        )

      # Now undo
      capture_io(fn ->
        TransferCredential.run([
          "--undo",
          audit.id,
          "--format",
          "quiet"
        ])
      end)

      # Should be back to original owner
      assert Repo.get!(Lightning.Credentials.Credential, cred.id).user_id ==
               original_owner.id
    end

    test "errors when audit event not found" do
      fake_id = Ecto.UUID.generate()

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--undo",
            fake_id,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "not found"
    end
  end

  describe "user ID options" do
    test "transfers using --from-user-id" do
      source = insert(:user)
      target = insert(:user, email: "target@example.com")
      cred = insert(:credential, name: "ID Test", user: source)

      capture_io(fn ->
        TransferCredential.run([
          "--name",
          cred.name,
          "--from-user-id",
          source.id,
          "--to",
          target.email,
          "--format",
          "quiet"
        ])
      end)

      assert Repo.get!(Lightning.Credentials.Credential, cred.id).user_id ==
               target.id
    end

    test "transfers using --to-user-id" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user)
      cred = insert(:credential, name: "ID Test", user: source)

      capture_io(fn ->
        TransferCredential.run([
          "--name",
          cred.name,
          "--from",
          source.email,
          "--to-user-id",
          target.id,
          "--format",
          "quiet"
        ])
      end)

      assert Repo.get!(Lightning.Credentials.Credential, cred.id).user_id ==
               target.id
    end

    test "errors when target user not found by --to-user-id" do
      source = insert(:user, email: "source@example.com")
      cred = insert(:credential, name: "ID Test", user: source)
      fake_id = Ecto.UUID.generate()

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--id",
            cred.id,
            "--to-user-id",
            fake_id,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "User not found"
      assert data["error"] =~ fake_id
    end

    test "errors when source user not found by --from-user-id" do
      target = insert(:user, email: "target@example.com")
      fake_id = Ecto.UUID.generate()

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--name",
            "Some Cred",
            "--from-user-id",
            fake_id,
            "--to",
            target.email,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "User not found"
      assert data["error"] =~ fake_id
    end
  end

  describe "error handling" do
    test "errors when credential not found by ID" do
      target = insert(:user, email: "target@example.com")
      fake_id = Ecto.UUID.generate()

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--id",
            fake_id,
            "--to",
            target.email,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "not found"
    end

    test "errors when credential not found by name" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--name",
            "Nonexistent",
            "--from",
            source.email,
            "--to",
            target.email,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "not found"
    end

    test "errors when source user not found" do
      target = insert(:user, email: "target@example.com")

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--name",
            "Some Cred",
            "--from",
            "nonexistent@example.com",
            "--to",
            target.email,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "not found"
    end

    test "errors when target user not found" do
      source = insert(:user, email: "source@example.com")
      cred = insert(:credential, user: source)

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--id",
            cred.id,
            "--to",
            "nonexistent@example.com",
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "not found"
    end

    test "errors on name conflict in single transfer" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")

      insert(:credential, name: "Conflicting", user: target)
      cred = insert(:credential, name: "Conflicting", user: source)

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--id",
            cred.id,
            "--to",
            target.email,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "already has a credential"
    end
  end

  describe "transfer by name with project filter" do
    test "finds credential in specific project" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")
      project = insert(:project)

      cred = insert(:credential, name: "Project Cred", user: source)
      insert(:project_credential, project: project, credential: cred)

      capture_io(fn ->
        TransferCredential.run([
          "--name",
          "Project Cred",
          "--from",
          source.email,
          "--to",
          target.email,
          "--project",
          project.id,
          "--format",
          "quiet"
        ])
      end)

      assert Repo.get!(Lightning.Credentials.Credential, cred.id).user_id ==
               target.id
    end

    test "errors when credential not found in project" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")
      project = insert(:project)
      other_project = insert(:project)

      cred = insert(:credential, name: "Project Cred", user: source)
      insert(:project_credential, project: other_project, credential: cred)

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--name",
            "Project Cred",
            "--from",
            source.email,
            "--to",
            target.email,
            "--project",
            project.id,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "not found"
      assert data["error"] =~ "in project"
    end
  end

  describe "bulk transfer with filters" do
    test "only transfers credentials matching schema filter" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")

      sf_cred =
        insert(:credential, name: "SF", user: source, schema: "salesforce")

      other_cred =
        insert(:credential, name: "Other", user: source, schema: "raw")

      capture_io(fn ->
        TransferCredential.run([
          "--all",
          "--from",
          source.email,
          "--to",
          target.email,
          "--schema",
          "salesforce",
          "--format",
          "quiet"
        ])
      end)

      # Only SF credential should be transferred
      assert Repo.get!(Lightning.Credentials.Credential, sf_cred.id).user_id ==
               target.id

      assert Repo.get!(Lightning.Credentials.Credential, other_cred.id).user_id ==
               source.id
    end

    test "dry run shows plan without making changes" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")

      cred1 = insert(:credential, name: "Cred 1", user: source)
      cred2 = insert(:credential, name: "Cred 2", user: source)

      output =
        capture_io(fn ->
          TransferCredential.run([
            "--all",
            "--from",
            source.email,
            "--to",
            target.email,
            "--dry-run",
            "--format",
            "json"
          ])
        end)

      # Credentials should NOT be transferred
      assert Repo.get!(Lightning.Credentials.Credential, cred1.id).user_id ==
               source.id

      assert Repo.get!(Lightning.Credentials.Credential, cred2.id).user_id ==
               source.id

      # Output should show dry run
      assert {:ok, data} = Jason.decode(output)
      assert data["dry_run"] == true
      assert length(data["transfers"]) == 2
    end
  end

  describe "output formats" do
    test "table format outputs readable text for list" do
      user = insert(:user, email: "owner@example.com")
      project = insert(:project, name: "My Project")
      cred = insert(:credential, name: "Test Cred", user: user, schema: "raw")
      insert(:project_credential, project: project, credential: cred)

      output =
        capture_io(fn ->
          TransferCredential.run([
            "--list",
            "--from",
            user.email,
            "--format",
            "table"
          ])
        end)

      assert output =~ "Credentials for owner@example.com"
      assert output =~ "Test Cred"
      assert output =~ "My Project"
      assert output =~ "Total: 1 credential(s)"
    end

    test "table format shows (none) for credentials without projects" do
      user = insert(:user, email: "owner@example.com")
      insert(:credential, name: "Orphan Cred", user: user, schema: "raw")

      output =
        capture_io(fn ->
          TransferCredential.run([
            "--list",
            "--from",
            user.email,
            "--format",
            "table"
          ])
        end)

      assert output =~ "(none)"
    end

    test "table format for empty credential list" do
      user = insert(:user, email: "owner@example.com")

      output =
        capture_io(fn ->
          TransferCredential.run([
            "--list",
            "--from",
            user.email,
            "--format",
            "table"
          ])
        end)

      assert output =~ "No credentials found"
    end

    test "table format outputs transfer result" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")
      cred = insert(:credential, name: "Table Test", user: source)

      output =
        capture_io(fn ->
          TransferCredential.run([
            "--id",
            cred.id,
            "--to",
            target.email,
            "--format",
            "table"
          ])
        end)

      assert output =~ "Transfer Complete"
      assert output =~ "Table Test"
      assert output =~ "source@example.com"
      assert output =~ "target@example.com"
    end

    test "table format outputs dry run plan" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")
      cred = insert(:credential, name: "Dry Run Test", user: source)

      output =
        capture_io(fn ->
          TransferCredential.run([
            "--id",
            cred.id,
            "--to",
            target.email,
            "--format",
            "table",
            "--dry-run"
          ])
        end)

      assert output =~ "Dry Run"
      assert output =~ "Transfer Plan"
      assert output =~ "Dry Run Test"
    end

    test "table format outputs dry run plan with rename" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")
      cred = insert(:credential, name: "Original Name", user: source)

      output =
        capture_io(fn ->
          TransferCredential.run([
            "--id",
            cred.id,
            "--to",
            target.email,
            "--rename",
            "New Name",
            "--format",
            "table",
            "--dry-run"
          ])
        end)

      assert output =~ "Rename to: New Name"
    end

    test "quiet format for list outputs only IDs" do
      user = insert(:user, email: "owner@example.com")
      cred = insert(:credential, name: "Test Cred", user: user)

      output =
        capture_io(fn ->
          TransferCredential.run([
            "--list",
            "--from",
            user.email,
            "--format",
            "quiet"
          ])
        end)

      # Should only contain the UUID
      assert String.trim(output) == cred.id
    end

    test "quiet format for error outputs to stderr" do
      source = insert(:user, email: "source@example.com")
      cred = insert(:credential, user: source)

      stderr =
        capture_io(:stderr, fn ->
          capture_io_with_exit(fn ->
            TransferCredential.run([
              "--id",
              cred.id,
              "--to",
              "nonexistent@example.com",
              "--format",
              "quiet"
            ])
          end)
        end)

      assert stderr =~ "not found"
    end

    test "quiet format for bulk conflicts outputs nothing" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")

      insert(:credential, name: "Conflicting", user: source)
      insert(:credential, name: "Conflicting", user: target)
      insert(:credential, name: "No Conflict", user: source)

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--all",
            "--from",
            source.email,
            "--to",
            target.email,
            "--format",
            "quiet"
          ])
        end)

      # Quiet format should not mention conflicts (only IDs or nothing)
      refute output =~ "Skipped"
      refute output =~ "conflicts"
    end
  end

  describe "short aliases" do
    test "-n works as --name" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")
      cred = insert(:credential, name: "Alias Test", user: source)

      capture_io(fn ->
        TransferCredential.run([
          "-n",
          "Alias Test",
          "-f",
          source.email,
          "-t",
          target.email,
          "--format",
          "quiet"
        ])
      end)

      assert Repo.get!(Lightning.Credentials.Credential, cred.id).user_id ==
               target.id
    end

    test "-i works as --id" do
      source = insert(:user)
      target = insert(:user, email: "target@example.com")
      cred = insert(:credential, user: source)

      capture_io(fn ->
        TransferCredential.run([
          "-i",
          cred.id,
          "-t",
          target.email,
          "--format",
          "quiet"
        ])
      end)

      assert Repo.get!(Lightning.Credentials.Credential, cred.id).user_id ==
               target.id
    end

    test "-p works as --project" do
      user = insert(:user, email: "owner@example.com")
      project = insert(:project)
      cred = insert(:credential, name: "Project Cred", user: user)
      insert(:project_credential, project: project, credential: cred)

      output =
        capture_io(fn ->
          TransferCredential.run([
            "--list",
            "-f",
            user.email,
            "-p",
            project.id,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert length(data["credentials"]) == 1
    end

    test "-s works as --schema" do
      user = insert(:user, email: "owner@example.com")
      insert(:credential, name: "SF", user: user, schema: "salesforce")
      insert(:credential, name: "Other", user: user, schema: "raw")

      output =
        capture_io(fn ->
          TransferCredential.run([
            "--list",
            "-f",
            user.email,
            "-s",
            "salesforce",
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert length(data["credentials"]) == 1
    end

    test "-r works as --rename" do
      source = insert(:user)
      target = insert(:user, email: "target@example.com")
      cred = insert(:credential, name: "Original", user: source)

      capture_io(fn ->
        TransferCredential.run([
          "-i",
          cred.id,
          "-t",
          target.email,
          "-r",
          "Renamed",
          "--format",
          "quiet"
        ])
      end)

      updated = Repo.get!(Lightning.Credentials.Credential, cred.id)
      assert updated.name == "Renamed"
    end
  end

  describe "undo edge cases" do
    test "errors when credential was deleted" do
      original_owner = insert(:user, email: "original@example.com")
      new_owner = insert(:user, email: "new@example.com")
      cred = insert(:credential, name: "Delete Test", user: original_owner)

      # Do the transfer
      capture_io_with_exit(fn ->
        TransferCredential.run([
          "--id",
          cred.id,
          "--to",
          new_owner.email,
          "--format",
          "quiet"
        ])
      end)

      # Get the audit event
      audit =
        Repo.one(
          from(a in Lightning.Auditing.Audit,
            where: a.item_id == ^cred.id and a.event == "transferred",
            order_by: [desc: a.inserted_at],
            limit: 1
          )
        )

      # Delete the credential
      Repo.delete!(Repo.get!(Lightning.Credentials.Credential, cred.id))

      # Try to undo
      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--undo",
            audit.id,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "no longer exists"
    end

    test "errors when original owner was deleted" do
      original_owner = insert(:user, email: "original@example.com")
      new_owner = insert(:user, email: "new@example.com")
      cred = insert(:credential, name: "Owner Delete Test", user: original_owner)

      # Do the transfer
      capture_io_with_exit(fn ->
        TransferCredential.run([
          "--id",
          cred.id,
          "--to",
          new_owner.email,
          "--format",
          "quiet"
        ])
      end)

      # Get the audit event
      audit =
        Repo.one(
          from(a in Lightning.Auditing.Audit,
            where: a.item_id == ^cred.id and a.event == "transferred",
            order_by: [desc: a.inserted_at],
            limit: 1
          )
        )

      # Delete the original owner
      # Need to clear the credential's reference first since it's now owned by new_owner
      Repo.delete!(original_owner)

      # Try to undo
      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--undo",
            audit.id,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "no longer exists"
    end
  end

  describe "constraint violation handling" do
    test "single transfer returns conflict error on unique constraint violation" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")

      # Create credential to transfer
      cred = insert(:credential, name: "Same Name", user: source)

      # Create existing credential with same name for target
      insert(:credential, name: "Same Name", user: target)

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--id",
            cred.id,
            "--to",
            target.email,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "already has a credential"

      # Credential should NOT have been transferred
      assert Repo.get!(Lightning.Credentials.Credential, cred.id).user_id ==
               source.id
    end

    test "bulk transfer handles mix of successes and conflicts" do
      source = insert(:user, email: "source@example.com")
      target = insert(:user, email: "target@example.com")

      cred_ok = insert(:credential, name: "Unique Name", user: source)
      cred_conflict = insert(:credential, name: "Conflicting", user: source)
      insert(:credential, name: "Conflicting", user: target)

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--all",
            "--from",
            source.email,
            "--to",
            target.email,
            "--format",
            "json"
          ])
        end)

      # The unique one should be transferred
      assert Repo.get!(Lightning.Credentials.Credential, cred_ok.id).user_id ==
               target.id

      # The conflicting one should NOT be transferred
      assert Repo.get!(Lightning.Credentials.Credential, cred_conflict.id).user_id ==
               source.id

      # Output should show both success and conflict
      assert output =~ "Unique Name"
      assert output =~ "conflicts"
    end

    test "undo returns conflict error when original owner has same-named credential" do
      original_owner = insert(:user, email: "original@example.com")
      new_owner = insert(:user, email: "new@example.com")
      cred = insert(:credential, name: "Undo Conflict", user: original_owner)

      # Do the transfer
      capture_io(fn ->
        TransferCredential.run([
          "--id",
          cred.id,
          "--to",
          new_owner.email,
          "--format",
          "quiet"
        ])
      end)

      # Create a credential with the same name for original owner (simulating they created a new one)
      insert(:credential, name: "Undo Conflict", user: original_owner)

      # Get the audit event
      audit =
        Repo.one(
          from(a in Lightning.Auditing.Audit,
            where: a.item_id == ^cred.id and a.event == "transferred",
            order_by: [desc: a.inserted_at],
            limit: 1
          )
        )

      # Try to undo - should fail with conflict
      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--undo",
            audit.id,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "already has a credential"
    end
  end

  describe "missing credential identifier" do
    test "returns error when no credential specified" do
      target = insert(:user, email: "target@example.com")

      output =
        capture_io_with_exit(fn ->
          TransferCredential.run([
            "--to",
            target.email,
            "--format",
            "json"
          ])
        end)

      assert {:ok, data} = Jason.decode(output)
      assert data["success"] == false
      assert data["error"] =~ "Missing credential"
    end

    test "returns error in table format" do
      target = insert(:user, email: "target@example.com")

      output =
        capture_io(:stderr, fn ->
          capture_io_with_exit(fn ->
            TransferCredential.run([
              "--to",
              target.email,
              "--format",
              "table"
            ])
          end)
        end)

      assert output =~ "Missing credential"
    end
  end
end
