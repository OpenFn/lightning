defmodule Lightning.Workflows.WorkflowTest do
  alias Lightning.Workflows
  use Lightning.DataCase, async: true

  alias Lightning.Workflows
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.Trigger

  import Lightning.Factories

  describe "relationships" do
    test "should be able resolve the current snapshot" do
      {:ok, workflow} =
        insert(:simple_workflow, project: insert(:project))
        |> Workflow.touch()
        |> Workflows.save_workflow(insert(:user))

      assert from(s in Ecto.assoc(workflow, :snapshots),
               where: s.lock_version == ^workflow.lock_version
             )
             |> Repo.one()
    end
  end

  describe "changeset/2 basic validations" do
    test "requires name and valid concurrency" do
      p = insert(:project)

      # missing name
      cs = Workflow.changeset(%Workflow{}, %{project_id: p.id})
      refute cs.valid?
      assert "can't be blank" in errors_on(cs).name

      # bad concurrency
      cs2 =
        Workflow.changeset(%Workflow{}, %{
          name: "w",
          project_id: p.id,
          concurrency: 0
        })

      refute cs2.valid?
      assert "must be greater than or equal to 1" in errors_on(cs2).concurrency

      # ok
      cs3 =
        Workflow.changeset(%Workflow{}, %{
          name: "w",
          project_id: p.id,
          concurrency: 2
        })

      assert cs3.valid?
    end

    test "a malformed project_id is a changeset error, not an Ecto.ChangeError on save" do
      cs =
        Workflow.changeset(%Workflow{}, %{
          name: "w",
          project_id: "__ID_WF_Foo_____"
        })

      refute cs.valid?
      assert "is not a valid UUID" in errors_on(cs).project_id
    end

    test "assoc_constraint(:project)" do
      cs =
        Workflow.changeset(%Workflow{}, %{
          name: "w",
          project_id: Ecto.UUID.generate()
        })

      {:error, cs} = Repo.insert(cs)
      assert "does not exist" in errors_on(cs).project
    end

    test "unique name per project" do
      p1 = insert(:project)
      p2 = insert(:project)

      {:ok, _} =
        %Workflow{}
        |> Workflow.changeset(%{name: "w1", project_id: p1.id})
        |> Repo.insert()

      # same name in same project -> error
      {:error, cs} =
        %Workflow{}
        |> Workflow.changeset(%{name: "w1", project_id: p1.id})
        |> Repo.insert()

      assert "A workflow with this name already exists (possibly pending deletion) in this project." in errors_on(
               cs
             ).name

      # same name in different project -> ok
      assert {:ok, _} =
               %Workflow{}
               |> Workflow.changeset(%{name: "w1", project_id: p2.id})
               |> Repo.insert()
    end
  end

  describe "changeset/2 name rule" do
    setup do
      %{project: insert(:project)}
    end

    test "a name may hold letters, marks, punctuation and symbols from any script",
         %{project: project} do
      [
        "Vérifier l'état",
        "患者確認",
        "تسجيل المريض",
        "רישום מטופל",
        "workflow 🎉",
        "MailChimp June'24",
        "Flujo 1: Registro en PS y gestión de perfiles",
        "a / b",
        "source -> target",
        "Ampersand & co",
        "नमस्ते"
      ]
      |> Enum.each(fn name ->
        changeset =
          Workflow.changeset(%Workflow{}, %{name: name, project_id: project.id})

        refute errors_on(changeset)[:name],
               "expected #{inspect(name)} to be accepted"
      end)
    end

    test "a name may not hold a control character", %{project: project} do
      [
        "nul\u{0000}byte",
        "tab\u{0009}here",
        "line\u{000A}break",
        "carriage\u{000D}return",
        "escape\u{001B}[31m",
        "unit\u{001F}separator",
        "delete\u{007F}",
        "c1\u{0080}next",
        "c1\u{009F}end",
        "non\u{FFFE}character",
        "non\u{FFFF}character"
      ]
      |> Enum.each(fn name ->
        changeset =
          Workflow.changeset(%Workflow{}, %{name: name, project_id: project.id})

        assert errors_on(changeset)[:name] == [
                 "workflow name can't contain control characters"
               ],
               "expected #{inspect(name)} to be rejected"
      end)
    end

    test "a name is normalised to NFC and trimmed on write", %{project: project} do
      decomposed = "  Ve\u{0301}rifier  "
      composed = "V\u{00E9}rifier"

      changeset =
        Workflow.changeset(%Workflow{}, %{
          name: decomposed,
          project_id: project.id
        })

      assert Ecto.Changeset.get_change(changeset, :name) == composed
    end

    test "a name at the width of the column saves", %{project: project} do
      name = String.duplicate("a", 255)

      changeset =
        Workflow.changeset(%Workflow{}, %{name: name, project_id: project.id})

      refute errors_on(changeset)[:name]
      assert {:ok, _} = Repo.insert(changeset)
    end

    test "a name past the width of the column is a changeset error, not a 500",
         %{project: project} do
      # This used to reach the database and come back as Postgrex 22001
      # (string_data_right_truncation), which the user saw as a 500.
      name = String.duplicate("a", 300)

      changeset =
        Workflow.changeset(%Workflow{}, %{name: name, project_id: project.id})

      assert errors_on(changeset)[:name] == [
               "workflow name should be at most 255 character(s)"
             ]

      assert {:error, changeset} = Repo.insert(changeset)
      refute changeset.valid?
    end

    test "the 255 cap counts graphemes, as the job cap does", %{project: project} do
      family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
      assert String.length(family) == 1

      over_cap = String.duplicate(family, 256)

      changeset =
        Workflow.changeset(%Workflow{}, %{
          name: over_cap,
          project_id: project.id
        })

      assert errors_on(changeset)[:name] == [
               "workflow name should be at most 255 character(s)"
             ]
    end

    test "a name short in graphemes but too wide for the column is rejected",
         %{project: project} do
      # 255 ZWJ families clear the cap above at 255 graphemes but are 1785
      # codepoints, and workflows.name is varchar(255).
      family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
      name = String.duplicate(family, 255)

      assert String.length(name) == 255
      assert name |> String.codepoints() |> length() == 1785

      changeset =
        Workflow.changeset(%Workflow{}, %{name: name, project_id: project.id})

      assert errors_on(changeset)[:name] == [
               "workflow name is too long, please use a shorter one"
             ]

      assert {:error, changeset} = Repo.insert(changeset)
      refute changeset.valid?
    end

    test "normalising a name onto one already taken is a changeset error, not a 500",
         %{project: project} do
      # Composing on write can land a name on one another workflow in the
      # project already holds, and the two look identical on screen.
      composed = "V\u{00E9}rifier"
      decomposed = "Ve\u{0301}rifier"

      {:ok, _taken} =
        %Workflow{}
        |> Workflow.changeset(%{name: composed, project_id: project.id})
        |> Repo.insert()

      {:ok, other} =
        %Workflow{}
        |> Workflow.changeset(%{name: "something else", project_id: project.id})
        |> Repo.insert()

      assert {:error, changeset} =
               other
               |> Workflow.changeset(%{name: decomposed})
               |> Repo.update()

      assert "A workflow with this name already exists (possibly pending deletion) in this project." in errors_on(
               changeset
             ).name
    end
  end

  describe "jsonb-bound fields on the workflow save path" do
    setup do
      %{project: insert(:project)}
    end

    test "a NUL in positions is a changeset error, not a 22P05", %{
      project: project
    } do
      # positions goes straight into the workflow_snapshots.positions jsonb,
      # keys and all, and Postgres refuses a NUL anywhere inside jsonb (#4893).
      for positions <- [
            %{"node\u{0000}id" => %{"x" => 1, "y" => 2}},
            %{"node" => %{"x" => 1, "label" => "a\u{0000}b"}},
            %{"node" => %{"tags" => ["ok", "bad\u{0000}"]}}
          ] do
        changeset =
          Workflow.changeset(%Workflow{}, %{
            name: "positions test",
            project_id: project.id,
            positions: positions
          })

        assert errors_on(changeset)[:positions] == [
                 "positions can't contain a null byte"
               ],
               "expected #{inspect(positions)} to be rejected"
      end
    end

    test "ordinary positions are untouched", %{project: project} do
      changeset =
        Workflow.changeset(%Workflow{}, %{
          name: "positions ok",
          project_id: project.id,
          positions: %{"a" => %{"x" => 1, "y" => 2}}
        })

      refute errors_on(changeset)[:positions]
      assert {:ok, _} = Repo.insert(changeset)
    end

    test "a NUL in positions is rejected before the snapshot insert", %{
      project: project
    } do
      attrs = %{
        name: "workflow with bad positions",
        project_id: project.id,
        positions: %{"bad\u{0000}key" => %{"x" => 1}},
        jobs: [
          %{
            id: Ecto.UUID.generate(),
            name: "step",
            body: "fn(state => state)",
            adaptor: "@openfn/language-common@latest"
          }
        ],
        triggers: [%{id: Ecto.UUID.generate(), type: :webhook}],
        edges: []
      }

      assert {:error, changeset} =
               Lightning.Workflows.save_workflow(attrs, insert(:user))

      assert errors_on(changeset)[:positions] == [
               "positions can't contain a null byte"
             ]
    end
  end

  describe "workflow_activated?/1" do
    test "true when a new trigger is enabled" do
      p = insert(:project)

      cs =
        %Workflow{}
        |> Workflow.changeset(%{
          name: "w",
          project_id: p.id,
          triggers: [%{type: :webhook, enabled: true}]
        })

      assert Workflow.workflow_activated?(cs)
    end

    test "true when an existing trigger flips enabled from false -> true" do
      wf = insert(:workflow, name: "w", project: insert(:project))
      t = insert(:trigger, workflow: wf, type: :webhook, enabled: false)

      # PRELOAD!
      wf = Repo.preload(wf, :triggers)

      t_cs =
        t
        |> Repo.reload!()
        |> Trigger.changeset(%{enabled: true})

      cs =
        wf
        |> Workflow.changeset(%{})
        |> Ecto.Changeset.put_assoc(:triggers, [t_cs])

      assert Workflow.workflow_activated?(cs)
    end

    test "false when no triggers are being enabled" do
      wf = insert(:workflow, project: insert(:project))
      t = insert(:trigger, workflow: wf, type: :webhook, enabled: true)

      # PRELOAD!
      wf = Repo.preload(wf, :triggers)

      t_cs =
        t
        |> Repo.reload!()
        # no change
        |> Trigger.changeset(%{})

      cs =
        wf
        |> Workflow.changeset(%{})
        |> Ecto.Changeset.put_assoc(:triggers, [t_cs])

      refute Workflow.workflow_activated?(cs)
    end
  end

  describe "touch/1 and soft delete" do
    test "touch increments lock_version and updates updated_at" do
      # safely in the past
      old = ~U[2000-01-01 00:00:00Z]
      wf = insert(:workflow, lock_version: 0, updated_at: old)

      updated = wf |> Workflow.touch() |> Repo.update!()

      assert updated.lock_version == wf.lock_version + 1
      assert DateTime.compare(updated.updated_at, old) == :gt
    end

    test "request_deletion_changeset allows setting deleted_at" do
      wf = insert(:workflow)
      now = DateTime.utc_now()

      {:ok, updated} =
        wf
        |> Workflow.request_deletion_changeset(%{deleted_at: now})
        |> Repo.update()

      assert updated.deleted_at
    end
  end
end
