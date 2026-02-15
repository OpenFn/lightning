defmodule Lightning.VersionControl.VersionControlUsageLimiterTest do
  use ExUnit.Case, async: true

  alias Lightning.Extensions.MockUsageLimiter
  alias Lightning.Extensions.Message
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.VersionControl.VersionControlUsageLimiter

  describe "limit_github_sync/1" do
    test "returns :ok when passed nil" do
      assert VersionControlUsageLimiter.limit_github_sync(nil) == :ok
    end

    test "with a project_id, indicates if request is allowed" do
      project_id = Ecto.UUID.generate()

      action = %Action{type: :github_sync}
      context = %Context{project_id: project_id}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        :ok
      end)

      assert VersionControlUsageLimiter.limit_github_sync(project_id) == :ok
    end

    test "with a project_id, indicates if request is denied" do
      project_id = Ecto.UUID.generate()

      action = %Action{type: :github_sync}
      context = %Context{project_id: project_id}

      message = %Message{text: "You melted the CPU."}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        {:error, :melted, message}
      end)

      assert VersionControlUsageLimiter.limit_github_sync(project_id) ==
               {:error, message}
    end
  end

  describe "limit_api_provisioning/1" do
    test "returns :ok when passed nil" do
      assert VersionControlUsageLimiter.limit_api_provisioning(nil) == :ok
    end

    test "with a project_id, indicates if request is allowed" do
      project_id = Ecto.UUID.generate()

      action = %Action{type: :api_provisioning}
      context = %Context{project_id: project_id}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        :ok
      end)

      assert VersionControlUsageLimiter.limit_api_provisioning(project_id) == :ok
    end

    test "with a project_id, indicates if request is denied" do
      project_id = Ecto.UUID.generate()

      action = %Action{type: :api_provisioning}
      context = %Context{project_id: project_id}

      message = %Message{text: "Provisioning not enabled."}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        {:error, :disabled, message}
      end)

      assert VersionControlUsageLimiter.limit_api_provisioning(project_id) ==
               {:error, message}
    end
  end
end
