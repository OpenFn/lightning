defmodule Lightning.Workflows.JobTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.Job
  alias Lightning.Repo

  import Lightning.Factories

  # No space in the alphabet on purpose: the changeset trims before it measures,
  # so a name that happens to end in one would be under the cap after trimming
  # and the length test would pass or fail depending on the seed.
  defp random_job_name(length) do
    for _ <- 1..length,
        into: "",
        do:
          <<Enum.random(~c"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")>>
  end

  describe "changeset/2" do
    test "a malformed id is a changeset error, not an Ecto.ChangeError on save" do
      # An unsubstituted import placeholder reaching :id (a :binary_id field)
      # passes cast/3 and would only raise when dumped on insert. validate_uuid
      # surfaces it as a changeset error instead.
      changeset =
        Job.changeset(%Job{}, %{
          id: "__ID_JOB_Envoyer-dans-DHIS2__",
          name: "Test Job",
          body: "fn(state => state)",
          adaptor: "@openfn/language-common@latest"
        })

      refute changeset.valid?
      assert changeset.errors[:id] == {"is not a valid UUID", []}
    end

    test "malformed FK ids are changeset errors, not Ecto.ChangeError on save" do
      # workflow_id + keychain_credential_id together (no project_credential_id
      # so validate_exclusive doesn't fire and override the UUID error).
      changeset =
        Job.changeset(%Job{}, %{
          name: "Test Job",
          body: "fn(state => state)",
          adaptor: "@openfn/language-common@latest",
          workflow_id: "__ID_JOB_Fetch__",
          keychain_credential_id: "__ID_CRED_Foo___"
        })

      refute changeset.valid?
      assert changeset.errors[:workflow_id] == {"is not a valid UUID", []}

      assert changeset.errors[:keychain_credential_id] ==
               {"is not a valid UUID", []}

      # project_credential_id in isolation (no keychain set).
      project_changeset =
        Job.changeset(%Job{}, %{
          name: "Test Job",
          body: "fn(state => state)",
          adaptor: "@openfn/language-common@latest",
          project_credential_id: "__ID_CRED_Foo___"
        })

      refute project_changeset.valid?

      assert project_changeset.errors[:project_credential_id] ==
               {"is not a valid UUID", []}
    end

    test "FKs left unset stay valid" do
      workflow = insert(:workflow)

      changeset =
        Job.changeset(%Job{}, %{
          name: "Test Job",
          body: "fn(state => state)",
          adaptor: "@openfn/language-common@latest",
          workflow_id: workflow.id
        })

      assert changeset.valid?
      refute changeset.errors[:project_credential_id]
      refute changeset.errors[:keychain_credential_id]
    end

    test "accepts keychain_credential_id in changeset" do
      workflow = insert(:workflow)

      keychain_credential =
        insert(:keychain_credential, project: workflow.project)

      changeset =
        Job.changeset(%Job{}, %{
          name: "Test Job",
          body: "test",
          adaptor: "@openfn/language-common@latest",
          keychain_credential_id: keychain_credential.id,
          workflow_id: workflow.id
        })

      assert changeset.valid?
      refute changeset.errors[:keychain_credential_id]
    end

    test "validates that only one credential type can be set" do
      workflow = insert(:workflow)
      project_credential = insert(:project_credential, project: workflow.project)

      keychain_credential =
        insert(:keychain_credential, project: workflow.project)

      changeset =
        Job.changeset(%Job{}, %{
          name: "Test Job",
          body: "test",
          adaptor: "@openfn/language-common@latest",
          project_credential_id: project_credential.id,
          keychain_credential_id: keychain_credential.id,
          workflow_id: workflow.id
        })

      refute changeset.valid?

      # The validate_exclusive function adds the error to the field that was changed
      assert changeset.errors[:project_credential_id] ==
               {"cannot be set when the other credential type is also set", []}
    end

    test "validates that keychain credential belongs to the same project as the job" do
      workflow = insert(:workflow)
      other_project = insert(:project)
      keychain_credential = insert(:keychain_credential, project: other_project)

      workflow_with_project = Repo.preload(workflow, :project)

      changeset =
        %Job{}
        |> Ecto.Changeset.change()
        |> Job.put_workflow(Ecto.Changeset.change(workflow_with_project))
        |> Job.changeset(%{
          name: "Test Job",
          body: "test",
          adaptor: "@openfn/language-common@latest",
          keychain_credential_id: keychain_credential.id,
          workflow_id: workflow.id
        })

      refute changeset.valid?

      assert changeset.errors[:keychain_credential_id] ==
               {"must belong to the same project as the job", []}
    end

    test "allows both credential fields to be null" do
      workflow = insert(:workflow)

      changeset =
        Job.changeset(%Job{}, %{
          name: "Test Job",
          body: "test",
          adaptor: "@openfn/language-common@latest",
          workflow_id: workflow.id
        })

      assert changeset.valid?
    end

    test "raises a constraint error when jobs in the same workflow have the same downcased and hyphenated name" do
      workflow = insert(:workflow)

      [first | rest] = [
        "Validate form type",
        "validate form type",
        "validate-form-type",
        "validate-FORM type"
      ]

      insert(:job, workflow: workflow, name: first)

      Enum.each(rest, fn name ->
        {:error, changeset} =
          Job.changeset(
            %Job{},
            params_with_assocs(:job, workflow: workflow, name: name)
          )
          |> Repo.insert()

        refute changeset.valid?

        assert changeset.errors[:name] ==
                 {"job name has already been taken",
                  [
                    constraint: :unique,
                    constraint_name: "jobs_name_workflow_id_index"
                  ]}
      end)
    end

    test "database constraint prevents job with both credential types" do
      workflow = insert(:workflow)
      project_credential = insert(:project_credential, project: workflow.project)

      keychain_credential =
        insert(:keychain_credential, project: workflow.project)

      # This should fail at the database level due to the constraint
      assert_raise Ecto.ConstraintError, fn ->
        insert(:job,
          workflow: workflow,
          project_credential: project_credential,
          keychain_credential: keychain_credential
        )
      end
    end

    test "name can't be longer than 100 chars" do
      name = random_job_name(101)
      errors = Job.changeset(%Job{}, %{name: name}) |> errors_on()
      assert errors[:name] == ["job name should be at most 100 character(s)"]
    end

    test "the 100 character cap counts graphemes, not codepoints or bytes" do
      # A ZWJ family is one grapheme, seven codepoints and 25 bytes. Ecto counts
      # graphemes, so 12 of them are 12 characters and not 84 or 300.
      family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
      assert String.length(family) == 1

      at_cap = String.duplicate("a", 88) <> String.duplicate(family, 12)
      assert String.length(at_cap) == 100

      refute Job.changeset(%Job{}, %{name: at_cap})
             |> errors_on()
             |> Map.get(:name)

      over_cap = String.duplicate("a", 89) <> String.duplicate(family, 12)
      assert String.length(over_cap) == 101

      assert Job.changeset(%Job{}, %{name: over_cap})
             |> errors_on()
             |> Map.get(:name) ==
               ["job name should be at most 100 character(s)"]
    end

    test "a name short in graphemes but too wide for the column is rejected" do
      # jobs.name is varchar(255) and Postgres counts those in codepoints. 100
      # ZWJ families are 100 graphemes, so they clear the product cap, but 700
      # codepoints, so the insert used to raise 22001. Only reachable since the
      # charset was widened.
      family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
      name = String.duplicate(family, 100)

      assert String.length(name) == 100
      assert name |> String.codepoints() |> length() == 700

      changeset =
        Job.changeset(%Job{}, %{
          name: name,
          body: "fn(state => state)",
          adaptor: "@openfn/language-common@latest",
          workflow_id: insert(:workflow).id
        })

      # No number in this message on purpose. The user was told the limit is
      # 100 and counts 100 characters; answering "at most 255" is not something
      # they can act on.
      assert errors_on(changeset)[:name] == [
               "job name is too long, please use a shorter one"
             ]

      assert {:error, changeset} = Repo.insert(changeset)
      refute changeset.valid?
    end

    test "an over-long name gets one message, not two" do
      # The column guard stays quiet when the product cap has already spoken.
      errors =
        Job.changeset(%Job{}, %{name: random_job_name(300)}) |> errors_on()

      assert errors[:name] == ["job name should be at most 100 character(s)"]
    end

    test "a name may hold letters, marks, punctuation and symbols from any script" do
      [
        "Vérifier l'état",
        "患者確認",
        "تسجيل المريض",
        "רישום מטופל",
        "step 🎉",
        "MailChimp June'24",
        "Flujo 1: Registro en PS y gestión de perfiles",
        "My project @ OpenFn",
        "Can't have a / slash",
        "source -> target",
        "Ampersand & co",
        "नमस्ते"
      ]
      |> Enum.each(fn name ->
        errors = Job.changeset(%Job{}, %{name: name}) |> errors_on()

        refute errors[:name], "expected #{inspect(name)} to be accepted"
      end)
    end

    test "a name may not hold a control character" do
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
        errors = Job.changeset(%Job{}, %{name: name}) |> errors_on()

        assert errors[:name] == ["job name can't contain control characters"],
               "expected #{inspect(name)} to be rejected"
      end)
    end

    test "a name made only of invisible characters is blank" do
      # Each of these takes no space and draws nothing, so the name renders as
      # an empty label everywhere and becomes an invisible key in the spec.
      # String.trim/1 does not know about them, which is why the blank check
      # alone was not enough.
      for name <- [
            "\u{200B}",
            "\u{FEFF}",
            "\u{200C}",
            "\u{00AD}",
            "\u{180E}",
            "\u{200B}\u{FEFF}\u{00AD}"
          ] do
        errors = Job.changeset(%Job{}, %{name: name}) |> errors_on()

        assert "can't be blank" in errors[:name],
               "expected #{inspect(name)} to be rejected as blank"
      end
    end

    test "consecutive joiners do not slip past the blank check" do
      # String.graphemes/1 fuses a ZWJ-led run into one cluster, so a
      # per-grapheme check caught one joiner and missed two.
      for name <- [
            "\u{200D}\u{200D}",
            "\u{200D}\u{200D}\u{200D}",
            "\u{200B}\u{200D}\u{200D}",
            "\u{2060}",
            "\u{3164}",
            "\u{FFA0}",
            "\u{115F}",
            "\u{1160}",
            "\u{2800}",
            "\u{200E}",
            "\u{202E}",
            "\u{FE0F}"
          ] do
        errors = Job.changeset(%Job{}, %{name: name}) |> errors_on()

        assert "can't be blank" in errors[:name],
               "expected #{inspect(name)} to be rejected as blank"
      end
    end

    test "a body containing a NUL is a changeset error, not a jsonb crash" do
      # jobs.body is copied into workflow_snapshots.jobs, and Postgres refuses
      # a NUL anywhere inside a jsonb value (22P05). Only the NUL: a body is
      # code and legitimately holds newlines and tabs (#4893).
      errors =
        Job.changeset(%Job{}, %{
          name: "step",
          body: "fn(state => state)\u{0000}",
          adaptor: "@openfn/language-common@latest"
        })
        |> errors_on()

      assert errors[:body] == ["job body can't contain a null byte"]
    end

    test "a body may hold newlines, tabs and other control characters" do
      for body <- ["a\nb", "a\tb", "a\r\nb", "a\u{001B}[31mb"] do
        errors =
          Job.changeset(%Job{}, %{
            name: "step",
            body: body,
            adaptor: "@openfn/language-common@latest"
          })
          |> errors_on()

        refute errors[:body], "expected #{inspect(body)} to be accepted"
      end
    end

    test "a NUL in a body is rejected before the snapshot insert" do
      project = insert(:project)

      attrs = %{
        name: "workflow with a bad job body",
        project_id: project.id,
        jobs: [
          %{
            id: Ecto.UUID.generate(),
            name: "step",
            body: "fn(state => state)\u{0000}",
            adaptor: "@openfn/language-common@latest"
          }
        ],
        triggers: [%{id: Ecto.UUID.generate(), type: :webhook}],
        edges: []
      }

      assert {:error, changeset} =
               Lightning.Workflows.save_workflow(attrs, insert(:user))

      assert [job_changeset] = Ecto.Changeset.get_change(changeset, :jobs)

      assert errors_on(job_changeset)[:body] == [
               "job body can't contain a null byte"
             ]
    end

    test "a name that merely contains an invisible character is fine" do
      # ZWJ is how an emoji sequence is written, and several scripts need ZWNJ.
      for name <- [
            "\u{1F468}\u{200D}\u{1F469}",
            "a\u{200B}b",
            "\u{0915}\u{094D}\u{200C}\u{0937}"
          ] do
        errors = Job.changeset(%Job{}, %{name: name}) |> errors_on()

        refute errors[:name], "expected #{inspect(name)} to be accepted"
      end
    end

    test "a name is normalised to NFC on write" do
      # e + combining acute: two codepoints going in, one coming out.
      decomposed = "Ve\u{0301}rifier"
      composed = "V\u{00E9}rifier"

      refute decomposed == composed

      changeset = Job.changeset(%Job{}, %{name: decomposed})

      assert Ecto.Changeset.get_change(changeset, :name) == composed
    end

    test "the name is trimmed before it is validated, not after" do
      # 100 characters plus trailing space. Trimming after validation, which is
      # what this changeset used to do, made this 105 characters and rejected
      # a name that is exactly at the cap.
      name = String.duplicate("a", 100) <> "     "

      changeset = Job.changeset(%Job{}, %{name: name})

      refute errors_on(changeset)[:name]

      assert Ecto.Changeset.get_change(changeset, :name) ==
               String.duplicate("a", 100)
    end

    test "a whitespace-only name is blank" do
      errors = Job.changeset(%Job{}, %{name: "   "}) |> errors_on()

      assert errors[:name] == ["job name can't be blank"]
    end

    test "a NUL in a name is a changeset error, not a crash on the snapshot insert" do
      # Job names are written into the workflow_snapshots.jobs jsonb column and
      # Postgres refuses a NUL inside jsonb, so letting one through the
      # changeset turns into a 500 on save (#4893).
      project = insert(:project)

      attrs = %{
        name: "workflow with a bad job name",
        project_id: project.id,
        jobs: [
          %{
            id: Ecto.UUID.generate(),
            name: "before\u{0000}after",
            body: "fn(state => state)",
            adaptor: "@openfn/language-common@latest"
          }
        ],
        triggers: [%{id: Ecto.UUID.generate(), type: :webhook}],
        edges: []
      }

      assert {:error, changeset} =
               Lightning.Workflows.save_workflow(attrs, insert(:user))

      assert [job_changeset] = Ecto.Changeset.get_change(changeset, :jobs)

      assert errors_on(job_changeset)[:name] == [
               "job name can't contain control characters"
             ]
    end

    test "must have an adaptor" do
      errors = Job.changeset(%Job{}, %{adaptor: nil}) |> errors_on()
      assert errors[:adaptor] == ["job adaptor can't be blank"]
    end

    test "accepts well-formed, registry-listed adaptor strings" do
      [
        "@openfn/language-common@latest",
        "@openfn/language-http@1.2.3",
        "@openfn/language-http@1.2.3-pre",
        "@openfn/language-http",
        "@openfn/language-common"
      ]
      |> Enum.each(fn adaptor ->
        errors = Job.changeset(%Job{}, %{adaptor: adaptor}) |> errors_on()
        refute errors[:adaptor], "expected #{inspect(adaptor)} to be accepted"
      end)
    end

    test "rejects a well-formed adaptor that is not in the registry" do
      # The registry membership check only runs on an otherwise-valid changeset,
      # so name and body are supplied here.
      [
        "@openfn/language-foo@1.0.0",
        "@evilcorp/language-http@1.0.0",
        "common@1.0.0"
      ]
      |> Enum.each(fn adaptor ->
        errors =
          Job.changeset(%Job{}, %{
            name: "job",
            body: "fn(state => state)",
            adaptor: adaptor
          })
          |> errors_on()

        assert errors[:adaptor] == ["is not a recognised adaptor"],
               "expected #{inspect(adaptor)} to be rejected as unknown"
      end)
    end

    test "rejects malformed / injection-shaped adaptor strings" do
      [
        "@openfn/x\npwd\nb@1.0.0",
        "@openfn/language-http@7.3.2; touch /tmp/x",
        "@openfn/language-common@latest and stuff"
      ]
      |> Enum.each(fn adaptor ->
        errors = Job.changeset(%Job{}, %{adaptor: adaptor}) |> errors_on()

        assert errors[:adaptor] == ["adaptor has invalid format"],
               "expected #{inspect(adaptor)} to be rejected"
      end)
    end
  end
end
