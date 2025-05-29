defmodule Lightning.AiAssistant.ChatMessageTest do
  use Lightning.DataCase, async: true

  alias Lightning.AiAssistant.ChatMessage

  describe "changeset/2" do
    test "validates required fields" do
      changeset = ChatMessage.changeset(%ChatMessage{}, %{})
      assert "can't be blank" in errors_on(changeset).content
      assert "can't be blank" in errors_on(changeset).role
    end

    test "validates user association for user role messages" do
      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: "Test message",
          role: :user
        })

      assert "is required" in errors_on(changeset).user
    end

    test "does not require user for assistant role messages" do
      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: "Test message",
          role: :assistant
        })

      assert changeset.valid?
    end

    test "validates role enum values" do
      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: "Test message",
          role: :invalid_role
        })

      assert "is invalid" in errors_on(changeset).role
    end

    test "validates status enum values" do
      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: "Test message",
          role: :user,
          status: :invalid_status
        })

      assert "is invalid" in errors_on(changeset).status
    end

    test "sets default values" do
      user = insert(:user)

      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: "Test message",
          role: :user,
          user: user
        })

      assert Ecto.Changeset.fetch_field!(changeset, :status) == :pending
      refute Ecto.Changeset.fetch_field!(changeset, :is_deleted)
      assert Ecto.Changeset.fetch_field!(changeset, :is_public)
    end

    test "casts and validates user association" do
      user = insert(:user)

      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: "Test message",
          role: :user,
          user: user
        })

      assert changeset.valid?
      assert Ecto.Changeset.fetch_field!(changeset, :user).id == user.id
    end

    test "handles string role values" do
      user = insert(:user)

      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: "Test message",
          role: "user",
          user: user
        })

      assert changeset.valid?
      assert Ecto.Changeset.fetch_field!(changeset, :role) == :user
    end

    test "handles string status values" do
      user = insert(:user)

      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: "Test message",
          role: :user,
          user: user,
          status: "success"
        })

      assert changeset.valid?
      assert Ecto.Changeset.fetch_field!(changeset, :status) == :success
    end
  end
end
