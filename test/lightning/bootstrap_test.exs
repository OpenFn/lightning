defmodule Lightning.BootstrapTest do
  use Lightning.DataCase, async: true

  alias Lightning.Bootstrap
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Workflow

  defp scenario do
    %{
      "users" => [
        %{
          "email" => "super@openfn.org",
          "first_name" => "Sizwe",
          "superuser" => true,
          "api_token" => true
        }
      ],
      "projects" => [
        %{
          "name" => "bootstrap-project",
          "members" => [%{"email" => "super@openfn.org", "role" => "owner"}],
          "workflows" => [
            %{
              "name" => "Webhook Workflow",
              "trigger" => %{"type" => "webhook"},
              "jobs" => [
                %{
                  "name" => "Transform",
                  "adaptor" => "@openfn/language-common@latest",
                  "body" => "fn(state => state);"
                }
              ],
              "edges" => [
                %{
                  "from" => "trigger",
                  "to" => "Transform",
                  "condition" => "always"
                }
              ]
            }
          ]
        }
      ]
    }
  end

  describe "create_from_map/1 and manifest/1" do
    test "builds a manifest with the generated token and a webhook path" do
      manifest =
        scenario() |> Bootstrap.create_from_map() |> Bootstrap.manifest()

      # User carries a generated (non-nil) API token and superuser flag.
      assert %{users: [user_manifest], projects: [project_manifest]} = manifest

      assert %{
               email: "super@openfn.org",
               superuser: true,
               api_token: api_token
             } = user_manifest

      assert is_binary(api_token)

      # Project and its webhook workflow are described, with the webhook path
      # derived from the trigger id.
      assert %{
               name: "bootstrap-project",
               workflows: [
                 %{
                   name: "Webhook Workflow",
                   trigger: %{
                     id: trigger_id,
                     type: :webhook,
                     webhook_path: webhook_path
                   },
                   jobs: [%{name: "Transform"}]
                 }
               ]
             } = project_manifest

      assert webhook_path == "/i/#{trigger_id}"
    end

    test "provisions a workflow with a complete current snapshot" do
      manifest =
        scenario() |> Bootstrap.create_from_map() |> Bootstrap.manifest()

      %{projects: [%{workflows: [%{id: workflow_id}]}]} = manifest

      snapshot = Snapshot.get_current_for(%Workflow{id: workflow_id})

      # The snapshot reflects the full graph: the job, the trigger and the edge
      # wiring them together.
      assert %Snapshot{
               jobs: [%{name: "Transform"}],
               triggers: [%{id: trigger_id, type: :webhook}],
               edges: [
                 %{
                   condition_type: :always,
                   source_trigger_id: trigger_id,
                   target_job_id: _
                 }
               ]
             } = snapshot
    end

    test "raises when bootstrapping is disabled" do
      original = Application.get_env(:lightning, Lightning.Bootstrap)
      Application.put_env(:lightning, Lightning.Bootstrap, enabled: false)

      on_exit(fn ->
        Application.put_env(:lightning, Lightning.Bootstrap, original)
      end)

      assert_raise RuntimeError, ~r/ALLOW_BOOTSTRAP/, fn ->
        Bootstrap.create_from_map(scenario())
      end
    end
  end
end
