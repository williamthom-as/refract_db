defmodule Refract.DB.FromSchemaTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 2]

  alias Refract.Classify.Result
  alias Refract.DB.Fixture
  alias Refract.DB.TestRepo
  alias Refract.DB.TestSchemas.Account
  alias Refract.DB.TestSchemas.Customer
  alias Refract.DB.TestSchemas.Ledger
  alias Refract.Shape
  alias Refract.Validate.Issue

  @moduletag timeout: 10_000

  defp header(%Shape{spec: spec}), do: spec.header
  defp row_rules(%Shape{spec: spec}), do: spec.row.match
  defp validation(%Shape{validation: validation}), do: validation.columns

  describe "columns" do
    test "a column per field under its column name, the field name an alias" do
      shape = Refract.DB.shape(Account)

      assert %Shape{name: "accounts", version: 1} = shape

      assert header(shape).columns == %{
               "account" => ["account"],
               "amount" => ["amount"],
               "opened_on" => ["opened_on"],
               "active" => ["active"],
               "notes" => ["notes"],
               "holder_name" => ["holder_name", "holder"]
             }
    end

    test "generated keys and timestamps are left out, a natural key kept" do
      assert Map.keys(header(Refract.DB.shape(Ledger)).columns) |> Enum.sort() ==
               ["amount", "entry_no", "memo", "posted_on"]

      assert "id" in Map.keys(header(Refract.DB.shape(Ledger, except: [])).columns)
    end

    test "name, version and aliases are options" do
      shape =
        Refract.DB.shape(Ledger,
          name: "ledger_export",
          version: 2,
          aliases: %{entry_no: ["entry number", ~r/^ref/i]}
        )

      assert %Shape{name: "ledger_export", version: 2} = shape

      assert ["entry_no", "entry number", %Regex{}] = header(shape).columns["entry_no"]
    end
  end

  describe "rules" do
    test "each type gives its rule, columns without one have none" do
      rules = validation(Refract.DB.shape(Customer))

      assert rules["score"] == [:number]
      assert rules["joined_at"] == [:datetime]
      assert rules["tier"] == [{:in, ["gold", "silver"]}]
      assert [%Regex{}] = rules["ref"]
      assert [{:boolean, boolean}] = rules["verified"]
      assert boolean.("yes")
      refute boolean.("maybe")
      refute Map.has_key?(rules, "email")

      ledger = validation(Refract.DB.shape(Ledger))
      assert ledger["entry_no"] == [:integer]
      assert ledger["posted_on"] == [:date]
    end

    test "required columns are required in the header, in values and in row matching" do
      shape = Refract.DB.shape(Ledger, required: [:entry_no, :amount, :memo])

      assert Enum.sort(header(shape).required) == ["amount", "entry_no", "memo"]
      assert header(shape).min_matches == 3
      assert validation(shape)["entry_no"] == [:required, :integer]
      assert validation(shape)["memo"] == [:required]
      assert row_rules(shape) == %{"entry_no" => :integer, "amount" => :number}
    end

    test "no required columns, no row rules and one header match" do
      shape = Refract.DB.shape(Ledger)

      assert header(shape).required == []
      assert header(shape).min_matches == 1
      assert row_rules(shape) == %{}
    end

    test "an enum is not a row rule" do
      assert row_rules(Refract.DB.shape(Customer, required: [:tier])) == %{}
    end
  end

  describe "options" do
    test "fields that are not in the schema raise" do
      assert_raise ArgumentError, ~r/required: :nope is not a field/, fn ->
        Refract.DB.shape(Ledger, required: [:nope])
      end

      assert_raise ArgumentError, ~r/aliases: :nope is not a field/, fn ->
        Refract.DB.shape(Ledger, aliases: %{nope: ["x"]})
      end

      assert_raise ArgumentError, ~r/except: :nope is not a field/, fn ->
        Refract.DB.shape(Ledger, except: [:nope])
      end
    end

    test "option shapes are checked" do
      assert_raise ArgumentError, ~r/required must be a list/, fn ->
        Refract.DB.shape(Ledger, required: :entry_no)
      end

      assert_raise ArgumentError, ~r/aliases must be a map/, fn ->
        Refract.DB.shape(Ledger, aliases: [entry_no: "x"])
      end

      assert_raise ArgumentError, ~r/aliases for entry_no must be a list/, fn ->
        Refract.DB.shape(Ledger, aliases: %{entry_no: "x"})
      end

      assert_raise ArgumentError, fn -> Refract.DB.shape(Ledger, columns: []) end
    end

    test "not a schema raises" do
      assert_raise ArgumentError, ~r/schema must be an ecto schema module/, fn ->
        Refract.DB.shape(Refract.DB)
      end
    end
  end

  describe "with refract" do
    setup do
      %{
        shape:
          Refract.DB.shape(Ledger,
            required: [:entry_no, :amount],
            aliases: %{entry_no: ["entry no"], posted_on: ["posted on"]}
          )
      }
    end

    test "a file classifies and validates against the schema shape", %{shape: shape} do
      csv = """
      Entry No,Amount,Posted On,Memo
      1,12.50,2024-01-31,rent
      2,twelve,2024-02-01,
      3,4.00,someday,
      """

      assert {:ok, %Result{verdict: :match}} = Refract.CSV.classify({:string, csv}, [shape])

      assert {:ok, %Refract.Validate.Result{issues: issues}} =
               Refract.CSV.validate({:string, csv}, shape)

      assert [
               %Issue{line: 3, column: "amount", rule: :number},
               %Issue{line: 4, column: "posted_on", rule: :date}
             ] = issues
    end

    test "the table matches the shape of its own schema", %{shape: shape} do
      table = Fixture.ledger!()
      rows = [%{"entry_no" => "1", "amount" => "1"}, %{"entry_no" => "2", "amount" => "2"}]
      {:ok, 2} = Refract.DB.insert(rows, TestRepo, {table, Ledger})

      assert {:ok, %Result{verdict: :match, drift: drift}} =
               Refract.DB.classify(Refract.DB.source(TestRepo, {table, Ledger}), [shape])

      assert drift.missing == []
      assert Enum.map(drift.extra, &elem(&1, 1)) == ["id", "inserted_at", "updated_at"]
    end

    test "suggest maps an unknown file onto the schema shape", %{shape: shape} do
      csv = "EntryNo,Total Amount,Posted-On\n1,2.00,2024-01-31\n"

      assert {:ok, report} = Refract.CSV.suggest({:string, csv}, shape)

      assert %{cell: "EntryNo", via: :normalised} = report.columns["entry_no"]
      assert %{cell: "Total Amount", via: :tokens} = report.columns["amount"]
      assert %{cell: "Posted-On", via: :normalised} = report.columns["posted_on"]
    end

    test "enum, uuid and boolean values read back and validate" do
      table =
        Fixture.customers!([
          %{tier: :gold, ref: Ecto.UUID.generate(), verified: true},
          %{tier: :silver, ref: Ecto.UUID.generate(), verified: false}
        ])

      source = Refract.DB.source(TestRepo, from(c in {table, Customer}, select: c))

      assert {:ok, rows} = Refract.DB.stream(source)

      assert [%{"tier" => "gold", "verified" => true}, %{"tier" => "silver"}] =
               Enum.sort_by(rows, & &1["tier"])

      assert {:ok, %Refract.Validate.Result{valid: true}} =
               Refract.DB.validate(source, Refract.DB.shape(Customer))
    end
  end
end
