defmodule LightningWeb.ErrorFormatterTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  alias LightningWeb.ErrorFormatter

  test "an unconfigured environment names the administrator, without a link" do
    message = ErrorFormatter.format(:environment_not_configured, %{})

    assert message =~ "administrator"
    # The project environment field is read-only, so sending someone to the
    # settings screen asks them to do something it refuses.
    refute message =~ "/settings"
  end

  test "a project that cannot be found says so" do
    assert ErrorFormatter.format(:project_not_found, %{}) =~ "project"
  end

  test "a mismatch points at the credential rather than the environment" do
    project = insert(:project)
    credential = insert(:credential, name: "DHIS2 prod")

    message =
      ErrorFormatter.format({:environment_mismatch, credential}, %{
        project: project,
        project_env: "prod"
      })

    assert message =~ "DHIS2 prod"
    assert message =~ "credentials"
  end
end
