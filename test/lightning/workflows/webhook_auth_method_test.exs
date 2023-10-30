defmodule Lightning.Workflows.WebhookAuthMethodTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.WebhookAuthMethod

  import Lightning.Factories

  describe "changeset/2" do
    setup do
      project = insert(:project)

      %{
        valid_attrs: %{
          name: "some name",
          auth_type: :basic,
          username: "some username",
          password: "somepassword",
          project_id: project.id
        },
        project: project
      }
    end

    test "generates a valid changeset for basic auth", %{
      valid_attrs: valid_attrs
    } do
      changeset =
        WebhookAuthMethod.changeset(
          %WebhookAuthMethod{},
          Map.put(valid_attrs, :auth_type, :basic)
        )

      assert changeset.valid?
    end

    test "generates a valid changeset for api auth", %{valid_attrs: valid_attrs} do
      changeset =
        WebhookAuthMethod.changeset(
          %WebhookAuthMethod{},
          Map.put(valid_attrs, :auth_type, :api)
        )

      assert changeset.valid?
    end

    test "invalid without required fields", %{valid_attrs: _valid_attrs} do
      changeset = WebhookAuthMethod.changeset(%WebhookAuthMethod{}, %{})
      refute changeset.valid?
    end

    test "validates auth_type", %{valid_attrs: valid_attrs} do
      changeset =
        WebhookAuthMethod.changeset(
          %WebhookAuthMethod{},
          Map.put(valid_attrs, :auth_type, :auth_type)
        )

      assert %{auth_type: ["is invalid"]} == errors_on(changeset)
    end

    test "validates password length", %{valid_attrs: valid_attrs} do
      changeset =
        WebhookAuthMethod.changeset(
          %WebhookAuthMethod{},
          %{valid_attrs | password: "short"}
        )

      assert %{password: ["should be at least 8 character(s)"]} ==
               errors_on(changeset)
    end
  end

  describe "unique_constraints/1" do
    setup do
      project = insert(:project)

      insert(:webhook_auth_method,
        name: "unique_name",
        project: project
      )

      %{
        project: project
      }
    end

    defp assert_unique_constraint_error(changeset, field, error_message) do
      assert {:error, changeset} = changeset |> Repo.insert()
      assert %{field => [error_message]} == errors_on(changeset)
    end

    test "validates unique name", %{
      project: project
    } do
      changeset =
        WebhookAuthMethod.changeset(%WebhookAuthMethod{}, %{
          name: "unique_name",
          auth_type: :api,
          project_id: project.id
        })

      assert_unique_constraint_error(
        changeset,
        :name,
        "must be unique within the project"
      )
    end
  end
end
