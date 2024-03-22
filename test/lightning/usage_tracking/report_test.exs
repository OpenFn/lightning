defmodule Lightning.UsageTracking.ReportTest do
  use Lightning.DataCase

  alias Ecto.Changeset
  alias Lightning.Repo
  alias Lightning.UsageTracking.Report

  describe ".changeset/2" do
    setup do
      %{
        data: %{"foo" => "bar"},
        date: ~D[2024-02-05],
        submitted_at: DateTime.add(DateTime.utc_now(), -10, :second)
      }
    end

    test "returns a valid changeset if all parameters are provided", %{
      data: data,
      date: date,
      submitted_at: submitted_at
    } do
      params = %{
        data: data,
        report_date: date,
        submitted: true,
        submitted_at: submitted_at
      }

      changes = Report.changeset(%Report{}, params)

      assert %Changeset{
               valid?: true,
               changes: %{
                 data: ^data,
                 report_date: ^date,
                 submitted: true,
                 submitted_at: ^submitted_at
               }
             } = changes
    end

    test "changeset is invalid if data is not provided", %{
      date: date,
      submitted_at: submitted_at
    } do
      params = %{
        report_date: date,
        submitted: true,
        submitted_at: submitted_at
      }

      %{valid?: false, errors: errors} = Report.changeset(%Report{}, params)

      assert [data: {"can't be blank", [validation: :required]}] = errors
    end

    test "changeset is invalid if the report date is not provided", %{
      data: data,
      submitted_at: submitted_at
    } do
      params = %{
        data: data,
        submitted: true,
        submitted_at: submitted_at
      }

      %{valid?: false, errors: errors} = Report.changeset(%Report{}, params)

      assert [report_date: {"can't be blank", [validation: :required]}] = errors
    end

    test "changeset is invalid if submitted is not provided", %{
      data: data,
      date: date,
      submitted_at: submitted_at
    } do
      params = %{
        data: data,
        report_date: date,
        submitted_at: submitted_at
      }

      %{valid?: false, errors: errors} = Report.changeset(%Report{}, params)

      assert [submitted: {"can't be blank", [validation: :required]}] = errors
    end

    test "changeset is valid if submitted_at is not provided", %{
      data: data,
      date: date
    } do
      params = %{
        data: data,
        report_date: date,
        submitted: true
      }

      %{valid?: true} = Report.changeset(%Report{}, params)
    end

    test "persistence fails i report already exists with date", %{
      data: data,
      date: date,
      submitted_at: submitted_at
    } do
      insert(:usage_tracking_report, report_date: date)

      params = %{
        data: data,
        report_date: date,
        submitted: true,
        submitted_at: submitted_at
      }

      result =
        %Report{}
        |> Report.changeset(params)
        |> Repo.insert()

      assert {:error, %{valid?: false, errors: errors}} = result

      assert [
               report_date: {
                 "has already been taken",
                 [
                   {:constraint, :unique},
                   {:constraint_name, "usage_tracking_reports_report_date_index"}
                 ]
               }
             ] = errors
    end
  end
end
