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
        credential_fixture(user_id: user.id, schema: "raw")
        |> with_body(%{name: "main", body: %{"my-secret" => "value"}})

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

      # Assert that the table works for users that have been deleted.
      assert html =~ "deleted"
      assert html =~ "(User deleted)"
      assert html =~ LiveHelpers.display_short_uuid(user_to_be_deleted.id)
    end
  end

  describe ".diff/1" do
    test "correctly lists changes with both before and after (string keys)" do
      assigns = %{
        audit: %{
          changes: %{
            before: %{
              "foo" => "foo_before",
              "bar" => "bar_before"
            },
            after: %{
              "foo" => "foo_after",
              "bar" => "bar_after"
            }
          },
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      # Should show field name, old value (strikethrough), arrow, and new value
      assert html =~ "font-semibold\">bar</span>"
      assert html =~ "line-through"
      assert html =~ "bar_before"
      assert html =~ "hero-arrow-right"
      assert html =~ "bar_after"

      assert html =~ "font-semibold\">foo</span>"
      assert html =~ "foo_before"
      assert html =~ "foo_after"
    end

    test "correctly lists changes with both before and after (atom keys)" do
      assigns = %{
        audit: %{
          changes: %{
            before: %{
              foo: "foo_before",
              bar: "bar_before"
            },
            after: %{
              foo: "foo_after",
              bar: "bar_after"
            }
          },
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      # Should show field name, old value (strikethrough), arrow, and new value
      assert html =~ "font-semibold\">bar</span>"
      assert html =~ "line-through"
      assert html =~ "bar_before"
      assert html =~ "hero-arrow-right"
      assert html =~ "bar_after"

      assert html =~ "font-semibold\">foo</span>"
      assert html =~ "foo_before"
      assert html =~ "foo_after"
    end

    test "correctly lists changes if before is nil (string keys)" do
      assigns = %{
        audit: %{
          changes: %{
            before: nil,
            after: %{"foo" => "foo_after", "bar" => "bar_after"}
          },
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      # When before is nil, should NOT show arrow (because old value is nil)
      assert html =~ "font-semibold\">bar</span>"
      assert html =~ "bar_after"
      refute html =~ "hero-arrow-right"

      assert html =~ "font-semibold\">foo</span>"
      assert html =~ "foo_after"
    end

    test "correctly lists changes if before is nil (atom keys)" do
      assigns = %{
        audit: %{
          changes: %{
            before: nil,
            after: %{foo: "foo_after", bar: "bar_after"}
          },
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      # When before is nil, should NOT show arrow (because old value is nil)
      assert html =~ "font-semibold\">bar</span>"
      assert html =~ "bar_after"
      refute html =~ "hero-arrow-right"

      assert html =~ "font-semibold\">foo</span>"
      assert html =~ "foo_after"
    end

    test "correctly lists changes if before is empty (string keys)" do
      assigns = %{
        audit: %{
          changes: %{
            before: %{},
            after: %{"foo" => "foo_after", "bar" => "bar_after"}
          },
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      # When before is empty map, should NOT show arrow (because old values are nil)
      assert html =~ "font-semibold\">bar</span>"
      assert html =~ "bar_after"
      refute html =~ "hero-arrow-right"

      assert html =~ "font-semibold\">foo</span>"
      assert html =~ "foo_after"
    end

    test "correctly lists changes if before is empty (atom keys)" do
      assigns = %{
        audit: %{
          changes: %{
            before: %{},
            after: %{foo: "foo_after", bar: "bar_after"}
          },
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      # When before is empty map, should NOT show arrow (because old values are nil)
      assert html =~ "font-semibold\">bar</span>"
      assert html =~ "bar_after"
      refute html =~ "hero-arrow-right"

      assert html =~ "font-semibold\">foo</span>"
      assert html =~ "foo_after"
    end

    test "correctly lists changes if after is nil (string keys)" do
      assigns = %{
        audit: %{
          changes: %{
            before: %{"foo" => "foo_before", "bar" => "bar_before"},
            after: nil
          },
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      # Should show old values with arrow, but new values will be empty string
      assert html =~ "font-semibold\">bar</span>"
      assert html =~ "bar_before"
      assert html =~ "hero-arrow-right"

      assert html =~ "font-semibold\">foo</span>"
      assert html =~ "foo_before"
    end

    test "correctly lists changes if after is nil (atom keys)" do
      assigns = %{
        audit: %{
          changes: %{
            before: %{foo: "foo_before", bar: "bar_before"},
            after: nil
          },
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      # Should show old values with arrow, but new values will be empty string
      assert html =~ "font-semibold\">bar</span>"
      assert html =~ "bar_before"
      assert html =~ "hero-arrow-right"

      assert html =~ "font-semibold\">foo</span>"
      assert html =~ "foo_before"
    end

    test "correctly lists changes if after is empty (string keys)" do
      assigns = %{
        audit: %{
          changes: %{
            before: %{"foo" => "foo_before", "bar" => "bar_before"},
            after: %{}
          },
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      # Should show old values with arrow, but new values will be empty string
      assert html =~ "font-semibold\">bar</span>"
      assert html =~ "bar_before"
      assert html =~ "hero-arrow-right"

      assert html =~ "font-semibold\">foo</span>"
      assert html =~ "foo_before"
    end

    test "correctly lists changes if after is empty (atom keys)" do
      assigns = %{
        audit: %{
          changes: %{
            before: %{foo: "foo_before", bar: "bar_before"},
            after: %{}
          },
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      # Should show old values with arrow, but new values will be empty string
      assert html =~ "font-semibold\">bar</span>"
      assert html =~ "bar_before"
      assert html =~ "hero-arrow-right"

      assert html =~ "font-semibold\">foo</span>"
      assert html =~ "foo_before"
    end

    test "includes any extra keys in the before (string keys)" do
      assigns = %{
        audit: %{
          changes: %{
            before: %{
              "foo" => "foo_before",
              "bar" => "bar_before",
              "baz" => "baz_before"
            },
            after: %{
              "foo" => "foo_after",
              "bar" => "bar_after"
            }
          },
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      # foo and bar should have arrows (both have old and new)
      assert html =~ "font-semibold\">bar</span>"
      assert html =~ "bar_before"
      assert html =~ "bar_after"

      assert html =~ "font-semibold\">foo</span>"
      assert html =~ "foo_before"
      assert html =~ "foo_after"

      # baz should have arrow (has old value, new is nil -> empty string)
      assert html =~ "font-semibold\">baz</span>"
      assert html =~ "baz_before"
      assert html =~ "hero-arrow-right"
    end

    test "includes any extra keys in the before (atom keys)" do
      assigns = %{
        audit: %{
          changes: %{
            before: %{
              foo: "foo_before",
              bar: "bar_before",
              baz: "baz_before"
            },
            after: %{
              foo: "foo_after",
              bar: "bar_after"
            }
          },
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      # foo and bar should have arrows (both have old and new)
      assert html =~ "font-semibold\">bar</span>"
      assert html =~ "bar_before"
      assert html =~ "bar_after"

      assert html =~ "font-semibold\">foo</span>"
      assert html =~ "foo_before"
      assert html =~ "foo_after"

      # baz should have arrow (has old value, new is nil -> empty string)
      assert html =~ "font-semibold\">baz</span>"
      assert html =~ "baz_before"
      assert html =~ "hero-arrow-right"
    end

    test "includes any extra keys in the after (string keys)" do
      assigns = %{
        audit: %{
          changes: %{
            before: %{
              "foo" => "foo_before",
              "bar" => "bar_before"
            },
            after: %{
              "foo" => "foo_after",
              "bar" => "bar_after",
              "baz" => "baz_after"
            }
          },
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      # foo and bar should have arrows (both have old and new)
      assert html =~ "font-semibold\">bar</span>"
      assert html =~ "bar_before"
      assert html =~ "bar_after"

      assert html =~ "font-semibold\">foo</span>"
      assert html =~ "foo_before"
      assert html =~ "foo_after"

      # baz should NOT have arrow (old is nil, only new value exists)
      assert html =~ "font-semibold\">baz</span>"
      assert html =~ "baz_after"
      # Count arrows - should only be 2 (for foo and bar)
      arrow_count =
        html |> String.split("hero-arrow-right") |> length() |> Kernel.-(1)

      assert arrow_count == 2
    end

    test "includes any extra keys in the after (atom keys)" do
      assigns = %{
        audit: %{
          changes: %{
            before: %{
              foo: "foo_before",
              bar: "bar_before"
            },
            after: %{
              foo: "foo_after",
              bar: "bar_after",
              baz: "baz_after"
            }
          },
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      # foo and bar should have arrows (both have old and new)
      assert html =~ "font-semibold\">bar</span>"
      assert html =~ "bar_before"
      assert html =~ "bar_after"

      assert html =~ "font-semibold\">foo</span>"
      assert html =~ "foo_before"
      assert html =~ "foo_after"

      # baz should NOT have arrow (old is nil, only new value exists)
      assert html =~ "font-semibold\">baz</span>"
      assert html =~ "baz_after"
      # Count arrows - should only be 2 (for foo and bar)
      arrow_count =
        html |> String.split("hero-arrow-right") |> length() |> Kernel.-(1)

      assert arrow_count == 2
    end

    test "list changes in order (string keys)" do
      assigns = %{
        audit: %{
          changes: %{
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
          },
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      # Fields should appear in alphabetical order: bar, baz, foo
      assert html =~ ~r"bar</span>&nbsp;.+baz</span>&nbsp;.+foo</span>&nbsp;"s
    end

    test "list changes in order (atom keys)" do
      assigns = %{
        audit: %{
          changes: %{
            before: %{foo: "foo_before", bar: "bar_before", baz: "baz_before"},
            after: %{foo: "foo_after", bar: "bar_after", baz: "baz_after"}
          },
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      # Fields should appear in alphabetical order: bar, baz, foo
      assert html =~ ~r"bar</span>&nbsp;.+baz</span>&nbsp;.+foo</span>&nbsp;"s
    end

    test "when both before and after are nil, return `No changes`" do
      assigns = %{
        audit: %{
          changes: %{before: nil, after: nil},
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~ "No changes"
    end

    test "when both before and after are empty, return `No changes`" do
      assigns = %{
        audit: %{
          changes: %{before: %{}, after: %{}},
          metadata: %{}
        }
      }

      html = render_component(&AuditLive.Index.diff/1, assigns)

      assert html =~ "No changes"
    end
  end
end
