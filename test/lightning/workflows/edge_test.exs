defmodule Lightning.Workflows.EdgeTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.Edge

  describe "condition_label and condition_expression" do
    defp edge_changeset(attrs) do
      Edge.changeset(
        %Edge{source_job_id: Ecto.UUID.generate()},
        Map.merge(
          %{
            workflow_id: Ecto.UUID.generate(),
            target_job_id: Ecto.UUID.generate()
          },
          attrs
        )
      )
    end

    test "a control character in the label is rejected on every condition type" do
      # This check used to sit inside the :js_expression branch, so an :always
      # edge could carry a NUL in its label straight into the snapshot jsonb.
      for condition_type <- [
            :always,
            :on_job_success,
            :on_job_failure,
            :js_expression
          ] do
        changeset =
          edge_changeset(%{
            condition_type: condition_type,
            condition_label: "bad\u{0000}label",
            condition_expression: "state.data.ok"
          })

        assert errors_on(changeset)[:condition_label] == [
                 "condition label can't contain control characters"
               ],
               "expected #{condition_type} to reject a control character"
      end
    end

    test "the label length cap applies on every condition type too" do
      for condition_type <- [:always, :on_job_success, :js_expression] do
        changeset =
          edge_changeset(%{
            condition_type: condition_type,
            condition_label: String.duplicate("a", 256),
            condition_expression: "state.data.ok"
          })

        assert errors_on(changeset)[:condition_label],
               "expected #{condition_type} to reject an over-long label"
      end
    end

    test "an ordinary label is accepted on every condition type" do
      for condition_type <- [:always, :on_job_success, :js_expression] do
        changeset =
          edge_changeset(%{
            condition_type: condition_type,
            condition_label: "évaluation rechazada 🎉",
            condition_expression: "state.data.ok"
          })

        refute errors_on(changeset)[:condition_label],
               "expected #{condition_type} to accept the label"
      end
    end

    test "a NUL in the expression is rejected on every condition type" do
      # cast/3 accepts an expression whatever the condition type is, and it
      # reaches the snapshot jsonb either way. This check used to be reachable
      # only through the :js_expression branch, and even there it sat behind a
      # `valid?: false` short circuit, so it never actually ran.
      for condition_type <- [
            :always,
            :on_job_success,
            :on_job_failure,
            :js_expression
          ] do
        changeset =
          edge_changeset(%{
            condition_type: condition_type,
            condition_expression: "state.data\u{0000}"
          })

        assert errors_on(changeset)[:condition_expression] == [
                 "condition expression can't contain a null byte"
               ],
               "expected #{condition_type} to reject a null byte"
      end
    end

    test "a label short in graphemes but too wide for the column is rejected" do
      # The cap above counts graphemes, the column counts codepoints: 200 ZWJ
      # families are 200 characters to Ecto and 1400 to Postgres.
      family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
      label = String.duplicate(family, 200)

      assert String.length(label) == 200
      assert label |> String.codepoints() |> length() == 1400

      for condition_type <- [:always, :on_job_success, :js_expression] do
        changeset =
          edge_changeset(%{
            condition_type: condition_type,
            condition_label: label,
            condition_expression: "state.data.ok"
          })

        assert errors_on(changeset)[:condition_label] == [
                 "condition label is too long, please use a shorter one"
               ],
               "expected #{condition_type} to reject an over-wide label"
      end
    end

    test "an expression short in graphemes but too wide for the column is rejected" do
      family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
      expression = String.duplicate(family, 200)

      for condition_type <- [:always, :on_job_success, :js_expression] do
        changeset =
          edge_changeset(%{
            condition_type: condition_type,
            condition_expression: expression
          })

        assert errors_on(changeset)[:condition_expression] == [
                 "condition expression is too long, please use a shorter one"
               ],
               "expected #{condition_type} to reject an over-wide expression"
      end
    end

    test "the expression length cap applies on every condition type" do
      for condition_type <- [:always, :on_job_success, :js_expression] do
        changeset =
          edge_changeset(%{
            condition_type: condition_type,
            condition_expression: String.duplicate("a", 256)
          })

        assert errors_on(changeset)[:condition_expression],
               "expected #{condition_type} to reject an over-long expression"
      end
    end

    test "the checks run even when the changeset is invalid for other reasons" do
      # A minimal changeset is invalid for unrelated missing fields on plenty
      # of real save paths. Skipping the jsonb checks there is how the hole
      # stayed open.
      changeset =
        Edge.changeset(%Edge{}, %{
          condition_type: :always,
          condition_expression: "state\u{0000}",
          condition_label: "bad\u{0000}label"
        })

      refute changeset.valid?

      assert errors_on(changeset)[:condition_expression] == [
               "condition expression can't contain a null byte"
             ]

      assert errors_on(changeset)[:condition_label] == [
               "condition label can't contain control characters"
             ]
    end

    test "the expression may hold newlines and tabs" do
      changeset =
        edge_changeset(%{
          condition_type: :js_expression,
          condition_expression: "state.data\n\t&& true"
        })

      refute errors_on(changeset)[:condition_expression]
    end
  end

  describe "changeset/2" do
    test "valid changeset" do
      changeset =
        Edge.changeset(%Edge{source_job_id: Ecto.UUID.generate()}, %{
          workflow_id: Ecto.UUID.generate(),
          condition_type: :on_job_success
        })

      assert changeset.valid?
    end

    test "a malformed uuid field is a changeset error, not an Ecto.ChangeError on save" do
      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: Ecto.UUID.generate(),
          source_job_id: "__ID_JOB_Envoyer-dans-DHIS2__",
          target_job_id: Ecto.UUID.generate(),
          condition_type: :on_job_success
        })

      refute changeset.valid?
      assert changeset.errors[:source_job_id] == {"is not a valid UUID", []}
    end

    test "a malformed workflow_id is a changeset error, not an Ecto.ChangeError on save" do
      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: "__ID_WF_Foo_____",
          source_job_id: Ecto.UUID.generate(),
          target_job_id: Ecto.UUID.generate(),
          condition_type: :on_job_success
        })

      refute changeset.valid?
      assert changeset.errors[:workflow_id] == {"is not a valid UUID", []}
    end

    test "edges must have a condition" do
      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: Ecto.UUID.generate(),
          source_job_id: Ecto.UUID.generate()
        })

      refute changeset.valid?

      assert changeset.errors == [
               condition_type: {"can't be blank", [validation: :required]}
             ]
    end

    test "edges must have at least one source" do
      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: Ecto.UUID.generate(),
          condition_type: :on_job_success
        })

      refute changeset.valid?

      assert changeset.errors == [
               source_job_id:
                 {"source_job_id or source_trigger_id must be present", []}
             ]
    end

    test "trigger sourced edges must have the :always condition" do
      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: Ecto.UUID.generate(),
          source_trigger_id: Ecto.UUID.generate(),
          condition_type: "on_job_success"
        })

      refute changeset.valid?

      assert {:condition_type,
              {"must be :always or :js_expression when source is a trigger",
               [validation: :inclusion, enum: [:always, :js_expression]]}} in changeset.errors
    end

    test "can't have both source_job_id and source_trigger_id" do
      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: Ecto.UUID.generate(),
          source_job_id: Ecto.UUID.generate(),
          source_trigger_id: Ecto.UUID.generate()
        })

      refute changeset.valid?

      assert {:source_job_id,
              {"source_job_id and source_trigger_id are mutually exclusive", []}} in changeset.errors,
             "error on the first change in the case both are set"

      changeset =
        Edge.changeset(%Edge{source_job_id: Ecto.UUID.generate()}, %{
          workflow_id: Ecto.UUID.generate(),
          source_trigger_id: Ecto.UUID.generate()
        })

      refute changeset.valid?

      assert {
               :source_trigger_id,
               {"source_job_id and source_trigger_id are mutually exclusive", []}
             } in changeset.errors
    end

    test "can't set the target job to the same as the source job" do
      job_id = Ecto.UUID.generate()

      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: Ecto.UUID.generate(),
          source_job_id: job_id,
          condition_type: :on_job_success,
          target_job_id: job_id
        })

      refute changeset.valid?

      assert {
               :target_job_id,
               {"target_job_id must be different from source_job_id", []}
             } in changeset.errors

      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: Ecto.UUID.generate(),
          source_job_id: job_id,
          condition_type: :on_job_success,
          target_job_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end

    test "can't assign a node from a different workflow" do
      workflow = Lightning.WorkflowsFixtures.workflow_fixture()
      job = Lightning.JobsFixtures.job_fixture()

      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: workflow.id,
          condition_type: :on_job_success,
          source_job_id: job.id
        })

      {:error, changeset} = Repo.insert(changeset)

      refute changeset.valid?

      assert {
               :source_job_id,
               {"job doesn't exist, or is not in the same workflow",
                [
                  constraint: :foreign,
                  constraint_name: "workflow_edges_source_job_id_fkey"
                ]}
             } in changeset.errors

      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: workflow.id,
          condition_type: :on_job_success,
          source_job_id: insert(:job, workflow: workflow).id,
          target_job_id: job.id
        })

      {:error, changeset} = Repo.insert(changeset)

      refute changeset.valid?

      assert {
               :target_job_id,
               {"job doesn't exist, or is not in the same workflow",
                [
                  constraint: :foreign,
                  constraint_name: "workflow_edges_target_job_id_fkey"
                ]}
             } in changeset.errors

      trigger =
        Lightning.Workflows.Trigger.changeset(
          %Lightning.Workflows.Trigger{},
          %{
            name: "test",
            workflow_id: job.workflow_id
          }
        )
        |> Repo.insert!()

      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: workflow.id,
          condition_type: :always,
          source_trigger_id: trigger.id
        })

      {:error, changeset} = Repo.insert(changeset)

      refute changeset.valid?

      assert {
               :source_trigger_id,
               {"trigger doesn't exist, or is not in the same workflow",
                [
                  constraint: :foreign,
                  constraint_name: "workflow_edges_source_trigger_id_fkey"
                ]}
             } in changeset.errors
    end

    test "new edges are enabled by default" do
      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: Ecto.UUID.generate(),
          source_job_id: Ecto.UUID.generate(),
          target_job_id: Ecto.UUID.generate(),
          condition_type: :on_job_success
        })

      assert changeset.valid?

      assert changeset.data.enabled ||
               Map.get(changeset.changes, :enabled, true),
             "New edges should be enabled by default"
    end

    test "edges with source_trigger_id should be enabled" do
      changeset =
        Edge.changeset(%Edge{}, %{
          workflow_id: Ecto.UUID.generate(),
          source_trigger_id: Ecto.UUID.generate(),
          target_job_id: Ecto.UUID.generate(),
          condition_type: :always
        })

      assert changeset.valid?

      assert changeset.data.enabled ||
               Map.get(changeset.changes, :enabled, true),
             "Edges with a source_trigger_id should always be enabled"
    end

    test "requires js_expression condition to have a label and js body" do
      changeset =
        Edge.changeset(
          %Edge{
            id: Ecto.UUID.generate(),
            workflow_id: Ecto.UUID.generate(),
            source_job_id: Ecto.UUID.generate(),
            enabled: true
          },
          %{condition_type: :js_expression}
        )

      assert changeset.errors == [
               condition_expression: {"can't be blank", [validation: :required]}
             ]
    end

    test "requires js_expression label and condition to have limited length" do
      changeset =
        Edge.changeset(
          %Edge{
            id: Ecto.UUID.generate(),
            workflow_id: Ecto.UUID.generate(),
            source_job_id: Ecto.UUID.generate(),
            enabled: true
          },
          %{
            condition_type: :js_expression,
            condition_label: String.duplicate("a", 256),
            condition_expression: String.duplicate("a", 256)
          }
        )

      # Asserted by field rather than as an ordered list: the label check moved
      # out of the :js_expression branch so it runs after the expression one,
      # and the order of changeset.errors is not what this test is about.
      errors = errors_on(changeset)

      assert errors[:condition_expression] == [
               "should be at most 255 character(s)"
             ]

      assert errors[:condition_label] == ["should be at most 255 character(s)"]
    end

    test "requires JS expression to have valid syntax" do
      edge = %Edge{
        id: Ecto.UUID.generate(),
        workflow_id: Ecto.UUID.generate(),
        source_job_id: Ecto.UUID.generate(),
        enabled: true
      }

      js_attrs = %{
        condition_type: :js_expression,
        condition_label: "Some JS Expression"
      }

      changeset =
        Edge.changeset(
          edge,
          Map.put(
            js_attrs,
            :condition_expression,
            "state.data.foo == 'bar';"
          )
        )

      assert Enum.empty?(changeset.errors)

      changeset =
        Edge.changeset(
          edge,
          Map.put(
            js_attrs,
            :condition_expression,
            "this.process"
          )
        )

      refute changeset.errors == [
               condition_expression: {"contains unacceptable words", []}
             ]

      assert Enum.empty?(changeset.errors)

      changeset =
        Edge.changeset(
          edge,
          Map.put(
            js_attrs,
            :condition_expression,
            "state.data.patient.status == 'processing'"
          )
        )

      assert Enum.empty?(changeset.errors)

      changeset =
        Edge.changeset(
          edge,
          Map.put(
            js_attrs,
            :condition_expression,
            "await state.data.myFunction();"
          )
        )

      refute changeset.errors == [
               condition_expression: {"contains unacceptable words", []}
             ]

      assert Enum.empty?(changeset.errors)

      changeset =
        Edge.changeset(
          edge,
          Map.put(
            js_attrs,
            :condition_expression,
            "eval('2 + 2')"
          )
        )

      refute changeset.errors == [
               condition_expression: {"contains unacceptable words", []}
             ]

      assert Enum.empty?(changeset.errors)

      changeset =
        Edge.changeset(
          edge,
          Map.put(
            js_attrs,
            :condition_expression,
            "state.data.foo == 'bar' || state.data.bar == 'foo'"
          )
        )

      assert Enum.empty?(changeset.errors)
    end

    test "allows JS expression to have import or require statements" do
      edge = %Edge{
        id: Ecto.UUID.generate(),
        workflow_id: Ecto.UUID.generate(),
        source_job_id: Ecto.UUID.generate(),
        enabled: true
      }

      js_attrs = %{
        condition_type: :js_expression,
        condition_label: "Some JS Expression"
      }

      changeset =
        Edge.changeset(
          edge,
          Map.put(
            js_attrs,
            :condition_expression,
            "{ var fs = require('fs'); }"
          )
        )

      refute changeset.errors == [
               condition_expression: {"contains unacceptable words", []}
             ]

      assert Enum.empty?(changeset.errors)

      changeset =
        Edge.changeset(
          edge,
          Map.put(
            js_attrs,
            :condition_expression,
            "{ var fs = import('fs'); }"
          )
        )

      refute changeset.errors == [
               condition_expression: {"contains unacceptable words", []}
             ]

      assert Enum.empty?(changeset.errors)
    end
  end
end
