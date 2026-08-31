defmodule Lightning.Workflows.SpecTest do
  use ExUnit.Case, async: true

  alias Lightning.Workflows.Spec

  defp spec(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "My Workflow",
        "jobs" => %{
          "transform-data" => %{
            "name" => "Transform data",
            "adaptor" => "@openfn/language-common@latest",
            "body" => "fn(state => state);"
          }
        },
        "triggers" => %{
          "webhook" => %{"type" => "webhook", "enabled" => true}
        },
        "edges" => %{
          "webhook->transform-data" => %{
            "source_trigger" => "webhook",
            "target_job" => "transform-data",
            "condition_type" => "always",
            "enabled" => true
          }
        }
      },
      overrides
    )
  end

  describe "to_document/2" do
    test "resolves key references into an id-wired provisioning document" do
      assert {:ok, document} = Spec.to_document(spec())

      assert %{
               "id" => workflow_id,
               "name" => "My Workflow",
               "jobs" => [job],
               "triggers" => [trigger],
               "edges" => [edge]
             } = document

      assert {:ok, _} = Ecto.UUID.cast(workflow_id)

      assert job == %{
               "id" => job["id"],
               "name" => "Transform data",
               "adaptor" => "@openfn/language-common@latest",
               "body" => "fn(state => state);"
             }

      assert trigger == %{
               "id" => trigger["id"],
               "type" => "webhook",
               "enabled" => true
             }

      assert edge == %{
               "id" => edge["id"],
               "condition_type" => "always",
               "enabled" => true,
               "source_trigger_id" => trigger["id"],
               "target_job_id" => job["id"]
             }
    end

    test "honours explicit ids and mints the rest through :id_fun" do
      job_id = Ecto.UUID.generate()

      spec =
        spec()
        |> put_in(["jobs", "transform-data", "id"], job_id)

      assert {:ok, document} =
               Spec.to_document(spec,
                 id_fun: fn kind, key -> "#{kind}:#{key}" end
               )

      assert document["id"] == "workflow:My Workflow"
      assert [%{"id" => ^job_id}] = document["jobs"]
      assert [%{"id" => "trigger:webhook"}] = document["triggers"]
      assert [%{"id" => "edge:webhook->transform-data"}] = document["edges"]
    end

    test "wires job-to-job edges, condition expressions and cron cursors" do
      spec =
        spec(%{
          "jobs" => %{
            "a" => %{"name" => "a", "adaptor" => "common", "body" => "x"},
            "b" => %{"name" => "b", "adaptor" => "common", "body" => "y"}
          },
          "triggers" => %{
            "cron" => %{
              "type" => "cron",
              "enabled" => false,
              "cron_expression" => "0 * * * *",
              "cron_cursor_job" => "b"
            }
          },
          "edges" => %{
            "a->b" => %{
              "source_job" => "a",
              "target_job" => "b",
              "condition_type" => "js_expression",
              "condition_expression" => "state.data.ok",
              "condition_label" => "only when ok",
              "enabled" => true
            }
          }
        })

      assert {:ok, document} = Spec.to_document(spec)

      ids = Map.new(document["jobs"], &{&1["name"], &1["id"]})

      assert [
               %{
                 "type" => "cron",
                 "enabled" => false,
                 "cron_expression" => "0 * * * *",
                 "cron_cursor_job_id" => cursor_id
               }
             ] = document["triggers"]

      assert cursor_id == ids["b"]

      assert [
               %{
                 "source_job_id" => source_id,
                 "target_job_id" => target_id,
                 "condition_type" => "js_expression",
                 "condition_expression" => "state.data.ok",
                 "condition_label" => "only when ok"
               }
             ] = document["edges"]

      assert source_id == ids["a"]
      assert target_id == ids["b"]
    end

    test "resolves a job's credential name against :credentials" do
      project_credential_id = Ecto.UUID.generate()

      spec = put_in(spec(), ["jobs", "transform-data", "credential"], "dhis2")

      assert {:ok, %{"jobs" => [job]}} =
               Spec.to_document(spec,
                 credentials: %{"dhis2" => project_credential_id}
               )

      assert job["project_credential_id"] == project_credential_id

      assert {:error, message} = Spec.to_document(spec)
      assert message =~ ~s(Job "transform-data" references credential "dhis2")
    end

    test "an empty triggers map means a trigger-less workflow" do
      spec = spec(%{"triggers" => %{}, "edges" => %{}})

      assert {:ok, %{"triggers" => [], "edges" => []}} = Spec.to_document(spec)
    end

    test "accepts an editor-exported spec, positions and explicit nulls included" do
      # The shape convertWorkflowStateToSpec produces: `pos` on jobs and
      # triggers, and explicit nulls for the fields it always emits.
      exported = %{
        "id" => Ecto.UUID.generate(),
        "name" => "Exported",
        "jobs" => %{
          "transform-data" => %{
            "id" => Ecto.UUID.generate(),
            "name" => "Transform data",
            "adaptor" => "@openfn/language-common@latest",
            "body" => "fn(state => state);",
            "pos" => %{"x" => 400, "y" => 300}
          }
        },
        "triggers" => %{
          "webhook" => %{
            "id" => Ecto.UUID.generate(),
            "type" => "webhook",
            "enabled" => true,
            "webhook_reply" => nil,
            "webhook_response_config" => %{"success_code" => 202},
            "pos" => %{"x" => 400, "y" => 100}
          }
        },
        "edges" => %{
          "webhook->transform-data" => %{
            "id" => Ecto.UUID.generate(),
            "source_trigger" => "webhook",
            "target_job" => "transform-data",
            "condition_type" => "always",
            "enabled" => true
          }
        }
      }

      assert :ok = Spec.validate(exported)
      assert {:ok, document} = Spec.to_document(exported)

      assert [trigger] = document["triggers"]
      assert trigger["webhook_reply"] == nil
      assert trigger["webhook_response_config"] == %{"success_code" => 202}

      # `pos` is part of the format but can't be provisioned, so it must not
      # leak into the document (the provisioner rejects extraneous params).
      refute Map.has_key?(trigger, "pos")
      refute document["jobs"] |> hd() |> Map.has_key?("pos")
    end

    test "omitted optional fields are left out rather than nilled" do
      assert {:ok, %{"triggers" => [trigger], "edges" => [edge]}} =
               Spec.to_document(spec())

      refute Map.has_key?(trigger, "webhook_reply")
      refute Map.has_key?(edge, "condition_expression")
    end

    test "output order is stable regardless of map ordering" do
      keys = fn document ->
        {Enum.map(document["jobs"], & &1["name"]),
         Enum.map(document["edges"], & &1["condition_type"])}
      end

      spec =
        spec(%{
          "jobs" =>
            Map.new(["c", "a", "b"], fn name ->
              {name, %{"name" => name, "adaptor" => "common", "body" => "x"}}
            end),
          "triggers" => %{},
          "edges" => %{
            "b->c" => %{
              "source_job" => "b",
              "target_job" => "c",
              "condition_type" => "on_job_failure",
              "enabled" => true
            },
            "a->b" => %{
              "source_job" => "a",
              "target_job" => "b",
              "condition_type" => "on_job_success",
              "enabled" => true
            }
          }
        })

      assert {:ok, document} = Spec.to_document(spec)

      assert keys.(document) ==
               {["a", "b", "c"], ["on_job_success", "on_job_failure"]}
    end

    test "reports dangling key references" do
      dangling_target =
        put_in(
          spec(),
          ["edges", "webhook->transform-data", "target_job"],
          "nope"
        )

      assert {:error, message} = Spec.to_document(dangling_target)

      assert message =~
               ~s(Edge "webhook->transform-data" references job "nope")

      assert message =~ ~s(known: "transform-data")

      dangling_trigger =
        put_in(
          spec(),
          ["edges", "webhook->transform-data", "source_trigger"],
          "nope"
        )

      assert {:error, message} = Spec.to_document(dangling_trigger)
      assert message =~ ~s(references trigger "nope")

      dangling_cursor =
        spec()
        |> put_in(["triggers", "webhook"], %{
          "type" => "cron",
          "enabled" => true,
          "cron_expression" => "0 * * * *",
          "cron_cursor_job" => "nope"
        })

      assert {:error, message} = Spec.to_document(dangling_cursor)
      assert message =~ ~s(Trigger "webhook" references job "nope")
    end

    test "rejects edges without a source, or with two" do
      no_source =
        update_in(
          spec(),
          ["edges", "webhook->transform-data"],
          &Map.delete(&1, "source_trigger")
        )

      assert {:error, message} = Spec.to_document(no_source)
      assert message =~ "needs a source_trigger or a source_job"

      two_sources =
        put_in(
          spec(),
          ["edges", "webhook->transform-data", "source_job"],
          "transform-data"
        )

      assert {:error, message} = Spec.to_document(two_sources)
      assert message =~ "can only have one source"
    end
  end

  describe "validate/1" do
    test "accepts what the editor's YAML import accepts" do
      assert :ok = Spec.validate(spec())
    end

    test "rejects unknown keys, missing keys and bad enums" do
      assert {:error, message} =
               Spec.validate(put_in(spec(), ["nam"], "typo"))

      assert message =~ "Invalid workflow spec"
      # the error path names the offending key
      assert message =~ "#/nam"
      assert message =~ "additional properties"

      assert {:error, message} = Spec.validate(Map.delete(spec(), "edges"))
      assert message =~ "Required property edges was not present"

      assert {:error, message} =
               Spec.validate(
                 put_in(
                   spec(),
                   ["triggers", "webhook", "type"],
                   "carrier-pigeon"
                 )
               )

      assert message =~ "#/triggers/webhook"
    end

    test "rejects two jobs sharing a name" do
      spec =
        put_in(spec(), ["jobs", "transform-again"], %{
          "name" => "Transform data",
          "adaptor" => "common",
          "body" => "x"
        })

      assert {:error, message} = Spec.validate(spec)
      assert message =~ "Duplicate job name(s) in workflow spec"
      assert message =~ ~s("Transform data")
    end

    test "rejects a non-map spec" do
      assert {:error, message} = Spec.validate("nope")
      assert message =~ "Expected a workflow spec map"
    end
  end

  describe "to_document!/2" do
    test "raises on an invalid spec" do
      assert_raise RuntimeError, ~r/Invalid workflow spec/, fn ->
        Spec.to_document!(Map.delete(spec(), "jobs"))
      end
    end
  end
end
