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

    test "validates content length minimum" do
      user = insert(:user)

      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: "",
          role: :user,
          user: user
        })

      assert "can't be blank" in errors_on(changeset).content
    end

    test "validates content length maximum" do
      user = insert(:user)
      long_content = String.duplicate("a", 10_001)

      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: long_content,
          role: :user,
          user: user
        })

      assert "should be at most 10000 character(s)" in errors_on(changeset).content
    end

    test "accepts content at maximum allowed length" do
      user = insert(:user)
      max_content = String.duplicate("a", 10_000)

      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: max_content,
          role: :user,
          user: user
        })

      assert changeset.valid?
    end

    test "sets pending status by default for user messages" do
      user = insert(:user)

      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: "Test message",
          role: :user,
          user: user
        })

      assert Ecto.Changeset.fetch_field!(changeset, :status) == :pending
    end

    test "sets success status by default for assistant messages" do
      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: "Test message",
          role: :assistant
        })

      assert Ecto.Changeset.fetch_field!(changeset, :status) == :success
    end

    test "preserves explicitly provided status over role defaults" do
      user = insert(:user)

      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: "Test message",
          role: :user,
          user: user,
          status: :success
        })

      assert Ecto.Changeset.fetch_field!(changeset, :status) == :success

      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: "Test message",
          role: :assistant,
          status: :pending
        })

      assert Ecto.Changeset.fetch_field!(changeset, :status) == :pending
    end

    test "accepts code field" do
      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: "Test message",
          role: :assistant,
          code: "defmodule MyWorkflow do\nend"
        })

      assert changeset.valid?

      assert Ecto.Changeset.fetch_field!(changeset, :code) ==
               "defmodule MyWorkflow do\nend"
    end

    test "accepts is_deleted field" do
      user = insert(:user)

      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: "Test message",
          role: :user,
          user: user,
          is_deleted: true
        })

      assert changeset.valid?
      assert Ecto.Changeset.fetch_field!(changeset, :is_deleted) == true
    end

    test "accepts is_public field" do
      user = insert(:user)

      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: "Test message",
          role: :user,
          user: user,
          is_public: false
        })

      assert changeset.valid?
      assert Ecto.Changeset.fetch_field!(changeset, :is_public) == false
    end

    test "accepts chat_session_id field" do
      user = insert(:user)
      chat_session_id = Ecto.UUID.generate()

      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          content: "Test message",
          role: :user,
          user: user,
          chat_session_id: chat_session_id
        })

      assert changeset.valid?

      assert Ecto.Changeset.fetch_field!(changeset, :chat_session_id) ==
               chat_session_id
    end

    test "handles user association with string key" do
      user = insert(:user)

      changeset =
        ChatMessage.changeset(%ChatMessage{}, %{
          "content" => "Test message",
          "role" => "user",
          "user" => user
        })

      assert changeset.valid?
      assert Ecto.Changeset.fetch_field!(changeset, :user).id == user.id
    end

    test "accepts all valid status values" do
      user = insert(:user)

      for status <- [:pending, :success, :error, :cancelled] do
        changeset =
          ChatMessage.changeset(%ChatMessage{}, %{
            content: "Test message",
            role: :user,
            user: user,
            status: status
          })

        assert changeset.valid?, "Status #{status} should be valid"
        assert Ecto.Changeset.fetch_field!(changeset, :status) == status
      end
    end
  end

  describe "status_changeset/2" do
    setup do
      user = insert(:user)
      chat_session = insert(:chat_session)

      message =
        insert(:chat_message,
          role: :user,
          user: user,
          chat_session: chat_session,
          status: :pending
        )

      {:ok, message: message}
    end

    test "updates status to success", %{message: message} do
      changeset = ChatMessage.status_changeset(message, :success)

      assert changeset.valid?
      assert Ecto.Changeset.fetch_change!(changeset, :status) == :success
    end

    test "updates status to error", %{message: message} do
      changeset = ChatMessage.status_changeset(message, :error)

      assert changeset.valid?
      assert Ecto.Changeset.fetch_change!(changeset, :status) == :error
    end

    test "updates status to cancelled", %{message: message} do
      changeset = ChatMessage.status_changeset(message, :cancelled)

      assert changeset.valid?
      assert Ecto.Changeset.fetch_change!(changeset, :status) == :cancelled
    end

    test "updates status to pending", %{message: message} do
      updated_message =
        Ecto.Changeset.change(message, %{status: :success})
        |> Lightning.Repo.update!()

      changeset = ChatMessage.status_changeset(updated_message, :pending)

      assert changeset.valid?
      assert Ecto.Changeset.fetch_change!(changeset, :status) == :pending
    end

    test "only changes status field and nothing else", %{message: message} do
      changeset = ChatMessage.status_changeset(message, :success)

      assert Map.keys(changeset.changes) == [:status]
      assert changeset.changes.status == :success
    end

    test "raises function clause error for invalid status", %{message: message} do
      assert_raise FunctionClauseError, fn ->
        ChatMessage.status_changeset(message, :invalid_status)
      end
    end
  end

  describe "edge cases and integration" do
    test "creates valid user message with all fields" do
      user = insert(:user)
      chat_session_id = Ecto.UUID.generate()

      attrs = %{
        content: "Help me create a workflow",
        code: nil,
        role: :user,
        status: :pending,
        is_deleted: false,
        is_public: true,
        chat_session_id: chat_session_id,
        user: user
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      assert changeset.valid?

      assert Ecto.Changeset.fetch_field!(changeset, :content) ==
               "Help me create a workflow"

      assert Ecto.Changeset.fetch_field!(changeset, :code) == nil
      assert Ecto.Changeset.fetch_field!(changeset, :role) == :user
      assert Ecto.Changeset.fetch_field!(changeset, :status) == :pending
      assert Ecto.Changeset.fetch_field!(changeset, :is_deleted) == false
      assert Ecto.Changeset.fetch_field!(changeset, :is_public) == true

      assert Ecto.Changeset.fetch_field!(changeset, :chat_session_id) ==
               chat_session_id

      assert Ecto.Changeset.fetch_field!(changeset, :user).id == user.id
    end

    test "creates valid assistant message with workflow code" do
      chat_session_id = Ecto.UUID.generate()
      code = "defmodule MyWorkflow do\n  def run, do: :ok\nend"

      attrs = %{
        content: "Here's your workflow...",
        code: code,
        role: :assistant,
        chat_session_id: chat_session_id
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      assert changeset.valid?

      assert Ecto.Changeset.fetch_field!(changeset, :content) ==
               "Here's your workflow..."

      assert Ecto.Changeset.fetch_field!(changeset, :code) == code

      assert Ecto.Changeset.fetch_field!(changeset, :role) == :assistant
      # Default for assistant
      assert Ecto.Changeset.fetch_field!(changeset, :status) == :success
      # No user required
      assert Ecto.Changeset.fetch_field!(changeset, :user) == nil
    end
  end
end
