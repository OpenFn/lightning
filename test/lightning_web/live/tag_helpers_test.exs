defmodule LightningWeb.TagHelpersTest do
  use LightningWeb.ConnCase, async: true

  alias Lightning.Workflows.WorkflowTemplate
  alias LightningWeb.TagHelpers
  alias Phoenix.LiveView.Socket

  describe "handle_action/4" do
    setup do
      socket = %Socket{}
      changeset = Ecto.Changeset.change(%WorkflowTemplate{}, %{tags: []})

      socket =
        Phoenix.Component.assign(socket, :workflow_template_changeset, changeset)

      %{socket: socket}
    end

    test "adds new tags", %{socket: socket} do
      socket =
        TagHelpers.handle_action(
          socket,
          %{
            "action" => "add",
            "value" => "tag1, tag2,tag3"
          },
          :workflow_template_changeset
        )

      changeset = socket.assigns.workflow_template_changeset

      assert Ecto.Changeset.get_field(changeset, :tags) == [
               "tag1",
               "tag2",
               "tag3"
             ]
    end

    test "handles empty strings and whitespace when adding", %{socket: socket} do
      socket =
        TagHelpers.handle_action(
          socket,
          %{
            "action" => "add",
            "value" => "tag1,  , tag2,,  tag3,"
          },
          :workflow_template_changeset
        )

      changeset = socket.assigns.workflow_template_changeset

      assert Ecto.Changeset.get_field(changeset, :tags) == [
               "tag1",
               "tag2",
               "tag3"
             ]
    end

    test "handles non-string input when adding", %{socket: socket} do
      socket =
        TagHelpers.handle_action(
          socket,
          %{
            "action" => "add",
            "value" => nil
          },
          :workflow_template_changeset
        )

      changeset = socket.assigns.workflow_template_changeset
      assert Ecto.Changeset.get_field(changeset, :tags) == []

      socket =
        TagHelpers.handle_action(
          socket,
          %{
            "action" => "add",
            "value" => 123
          },
          :workflow_template_changeset
        )

      changeset = socket.assigns.workflow_template_changeset
      assert Ecto.Changeset.get_field(changeset, :tags) == []
    end

    test "removes a tag", %{socket: socket} do
      # First add some tags
      socket =
        TagHelpers.handle_action(
          socket,
          %{
            "action" => "add",
            "value" => "tag1,tag2,tag3"
          },
          :workflow_template_changeset
        )

      # Then remove one
      socket =
        TagHelpers.handle_action(
          socket,
          %{
            "action" => "remove",
            "value" => "tag2"
          },
          :workflow_template_changeset
        )

      changeset = socket.assigns.workflow_template_changeset
      assert Ecto.Changeset.get_field(changeset, :tags) == ["tag1", "tag3"]
    end

    test "prepares tag for editing", %{socket: socket} do
      # First add some tags
      socket =
        TagHelpers.handle_action(
          socket,
          %{
            "action" => "add",
            "value" => "tag1,tag2,tag3"
          },
          :workflow_template_changeset
        )

      # Then edit one
      socket =
        TagHelpers.handle_action(
          socket,
          %{
            "action" => "edit",
            "value" => "tag2"
          },
          :workflow_template_changeset
        )

      changeset = socket.assigns.workflow_template_changeset
      assert Ecto.Changeset.get_field(changeset, :tags) == ["tag1", "tag3"]
    end

    test "works with custom field name", %{socket: socket} do
      # Use the same WorkflowTemplate but with a different assign name
      changeset = Ecto.Changeset.change(%WorkflowTemplate{}, %{tags: []})
      socket = Phoenix.Component.assign(socket, :test_changeset, changeset)

      socket =
        TagHelpers.handle_action(
          socket,
          %{
            "action" => "add",
            "value" => "tag1,tag2"
          },
          :test_changeset,
          :tags
        )

      changeset = socket.assigns.test_changeset
      assert Ecto.Changeset.get_field(changeset, :tags) == ["tag1", "tag2"]
    end
  end

  describe "process_tag_params/2" do
    test "converts comma-separated string to list of tags" do
      params = %{"tags" => "tag1, tag2,tag3"}
      result = TagHelpers.process_tag_params(params)
      assert result["tags"] == ["tag1", "tag2", "tag3"]
    end

    test "handles empty strings and whitespace" do
      params = %{"tags" => "tag1,  , tag2,,  tag3,"}
      result = TagHelpers.process_tag_params(params)
      assert result["tags"] == ["tag1", "tag2", "tag3"]
    end

    test "returns original params when tags is not a string" do
      params = %{"tags" => ["already", "a", "list"]}
      result = TagHelpers.process_tag_params(params)
      assert result == params

      params = %{"tags" => nil}
      result = TagHelpers.process_tag_params(params)
      assert result == params
    end

    test "processes custom field name" do
      params = %{"custom_tags" => "tag1,tag2"}
      result = TagHelpers.process_tag_params(params, "custom_tags")
      assert result["custom_tags"] == ["tag1", "tag2"]
    end

    test "handles missing field" do
      params = %{}
      result = TagHelpers.process_tag_params(params)
      assert result == params
    end
  end
end
