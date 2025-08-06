defmodule Lightning.Workflows.ParamsComparatorTest do
  use ExUnit.Case, async: true

  alias Lightning.Workflows.ParamsComparator

  describe "equivalent?/3 with nil values" do
    test "returns true when both workflows are nil" do
      assert ParamsComparator.equivalent?(nil, nil)
    end

    test "returns false when first workflow is nil and second is not" do
      workflow = %{"name" => "test"}
      refute ParamsComparator.equivalent?(nil, workflow)
    end

    test "returns false when second workflow is nil and first is not" do
      workflow = %{"name" => "test"}
      refute ParamsComparator.equivalent?(workflow, nil)
    end
  end

  describe "equivalent?/3 with identical workflows" do
    test "returns true for identical simple workflows" do
      workflow = %{
        "name" => "My Workflow",
        "project_id" => "123",
        "jobs" => [],
        "triggers" => [],
        "edges" => []
      }

      assert ParamsComparator.equivalent?(workflow, workflow)
    end

    test "returns true for identical complex workflows" do
      workflow = build_complex_workflow()
      assert ParamsComparator.equivalent?(workflow, workflow)
    end
  end

  describe "equivalent?/3 with different workflows" do
    test "returns false when workflow names differ" do
      workflow1 = %{"name" => "Workflow 1"}
      workflow2 = %{"name" => "Workflow 2"}

      refute ParamsComparator.equivalent?(workflow1, workflow2)
    end

    test "returns false when job bodies differ" do
      workflow1 = %{
        "jobs" => [%{"id" => "1", "name" => "Job", "body" => "code1"}]
      }

      workflow2 = %{
        "jobs" => [%{"id" => "1", "name" => "Job", "body" => "code2"}]
      }

      refute ParamsComparator.equivalent?(workflow1, workflow2)
    end
  end

  describe "comparison modes" do
    test "semantic mode ignores IDs by default" do
      workflow1 = %{
        "id" => "workflow-1",
        "name" => "Test",
        "jobs" => [%{"id" => "job-1", "name" => "Job A", "body" => "code"}],
        "triggers" => [
          %{"id" => "trigger-1", "type" => "webhook", "enabled" => true}
        ],
        "edges" => []
      }

      workflow2 = %{
        "id" => "workflow-2",
        "name" => "Test",
        "jobs" => [%{"id" => "job-2", "name" => "Job A", "body" => "code"}],
        "triggers" => [
          %{"id" => "trigger-2", "type" => "webhook", "enabled" => true}
        ],
        "edges" => []
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end

    test "exact mode compares all fields including IDs" do
      workflow1 = %{
        "id" => "workflow-1",
        "name" => "Test"
      }

      workflow2 = %{
        "id" => "workflow-2",
        "name" => "Test"
      }

      refute ParamsComparator.equivalent?(workflow1, workflow2, mode: :exact)
    end

    test "semantic mode ignores timestamps" do
      workflow1 = %{
        "name" => "Test",
        "inserted_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T00:00:00Z"
      }

      workflow2 = %{
        "name" => "Test",
        "inserted_at" => "2024-02-01T00:00:00Z",
        "updated_at" => "2024-02-01T00:00:00Z"
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end
  end

  describe "custom ignore options" do
    test "ignores specific workflow fields" do
      workflow1 = %{"name" => "Test", "concurrency" => 1}
      workflow2 = %{"name" => "Test", "concurrency" => 5}

      assert ParamsComparator.equivalent?(workflow1, workflow2,
               ignore: [workflow: [:concurrency]]
             )
    end

    test "ignores specific job fields" do
      workflow1 = %{
        "jobs" => [
          %{
            "name" => "Job",
            "body" => "code1",
            "adaptor" => "@openfn/language-http@1.0"
          }
        ]
      }

      workflow2 = %{
        "jobs" => [
          %{
            "name" => "Job",
            "body" => "code2",
            "adaptor" => "@openfn/language-http@2.0"
          }
        ]
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2,
               ignore: [jobs: [:body, :adaptor]]
             )
    end

    test "ignores all job fields with :all" do
      workflow1 = %{
        "name" => "Test",
        "jobs" => [%{"name" => "Job A", "body" => "code1", "adaptor" => "v1"}]
      }

      workflow2 = %{
        "name" => "Test",
        "jobs" => [%{"name" => "Job B", "body" => "code2", "adaptor" => "v2"}]
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2,
               ignore: [jobs: :all]
             )
    end

    test "ignores all trigger fields with :all" do
      workflow1 = %{
        "name" => "Test",
        "triggers" => [
          %{"type" => "webhook", "enabled" => true, "custom_path" => "/path1"}
        ]
      }

      workflow2 = %{
        "name" => "Test",
        "triggers" => [
          %{
            "type" => "cron",
            "enabled" => false,
            "cron_expression" => "* * * * *"
          }
        ]
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2,
               ignore: [triggers: :all]
             )
    end

    test "ignores all edge fields with :all" do
      workflow1 = %{
        "name" => "Test",
        "edges" => [
          %{
            "source_job_id" => "1",
            "target_job_id" => "2",
            "condition_type" => "on_success"
          }
        ]
      }

      workflow2 = %{
        "name" => "Test",
        "edges" => [
          %{
            "source_job_id" => "3",
            "target_job_id" => "4",
            "condition_type" => "on_failure"
          }
        ]
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2,
               ignore: [edges: :all]
             )
    end
  end

  describe "field key handling" do
    test "handles both string and atom keys" do
      workflow1 = %{"name" => "Test", "project_id" => "123"}
      workflow2 = %{name: "Test", project_id: "123"}

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end

    test "handles mixed string and atom keys in nested structures" do
      workflow1 = %{
        "name" => "Test",
        "jobs" => [%{"name" => "Job", "body" => "code"}]
      }

      workflow2 = %{
        name: "Test",
        jobs: [%{name: "Job", body: "code"}]
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end

    test "handles missing fields gracefully" do
      workflow1 = %{"name" => "Test"}
      workflow2 = %{"name" => "Test", "description" => "A test workflow"}

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end

    test "handles nil values in fields" do
      workflow1 = %{"name" => "Test", "project_id" => nil}
      workflow2 = %{"name" => "Test", "project_id" => nil}

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end
  end

  describe "list ordering normalization" do
    test "jobs with different order are equivalent in semantic mode" do
      workflow1 = %{
        "jobs" => [
          %{"id" => "1", "name" => "Job A", "body" => "code"},
          %{"id" => "2", "name" => "Job B", "body" => "code"}
        ]
      }

      workflow2 = %{
        "jobs" => [
          %{"id" => "2", "name" => "Job B", "body" => "code"},
          %{"id" => "1", "name" => "Job A", "body" => "code"}
        ]
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end

    test "triggers with different order are equivalent" do
      workflow1 = %{
        "triggers" => [
          %{"id" => "1", "type" => "webhook", "enabled" => true},
          %{"id" => "2", "type" => "cron", "enabled" => false}
        ]
      }

      workflow2 = %{
        "triggers" => [
          %{"id" => "2", "type" => "cron", "enabled" => false},
          %{"id" => "1", "type" => "webhook", "enabled" => true}
        ]
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end

    test "edges with different order are equivalent" do
      workflow1 = %{
        "jobs" => [
          %{"id" => "job1", "name" => "Job 1"},
          %{"id" => "job2", "name" => "Job 2"}
        ],
        "edges" => [
          %{"id" => "e1", "source_job_id" => "job1", "target_job_id" => "job2"},
          %{"id" => "e2", "source_job_id" => "job2", "target_job_id" => "job1"}
        ]
      }

      workflow2 = %{
        "jobs" => [
          %{"id" => "job1", "name" => "Job 1"},
          %{"id" => "job2", "name" => "Job 2"}
        ],
        "edges" => [
          %{"id" => "e2", "source_job_id" => "job2", "target_job_id" => "job1"},
          %{"id" => "e1", "source_job_id" => "job1", "target_job_id" => "job2"}
        ]
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end
  end

  describe "edge source/target resolution" do
    test "handles edges with job sources" do
      workflow1 = %{
        "jobs" => [
          %{"id" => "job1", "name" => "Source Job"},
          %{"id" => "job2", "name" => "Target Job"}
        ],
        "edges" => [
          %{"source_job_id" => "job1", "target_job_id" => "job2"}
        ]
      }

      workflow2 = %{
        "jobs" => [
          %{"id" => "different-id-1", "name" => "Source Job"},
          %{"id" => "different-id-2", "name" => "Target Job"}
        ],
        "edges" => [
          %{
            "source_job_id" => "different-id-1",
            "target_job_id" => "different-id-2"
          }
        ]
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end

    test "handles edges with trigger sources" do
      workflow1 = %{
        "triggers" => [
          %{"id" => "trigger1", "type" => "webhook", "enabled" => true}
        ],
        "jobs" => [%{"id" => "job1", "name" => "Job"}],
        "edges" => [
          %{"source_trigger_id" => "trigger1", "target_job_id" => "job1"}
        ]
      }

      workflow2 = %{
        "triggers" => [
          %{"id" => "trigger2", "type" => "webhook", "enabled" => true}
        ],
        "jobs" => [%{"id" => "job2", "name" => "Job"}],
        "edges" => [
          %{"source_trigger_id" => "trigger2", "target_job_id" => "job2"}
        ]
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end

    test "handles edges with nil sources gracefully" do
      workflow = %{
        "edges" => [
          %{"source_job_id" => nil, "target_job_id" => "job1"},
          %{"source_trigger_id" => nil, "target_job_id" => "job2"}
        ]
      }

      assert ParamsComparator.equivalent?(workflow, workflow)
    end
  end

  describe "complex scenarios" do
    test "empty workflows are equivalent" do
      workflow1 = %{}
      workflow2 = %{}

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end

    test "workflows with only jobs (no triggers/edges) are compared correctly" do
      workflow1 = %{
        "name" => "Jobs Only",
        "jobs" => [
          %{"name" => "Job A", "body" => "code"},
          %{"name" => "Job B", "body" => "code"}
        ]
      }

      workflow2 = %{
        "name" => "Jobs Only",
        "jobs" => [
          %{"name" => "Job A", "body" => "code"},
          %{"name" => "Job B", "body" => "code"}
        ]
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end

    test "complex workflow with all components and different IDs are equivalent semantically" do
      workflow1 = %{
        "id" => "workflow-uuid-1",
        "name" => "ETL Pipeline",
        "project_id" => "project-1",
        "jobs" => [
          %{
            "id" => "extract-1",
            "name" => "Extract Data",
            "body" => "getData();",
            "adaptor" => "@openfn/language-http"
          },
          %{
            "id" => "transform-1",
            "name" => "Transform Data",
            "body" => "transformData();",
            "adaptor" => "@openfn/language-common"
          }
        ],
        "triggers" => [
          %{
            "id" => "webhook-1",
            "type" => "webhook",
            "enabled" => true
          }
        ],
        "edges" => [
          %{
            "id" => "edge-1",
            "source_trigger_id" => "webhook-1",
            "target_job_id" => "extract-1",
            "condition_type" => "always"
          },
          %{
            "id" => "edge-2",
            "source_job_id" => "extract-1",
            "target_job_id" => "transform-1",
            "condition_type" => "on_success"
          }
        ]
      }

      workflow2 = %{
        "id" => "workflow-uuid-2",
        "name" => "ETL Pipeline",
        "project_id" => "project-2",
        "jobs" => [
          %{
            "id" => "extract-2",
            "name" => "Extract Data",
            "body" => "getData();",
            "adaptor" => "@openfn/language-http"
          },
          %{
            "id" => "transform-2",
            "name" => "Transform Data",
            "body" => "transformData();",
            "adaptor" => "@openfn/language-common"
          }
        ],
        "triggers" => [
          %{
            "id" => "webhook-2",
            "type" => "webhook",
            "enabled" => true
          }
        ],
        "edges" => [
          %{
            "id" => "edge-3",
            "source_trigger_id" => "webhook-2",
            "target_job_id" => "extract-2",
            "condition_type" => "always"
          },
          %{
            "id" => "edge-4",
            "source_job_id" => "extract-2",
            "target_job_id" => "transform-2",
            "condition_type" => "on_success"
          }
        ]
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end
  end

  describe "sorting behavior" do
    test "jobs are sorted by name when IDs are ignored (semantic mode)" do
      # Even with different insertion order, should be equivalent
      workflow1 = %{
        "jobs" => [
          %{"id" => "1", "name" => "Zebra", "body" => "code"},
          %{"id" => "2", "name" => "Alpha", "body" => "code"}
        ]
      }

      workflow2 = %{
        "jobs" => [
          %{"id" => "3", "name" => "Alpha", "body" => "code"},
          %{"id" => "4", "name" => "Zebra", "body" => "code"}
        ]
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end

    test "jobs are sorted by ID in exact mode" do
      workflow1 = %{
        "jobs" => [
          %{"id" => "2", "name" => "Job", "body" => "code"},
          %{"id" => "1", "name" => "Job", "body" => "code"}
        ]
      }

      workflow2 = %{
        "jobs" => [
          %{"id" => "1", "name" => "Job", "body" => "code"},
          %{"id" => "2", "name" => "Job", "body" => "code"}
        ]
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2, mode: :exact)
    end

    test "triggers are sorted by type and enabled status in semantic mode" do
      workflow1 = %{
        "triggers" => [
          %{"id" => "1", "type" => "webhook", "enabled" => false},
          %{"id" => "2", "type" => "cron", "enabled" => true},
          %{"id" => "3", "type" => "webhook", "enabled" => true}
        ]
      }

      workflow2 = %{
        "triggers" => [
          %{"id" => "4", "type" => "cron", "enabled" => true},
          %{"id" => "5", "type" => "webhook", "enabled" => true},
          %{"id" => "6", "type" => "webhook", "enabled" => false}
        ]
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end
  end

  describe "edge cases" do
    test "raises FunctionClauseError for non-map data in get_field" do
      workflow1 = %{"name" => "Test", "jobs" => ["not a map"]}
      workflow2 = %{"name" => "Test", "jobs" => []}

      assert_raise FunctionClauseError, fn ->
        ParamsComparator.equivalent?(workflow1, workflow2)
      end
    end

    test "raises FunctionClauseError for invalid ignore list format" do
      workflow = %{"name" => "Test"}

      assert_raise FunctionClauseError, fn ->
        ParamsComparator.equivalent?(workflow, workflow, ignore: "not a list")
      end
    end

    test "exercises all sorting branches - edges without IDs in exact mode" do
      workflow1 = %{
        "edges" => [
          %{"source_job_id" => "j1", "target_job_id" => "j2"},
          %{"source_job_id" => "j2", "target_job_id" => "j3"}
        ]
      }

      workflow2 = %{
        "edges" => [
          %{"source_job_id" => "j2", "target_job_id" => "j3"},
          %{"source_job_id" => "j1", "target_job_id" => "j2"}
        ]
      }

      refute ParamsComparator.equivalent?(workflow1, workflow2, mode: :exact)
    end

    test "handles edges with both source_job_id and source_trigger_id as nil" do
      workflow = %{
        "edges" => [
          %{
            "source_job_id" => nil,
            "source_trigger_id" => nil,
            "target_job_id" => nil
          }
        ]
      }

      assert ParamsComparator.equivalent?(workflow, workflow)
    end

    test "handles workflows with nil jobs, triggers, and edges fields" do
      workflow1 = %{
        "name" => "Test",
        "jobs" => nil,
        "triggers" => nil,
        "edges" => nil
      }

      workflow2 = %{
        "name" => "Test"
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end

    test "handles edge case where source_job_id is false (not nil)" do
      workflow = %{
        "jobs" => [%{"id" => "job1", "name" => "Job"}],
        "edges" => [
          %{
            "source_job_id" => false,
            "source_trigger_id" => "trigger1",
            "target_job_id" => "job1"
          }
        ]
      }

      assert ParamsComparator.equivalent?(workflow, workflow)
    end

    test "comparing with unusual but valid mode option" do
      workflow = %{"name" => "Test"}

      assert ParamsComparator.equivalent?(workflow, workflow, mode: :unknown)
    end

    test "handles workflow with positions field in exact mode" do
      workflow1 = %{
        "name" => "Test",
        "positions" => %{"job1" => %{"x" => 100, "y" => 200}}
      }

      workflow2 = %{
        "name" => "Test",
        "positions" => %{"job1" => %{"x" => 150, "y" => 250}}
      }

      refute ParamsComparator.equivalent?(workflow1, workflow2, mode: :exact)
    end

    test "edge mappings with missing jobs" do
      workflow = %{
        "jobs" => nil,
        "triggers" => [%{"id" => "t1", "type" => "webhook", "enabled" => true}],
        "edges" => [
          %{"source_trigger_id" => "t1", "target_job_id" => "missing-job"}
        ]
      }

      assert ParamsComparator.equivalent?(workflow, workflow)
    end

    test "handles unknown pattern in build_ignore_list" do
      workflow = %{"name" => "Test"}

      assert ParamsComparator.equivalent?(workflow, workflow,
               mode: "invalid_mode"
             )
    end

    test "flatten_ignore_list with empty list" do
      workflow = %{"name" => "Test"}

      assert ParamsComparator.equivalent?(workflow, workflow, ignore: [])
    end

    test "handles target_job_id nil in determine_target" do
      workflow = %{
        "jobs" => [%{"id" => "job1", "name" => "Job"}],
        "edges" => [
          %{
            "source_job_id" => "job1",
            "target_job_id" => nil
          }
        ]
      }

      assert ParamsComparator.equivalent?(workflow, workflow)
    end

    test "handles false (but not nil) target_job_id" do
      workflow = %{
        "jobs" => [%{"id" => "job1", "name" => "Job"}],
        "edges" => [
          %{
            "source_job_id" => "job1",
            "target_job_id" => false
          }
        ]
      }

      assert ParamsComparator.equivalent?(workflow, workflow)
    end

    test "add_unless_ignored with nil ignore_key uses key as check_key" do
      workflow1 = %{"name" => "Test", "errors" => ["error1"]}
      workflow2 = %{"name" => "Test", "errors" => ["error2"]}

      assert ParamsComparator.equivalent?(workflow1, workflow2)
    end

    test "empty string field name in get_field" do
      workflow = %{"" => "value", "name" => "Test"}

      assert ParamsComparator.equivalent?(workflow, workflow)
    end

    test "ignores all workflow fields with :all" do
      workflow1 = %{
        "id" => "id1",
        "name" => "Workflow 1",
        "project_id" => "proj1",
        "concurrency" => 5,
        "enable_job_logs" => true
      }

      workflow2 = %{
        "id" => "id2",
        "name" => "Workflow 2",
        "project_id" => "proj2",
        "concurrency" => 10,
        "enable_job_logs" => false
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2,
               ignore: [workflow: :all]
             )
    end

    test "trigger sorting by ID in exact mode" do
      workflow1 = %{
        "triggers" => [
          %{"id" => "2", "type" => "webhook", "enabled" => true},
          %{"id" => "1", "type" => "webhook", "enabled" => true}
        ]
      }

      workflow2 = %{
        "triggers" => [
          %{"id" => "1", "type" => "webhook", "enabled" => true},
          %{"id" => "2", "type" => "webhook", "enabled" => true}
        ]
      }

      assert ParamsComparator.equivalent?(workflow1, workflow2, mode: :exact)
    end

    test "get_field with nil data returns nil" do
      workflow = %{
        "jobs" => [nil, %{"id" => "job1", "name" => "Job"}],
        "edges" => []
      }

      assert ParamsComparator.equivalent?(workflow, workflow)
    end
  end

  defp build_complex_workflow do
    %{
      "id" => "complex-workflow",
      "name" => "Complex Workflow",
      "project_id" => "project-123",
      "lock_version" => 1,
      "deleted_at" => nil,
      "inserted_at" => "2024-01-01T00:00:00Z",
      "updated_at" => "2024-01-01T00:00:00Z",
      "concurrency" => 10,
      "enable_job_logs" => true,
      "jobs" => [
        %{
          "id" => "job-1",
          "name" => "First Job",
          "body" => "console.log('hello');",
          "adaptor" => "@openfn/language-common",
          "project_credential_id" => "cred-1",
          "workflow_id" => "complex-workflow",
          "inserted_at" => "2024-01-01T00:00:00Z",
          "updated_at" => "2024-01-01T00:00:00Z"
        },
        %{
          "id" => "job-2",
          "name" => "Second Job",
          "body" => "console.log('world');",
          "adaptor" => "@openfn/language-http",
          "project_credential_id" => "cred-2",
          "workflow_id" => "complex-workflow",
          "inserted_at" => "2024-01-01T00:00:00Z",
          "updated_at" => "2024-01-01T00:00:00Z"
        }
      ],
      "triggers" => [
        %{
          "id" => "trigger-1",
          "type" => "webhook",
          "enabled" => true,
          "has_auth_method" => true,
          "workflow_id" => "complex-workflow",
          "inserted_at" => "2024-01-01T00:00:00Z",
          "updated_at" => "2024-01-01T00:00:00Z"
        }
      ],
      "edges" => [
        %{
          "id" => "edge-1",
          "source_trigger_id" => "trigger-1",
          "target_job_id" => "job-1",
          "enabled" => true,
          "condition_type" => "always",
          "workflow_id" => "complex-workflow",
          "inserted_at" => "2024-01-01T00:00:00Z",
          "updated_at" => "2024-01-01T00:00:00Z"
        },
        %{
          "id" => "edge-2",
          "source_job_id" => "job-1",
          "target_job_id" => "job-2",
          "enabled" => true,
          "condition_type" => "on_success",
          "condition_expression" => nil,
          "condition_label" => "Success",
          "workflow_id" => "complex-workflow",
          "inserted_at" => "2024-01-01T00:00:00Z",
          "updated_at" => "2024-01-01T00:00:00Z"
        }
      ]
    }
  end
end
