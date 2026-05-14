defmodule Lightning.Channels.PersistencePolicyTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Channels.PersistencePolicy

  describe "persist_observations?/1" do
    test "returns true when the project's retention_policy is :retain_all" do
      project = insert(:project, retention_policy: :retain_all)

      assert PersistencePolicy.persist_observations?(project.id) == true
    end

    test "returns false when the project's retention_policy is :erase_all" do
      project = insert(:project, retention_policy: :erase_all)

      assert PersistencePolicy.persist_observations?(project.id) == false
    end
  end

  describe "wipe_request_attrs/2" do
    test "is a no-op when persist_observations: true" do
      attrs = %{
        channel_id: "abc",
        client_identity: "127.0.0.1",
        state: :pending
      }

      assert PersistencePolicy.wipe_request_attrs(attrs,
               persist_observations: true
             ) ==
               attrs
    end

    test "drops client_identity and sets is_wiped: true when persist_observations: false" do
      attrs = %{
        channel_id: "abc",
        client_identity: "127.0.0.1",
        state: :pending,
        started_at: ~U[2026-01-01 00:00:00Z]
      }

      result =
        PersistencePolicy.wipe_request_attrs(attrs, persist_observations: false)

      refute Map.has_key?(result, :client_identity)

      assert %{
               channel_id: "abc",
               state: :pending,
               started_at: ~U[2026-01-01 00:00:00Z],
               is_wiped: true
             } = result
    end
  end

  describe "wipe_event_attrs/2" do
    test "is a no-op when persist_observations: true; leaves PII fields untouched" do
      attrs = %{
        type: :destination_response,
        request_method: "POST",
        request_path: "/api/data",
        request_query_string: "page=1",
        request_headers: [["content-type", "application/json"]],
        request_body_preview: "{\"hello\":\"world\"}",
        request_body_hash: "abc123",
        response_headers: [["content-type", "text/plain"]],
        response_body_preview: "ok",
        response_body_hash: "def456",
        response_status: 200,
        latency_us: 12_345
      }

      assert PersistencePolicy.wipe_event_attrs(attrs,
               persist_observations: true
             ) ==
               attrs
    end

    test "drops the eight PII fields when persist_observations: false" do
      attrs = %{
        type: :destination_response,
        request_method: "POST",
        request_path: "/api/data",
        request_query_string: "page=1",
        request_headers: [["content-type", "application/json"]],
        request_body_preview: "{\"hello\":\"world\"}",
        request_body_hash: "abc123",
        response_headers: [["content-type", "text/plain"]],
        response_body_preview: "ok",
        response_body_hash: "def456",
        response_status: 200,
        latency_us: 12_345,
        request_body_size: 17,
        response_body_size: 2,
        error_message: nil
      }

      result =
        PersistencePolicy.wipe_event_attrs(attrs, persist_observations: false)

      # The eight PII fields are dropped from the attrs map.
      for field <- [
            :request_path,
            :request_query_string,
            :request_headers,
            :request_body_preview,
            :request_body_hash,
            :response_headers,
            :response_body_preview,
            :response_body_hash
          ] do
        refute Map.has_key?(result, field),
               "expected #{field} to be dropped, but it was present in #{inspect(result)}"
      end

      # Status / timing / size / category fields are preserved.
      assert %{
               type: :destination_response,
               request_method: "POST",
               response_status: 200,
               latency_us: 12_345,
               request_body_size: 17,
               response_body_size: 2,
               error_message: nil
             } = result
    end
  end
end
