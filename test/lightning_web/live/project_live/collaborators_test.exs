defmodule LightningWeb.ProjectLive.CollaboratorsTest do
  use Lightning.DataCase, async: true

  alias LightningWeb.ProjectLive.Collaborators
  alias LightningWeb.ProjectLive.InvitedCollaborators

  describe "Collaborators.changeset/2 email validation" do
    test "accepts standard email addresses" do
      valid_emails = [
        "user@example.com",
        "user@example.org",
        "user@example.io",
        "user@subdomain.example.com"
      ]

      for email <- valid_emails do
        changeset =
          Collaborators.changeset(%Collaborators{}, %{
            "collaborators" => %{
              "0" => %{"email" => email, "role" => "editor"}
            }
          })

        assert changeset.valid?,
               "Expected #{email} to be valid, but got errors: #{inspect(changeset.errors)}"
      end
    end

    test "accepts emails with longer TLDs like .foundation, .technology" do
      valid_emails = [
        "taylor@openfn.foundation",
        "user@example.technology",
        "contact@company.international",
        "info@org.photography",
        "admin@test.engineering"
      ]

      for email <- valid_emails do
        changeset =
          Collaborators.changeset(%Collaborators{}, %{
            "collaborators" => %{
              "0" => %{"email" => email, "role" => "editor"}
            }
          })

        assert changeset.valid?,
               "Expected #{email} to be valid, but got errors: #{inspect(changeset.errors)}"
      end
    end

    test "accepts emails with hyphens and dots in local part" do
      valid_emails = [
        "first.last@example.com",
        "user-name@example.com",
        "user.name-test@example.org"
      ]

      for email <- valid_emails do
        changeset =
          Collaborators.changeset(%Collaborators{}, %{
            "collaborators" => %{
              "0" => %{"email" => email, "role" => "editor"}
            }
          })

        assert changeset.valid?,
               "Expected #{email} to be valid, but got errors: #{inspect(changeset.errors)}"
      end
    end

    test "rejects invalid email formats" do
      invalid_emails = [
        "not-an-email",
        "missing@tld",
        "@nodomain.com",
        "spaces in@email.com"
      ]

      for email <- invalid_emails do
        changeset =
          Collaborators.changeset(%Collaborators{}, %{
            "collaborators" => %{
              "0" => %{"email" => email, "role" => "editor"}
            }
          })

        refute changeset.valid?,
               "Expected #{email} to be invalid, but it was accepted"
      end
    end
  end

  describe "InvitedCollaborators.changeset/2 email validation" do
    test "accepts emails with longer TLDs like .foundation, .technology" do
      valid_emails = [
        "taylor@openfn.foundation",
        "user@example.technology",
        "contact@company.international"
      ]

      for email <- valid_emails do
        changeset =
          InvitedCollaborators.changeset(%InvitedCollaborators{}, %{
            "invited_collaborators" => %{
              "0" => %{
                "first_name" => "Test",
                "last_name" => "User",
                "email" => email,
                "role" => "editor"
              }
            }
          })

        assert changeset.valid?,
               "Expected #{email} to be valid, but got errors: #{inspect(changeset.errors)}"
      end
    end

    test "rejects invalid email formats" do
      invalid_emails = [
        "not-an-email",
        "missing@tld"
      ]

      for email <- invalid_emails do
        changeset =
          InvitedCollaborators.changeset(%InvitedCollaborators{}, %{
            "invited_collaborators" => %{
              "0" => %{
                "first_name" => "Test",
                "last_name" => "User",
                "email" => email,
                "role" => "editor"
              }
            }
          })

        refute changeset.valid?,
               "Expected #{email} to be invalid, but it was accepted"
      end
    end
  end
end
