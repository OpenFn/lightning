defmodule LightningWeb.AuditLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.CredentialsFixtures
  import Lightning.Factories

  alias Lightning.Repo
  alias LightningWeb.AuditLive
  alias LightningWeb.LiveHelpers

  describe "Index as a regular user" do
    setup :register_and_log_in_user

    test "cannot access the audit trail", %{conn: conn} do
      {:ok, _index_live, html} =
        live(conn, ~p"/settings/audit", on_error: :raise)
        |> follow_redirect(conn, "/projects")

      assert html =~ "Sorry, you don&#39;t have access to that."
    end
  end

  describe "Index as a superuser" do
    setup :register_and_log_in_superuser
    setup :create_project_for_current_user

    test "lists all audit entries", %{conn: conn, user: user} do
      # Generate an audit event on creation.
      credential =
        credential_fixture(user_id: user.id, body: %{"my-secret" => "value"})

      # Add another audit event, but this time for a user that will be deleted
      # before the listing
      user_to_be_deleted = insert(:user)

      {:ok, _audit} =
        Lightning.Credentials.Audit.event(
          "deleted",
          credential.id,
          user_to_be_deleted
        )
        |> Lightning.Credentials.Audit.save()

      Repo.delete!(user_to_be_deleted)

      {:ok, _index_live, html} =
        live(conn, Routes.audit_index_path(conn, :index), on_error: :raise)

      assert html =~ "Audit"
      # Assert that the table works for users that still exist.
      assert html =~ user.first_name
      assert html =~ user.email
      assert html =~ LiveHelpers.display_short_uuid(credential.id)
      assert html =~ "created"
      assert html =~ "No changes"
      refute html =~ "nil"

      # Assert that the table works for users that have been deleted.
      assert html =~ "created"
      assert html =~ "(User deleted)"
      assert html =~ LiveHelpers.display_short_uuid(user_to_be_deleted.id)
    end
  end

  describe ".diff/1" do
    test "correctly lists changes with both before and after (string keys)" do
      assigns = %{
        metadata: %{
          before: %{
            "foo" => "foo_before",
            "bar" => "bar_before"
          },
          after: %{
            "foo" => "foo_after",
            "bar" => "bar_after"
          }
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~
               ~r"<span class=\"font-semibold\">bar</span>&nbsp; bar_before.*?<span class=\"hero-arrow-right.*?</span>.*?bar_after"s

      assert html =~
               ~r"<span class=\"font-semibold\">foo</span>&nbsp; foo_before.*?<span class=\"hero-arrow-right.*?</span>.*?foo_after"s
    end

    test "correctly lists changes with both before and after (atom keys)" do
      assigns = %{
        metadata: %{
          before: %{
            foo: "foo_before",
            bar: "bar_before"
          },
          after: %{
            foo: "foo_after",
            bar: "bar_after"
          }
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~
               ~r"<span class=\"font-semibold\">bar</span>&nbsp; bar_before.*?<span class=\"hero-arrow-right.*?</span>.*?bar_after"s

      assert html =~
               ~r"<span class=\"font-semibold\">foo</span>&nbsp; foo_before.*?<span class=\"hero-arrow-right.*?</span>.*?foo_after"s
    end

    test "correctly lists changes if before is nil (string keys)" do
      assigns = %{
        metadata: %{
          before: nil,
          after: %{"foo" => "foo_after", "bar" => "bar_after"}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~
               ~r"<span class=\"font-semibold\">bar</span>&nbsp;\s*<span class=\"hero-arrow-right.*?</span>\s*bar_after"s

      assert html =~
               ~r"<span class=\"font-semibold\">foo</span>&nbsp;\s*<span class=\"hero-arrow-right.*?</span>\s*foo_after"s
    end

    test "correctly lists changes if before is nil (atom keys)" do
      assigns = %{
        metadata: %{
          before: nil,
          after: %{foo: "foo_after", bar: "bar_after"}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~
               ~r"<span class=\"font-semibold\">bar</span>&nbsp;\s*<span class=\"hero-arrow-right.*?</span>\s*bar_after"s

      assert html =~
               ~r"<span class=\"font-semibold\">foo</span>&nbsp;\s*<span class=\"hero-arrow-right.*?</span>\s*foo_after"s
    end

    test "correctly lists changes if before is empty (string keys)" do
      assigns = %{
        metadata: %{
          before: %{},
          after: %{"foo" => "foo_after", "bar" => "bar_after"}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~
               ~r"<span class=\"font-semibold\">bar</span>&nbsp;\s*<span class=\"hero-arrow-right.*?</span>\s*bar_after"s

      assert html =~
               ~r"<span class=\"font-semibold\">foo</span>&nbsp;\s*<span class=\"hero-arrow-right.*?</span>\s*foo_after"s
    end

    test "correctly lists changes if before is empty (atom keys)" do
      assigns = %{
        metadata: %{
          before: %{},
          after: %{foo: "foo_after", bar: "bar_after"}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~
               ~r"<span class=\"font-semibold\">bar</span>&nbsp;\s*<span class=\"hero-arrow-right.*?</span>\s*bar_after"s

      assert html =~
               ~r"<span class=\"font-semibold\">foo</span>&nbsp;\s*<span class=\"hero-arrow-right.*?</span>\s*foo_after"s
    end

    test "correctly lists changes if after is nil (string keys)" do
      assigns = %{
        metadata: %{
          before: %{"foo" => "foo_before", "bar" => "bar_before"},
          after: nil
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~
               ~r"<span class=\"font-semibold\">bar</span>&nbsp; bar_before.*?<span class=\"hero-arrow-right.*?</span>\s*"s

      assert html =~
               ~r"<span class=\"font-semibold\">foo</span>&nbsp; foo_before.*?<span class=\"hero-arrow-right.*?</span>\s*"s
    end

    test "correctly lists changes if after is nil (atom keys)" do
      assigns = %{
        metadata: %{
          before: %{foo: "foo_before", bar: "bar_before"},
          after: nil
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~
               ~r"<span class=\"font-semibold\">bar</span>&nbsp; bar_before.*?<span class=\"hero-arrow-right.*?</span>\s*"s

      assert html =~
               ~r"<span class=\"font-semibold\">foo</span>&nbsp; foo_before.*?<span class=\"hero-arrow-right.*?</span>\s*"s
    end

    test "correctly lists changes if after is empty (string keys)" do
      assigns = %{
        metadata: %{
          before: %{"foo" => "foo_before", "bar" => "bar_before"},
          after: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~
               ~r"<span class=\"font-semibold\">bar</span>&nbsp; bar_before.*?<span class=\"hero-arrow-right.*?</span>\s*"s

      assert html =~
               ~r"<span class=\"font-semibold\">foo</span>&nbsp; foo_before.*?<span class=\"hero-arrow-right.*?</span>\s*"s
    end

    test "correctly lists changes if after is empty (atom keys)" do
      assigns = %{
        metadata: %{
          before: %{foo: "foo_before", bar: "bar_before"},
          after: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~
               ~r"<span class=\"font-semibold\">bar</span>&nbsp; bar_before.*?<span class=\"hero-arrow-right.*?</span>\s*"s

      assert html =~
               ~r"<span class=\"font-semibold\">foo</span>&nbsp; foo_before.*?<span class=\"hero-arrow-right.*?</span>\s*"s
    end

    test "includes any extra keys in the before (string keys)" do
      assigns = %{
        metadata: %{
          before: %{
            "foo" => "foo_before",
            "bar" => "bar_before",
            "baz" => "baz_before"
          },
          after: %{
            "foo" => "foo_after",
            "bar" => "bar_after"
          }
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~
               ~r"<span class=\"font-semibold\">bar</span>&nbsp; bar_before.*?<span class=\"hero-arrow-right.*?</span>.*?bar_after"s

      assert html =~
               ~r"<span class=\"font-semibold\">foo</span>&nbsp; foo_before.*?<span class=\"hero-arrow-right.*?</span>.*?foo_after"s

      assert html =~
               ~r"<span class=\"font-semibold\">baz</span>&nbsp; baz_before.*?<span class=\"hero-arrow-right.*?</span>\s*"s
    end

    test "includes any extra keys in the before (atom keys)" do
      assigns = %{
        metadata: %{
          before: %{
            foo: "foo_before",
            bar: "bar_before",
            baz: "baz_before"
          },
          after: %{
            foo: "foo_after",
            bar: "bar_after"
          }
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~
               ~r"<span class=\"font-semibold\">bar</span>&nbsp; bar_before.*?<span class=\"hero-arrow-right.*?</span>.*?bar_after"s

      assert html =~
               ~r"<span class=\"font-semibold\">foo</span>&nbsp; foo_before.*?<span class=\"hero-arrow-right.*?</span>.*?foo_after"s

      assert html =~
               ~r"<span class=\"font-semibold\">baz</span>&nbsp; baz_before.*?<span class=\"hero-arrow-right.*?</span>\s*"s
    end

    test "includes any extra keys in the after (string keys)" do
      assigns = %{
        metadata: %{
          before: %{
            "foo" => "foo_before",
            "bar" => "bar_before"
          },
          after: %{
            "foo" => "foo_after",
            "bar" => "bar_after",
            "baz" => "baz_after"
          }
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~
               ~r"<span class=\"font-semibold\">bar</span>&nbsp; bar_before.*?<span class=\"hero-arrow-right.*?</span>.*?bar_after"s

      assert html =~
               ~r"<span class=\"font-semibold\">foo</span>&nbsp; foo_before.*?<span class=\"hero-arrow-right.*?</span>.*?foo_after"s

      assert html =~
               ~r"<span class=\"font-semibold\">baz</span>&nbsp;\s*<span class=\"hero-arrow-right.*?</span>\s*baz_after"s
    end

    test "includes any extra keys in the after (atom keys)" do
      assigns = %{
        metadata: %{
          before: %{
            foo: "foo_before",
            bar: "bar_before"
          },
          after: %{
            foo: "foo_after",
            bar: "bar_after",
            baz: "baz_after"
          }
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~
               ~r"<span class=\"font-semibold\">bar</span>&nbsp; bar_before.*?<span class=\"hero-arrow-right.*?</span>.*?bar_after"s

      assert html =~
               ~r"<span class=\"font-semibold\">foo</span>&nbsp; foo_before.*?<span class=\"hero-arrow-right.*?</span>.*?foo_after"s

      assert html =~
               ~r"<span class=\"font-semibold\">baz</span>&nbsp;\s*<span class=\"hero-arrow-right.*?</span>\s*baz_after"s
    end

    test "list changes in order (string keys)" do
      assigns = %{
        metadata: %{
          before: %{
            "foo" => "foo_before",
            "bar" => "bar_before",
            "baz" => "baz_before"
          },
          after: %{
            "foo" => "foo_after",
            "bar" => "bar_after",
            "baz" => "baz_after"
          }
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~ ~r"bar</span>&nbsp;.+baz</span>&nbsp;.+foo</span>&nbsp;"s
    end

    test "list changes in order (atom keys)" do
      assigns = %{
        metadata: %{
          before: %{foo: "foo_before", bar: "bar_before", baz: "baz_before"},
          after: %{foo: "foo_after", bar: "bar_after", baz: "baz_after"}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~ ~r"bar</span>&nbsp;.+baz</span>&nbsp;.+foo</span>&nbsp;"s
    end

    test "when both before and after are nil, return `No changes`" do
      assigns = %{metadata: %{before: nil, after: nil}}

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~ "No changes"
    end

    test "when both before and after are empty, return `No changes`" do
      assigns = %{metadata: %{before: %{}, after: %{}}}

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~ "No changes"
    end
  end
end
