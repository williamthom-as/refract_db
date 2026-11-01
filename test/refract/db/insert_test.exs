defmodule Refract.DB.InsertTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 2]

  alias Refract.DB.Fixture
  alias Refract.DB.InsertError
  alias Refract.DB.TestRepo
  alias Refract.DB.TestSchemas.Account
  alias Refract.DB.TestSchemas.Ledger
  alias Refract.Shape
  alias Refract.Table

  @moduletag timeout: 10_000

  defp ledger_rows(table),
    do: TestRepo.all(from(l in {table, Ledger}, order_by: l.entry_no))

  defp entry(entry_no, amount),
    do: %{"entry_no" => "#{entry_no}", "amount" => amount, "posted_on" => "2024-01-31"}

  describe "insert" do
    test "text values are cast to the field types" do
      table = Fixture.ledger!()
      rows = [entry(1, "12.50"), entry(2, "3")]

      assert {:ok, 2} = Refract.DB.insert(rows, TestRepo, {table, Ledger})

      assert [
               %Ledger{entry_no: 1, amount: first, posted_on: ~D[2024-01-31]},
               %Ledger{entry_no: 2, amount: second}
             ] = ledger_rows(table)

      assert Decimal.equal?(first, "12.5")
      assert Decimal.equal?(second, "3")
    end

    test "native values go in as they are" do
      table = Fixture.ledger!()
      row = %{"entry_no" => 1, "amount" => Decimal.new("4.25"), "posted_on" => ~D[2024-02-29]}

      assert {:ok, 1} = Refract.DB.insert([row], TestRepo, {table, Ledger})
      assert [%Ledger{entry_no: 1, posted_on: ~D[2024-02-29]}] = ledger_rows(table)
    end

    test "a key is a field name or its column name" do
      table = Fixture.accounts!([])
      rows = [%{"id" => "1", "holder" => "Ada"}, %{"id" => "2", "holder_name" => "Grace"}]

      assert {:ok, 2} = Refract.DB.insert(rows, TestRepo, {table, Account})

      assert ["Ada", "Grace"] =
               TestRepo.all(from(a in {table, Account}, order_by: a.id, select: a.holder))
    end

    test "an empty string is nil" do
      table = Fixture.ledger!()

      assert {:ok, 1} =
               Refract.DB.insert([%{"entry_no" => "1", "memo" => ""}], TestRepo, {table, Ledger})

      assert [%Ledger{memo: nil}] = ledger_rows(table)
    end

    test "timestamps are filled, a given one is kept" do
      table = Fixture.ledger!()

      rows = [
        %{"entry_no" => "1"},
        %{"entry_no" => "2", "inserted_at" => "2020-01-01T00:00:00"},
        %{"entry_no" => "3", "inserted_at" => nil}
      ]

      assert {:ok, 3} = Refract.DB.insert(rows, TestRepo, {table, Ledger})

      assert [first, second, third] = ledger_rows(table)
      assert %NaiveDateTime{} = first.inserted_at
      assert first.updated_at == first.inserted_at
      assert second.inserted_at == ~N[2020-01-01 00:00:00]
      assert third.inserted_at == first.inserted_at
    end

    test "an empty stream inserts nothing" do
      table = Fixture.ledger!()

      assert {:ok, 0} = Refract.DB.insert([], TestRepo, {table, Ledger})
    end

    test "rows are read lazily" do
      table = Fixture.ledger!()
      rows = Stream.map(1..3, &entry(&1, "1"))

      assert {:ok, 3} = Refract.DB.insert(rows, TestRepo, {table, Ledger}, chunk: 2)
    end
  end

  describe "errors" do
    test "an unknown column stops it, everything rolled back" do
      table = Fixture.ledger!()
      rows = [entry(1, "1"), entry(2, "2"), Map.put(entry(3, "3"), "nope", "x")]

      assert {:error, {:unknown_column, %{line: 3, column: "nope", inserted: 0}}} =
               Refract.DB.insert(rows, TestRepo, {table, Ledger}, chunk: 1)

      assert ledger_rows(table) == []
    end

    test "a value that does not cast stops it, without the value" do
      table = Fixture.ledger!()
      rows = [entry(1, "1"), entry(2, "twelve")]

      assert {:error, {:cast_failed, detail}} =
               Refract.DB.insert(rows, TestRepo, {table, Ledger})

      assert detail == %{line: 2, column: "amount", inserted: 0}
      assert ledger_rows(table) == []
    end

    test "per chunk commits keep the chunks before the error" do
      table = Fixture.ledger!()
      rows = [entry(1, "1"), entry(2, "2"), entry(3, "bad"), entry(4, "4")]

      assert {:error, {:cast_failed, %{line: 3, inserted: 2}}} =
               Refract.DB.insert(rows, TestRepo, {table, Ledger}, chunk: 2, transaction: false)

      assert Enum.map(ledger_rows(table), & &1.entry_no) == [1, 2]
    end

    test "a database error raises and rolls back" do
      table = Fixture.ledger!()

      assert_raise Exqlite.Error, ~r/UNIQUE constraint failed/, fn ->
        Refract.DB.insert([entry(1, "1"), entry(1, "2")], TestRepo, {table, Ledger})
      end

      assert ledger_rows(table) == []
    end

    test "insert! gives the count or raises naming the row and column, not the value" do
      table = Fixture.ledger!()

      assert Refract.DB.insert!([entry(1, "1")], TestRepo, {table, Ledger}) == 1

      error =
        assert_raise InsertError, fn ->
          Refract.DB.insert!([entry(2, "secret-amount")], TestRepo, {table, Ledger})
        end

      assert error.message == "cannot insert rows: cast_failed line 1, amount"
    end
  end

  describe "chunks" do
    test "the default chunk stays under the bind parameter limit" do
      table = Fixture.ledger!()
      rows = Enum.map(1..10_000, &entry(&1, "1"))

      assert {:ok, 10_000} = Refract.DB.insert(rows, TestRepo, {table, Ledger})
    end

    test "a chunk over the limit is a database error" do
      table = Fixture.ledger!()
      rows = Enum.map(1..7_000, &entry(&1, "1"))

      assert_raise Exqlite.Error, ~r/variable number must be between \?1 and \?32766/, fn ->
        Refract.DB.insert(rows, TestRepo, {table, Ledger}, chunk: 7_000)
      end
    end
  end

  describe "upsert" do
    test "ecto on_conflict replaces matching rows and keeps inserted_at" do
      table = Fixture.ledger!()

      upsert = [
        on_conflict: {:replace_all_except, [:id, :inserted_at]},
        conflict_target: [:entry_no]
      ]

      assert {:ok, 2} =
               Refract.DB.insert([entry(1, "1"), entry(2, "2")], TestRepo, {table, Ledger})

      [first, _second] = ledger_rows(table)

      rows = [
        Map.put(entry(1, "10"), "updated_at", "2030-01-01T00:00:00"),
        entry(3, "3")
      ]

      assert {:ok, 2} = Refract.DB.insert(rows, TestRepo, {table, Ledger}, upsert)

      assert [updated, unchanged, added] = ledger_rows(table)
      assert {updated.id, updated.inserted_at} == {first.id, first.inserted_at}
      assert updated.updated_at == ~N[2030-01-01 00:00:00]
      assert Decimal.equal?(updated.amount, "10")
      assert Decimal.equal?(unchanged.amount, "2")
      assert added.entry_no == 3
    end

    test "on_conflict nothing skips matching rows" do
      table = Fixture.ledger!()

      assert {:ok, 1} = Refract.DB.insert([entry(1, "1")], TestRepo, {table, Ledger})

      assert {:ok, 1} =
               Refract.DB.insert([entry(1, "9"), entry(2, "2")], TestRepo, {table, Ledger},
                 on_conflict: :nothing,
                 conflict_target: [:entry_no]
               )

      assert [%Ledger{amount: amount}, %Ledger{entry_no: 2}] = ledger_rows(table)
      assert Decimal.equal?(amount, "1")
    end
  end

  describe "with refract" do
    test "a csv validated row by row goes in, issues and errors count rows the same" do
      table = Fixture.ledger!()

      csv = """
      entry_no,amount,posted_on
      1,12.50,2024-01-31
      2,,2024-02-01
      3,7.25,2024-02-02
      """

      shape =
        Shape.new(
          name: "ledger",
          spec:
            Table.spec(
              header: [
                columns: %{
                  "entry_no" => ["entry_no"],
                  "amount" => ["amount"],
                  "posted_on" => ["posted_on"]
                }
              ]
            ),
          validation: [columns: %{"amount" => [:required]}]
        )

      assert {:ok, rows} = Refract.CSV.stream({:string, csv})
      tagged = Enum.to_list(Refract.Validate.rows(rows, shape))

      assert [{:ok, _first}, {:invalid, _second, [%{line: 2, column: "amount"}]}, {:ok, _third}] =
               tagged

      valid = for {:ok, row} <- tagged, do: row

      assert {:ok, 2} = Refract.DB.insert(valid, TestRepo, {table, Ledger})

      source =
        Refract.DB.source(
          TestRepo,
          from(l in {table, Ledger}, select: map(l, [:id, :entry_no, :amount]))
        )

      assert {:ok, back} = Refract.DB.stream(source)
      assert Enum.map(back, & &1["entry_no"]) == [1, 3]
    end
  end

  describe "options" do
    test "the target must be a schema" do
      assert_raise ArgumentError, ~r/schema must be an ecto schema module/, fn ->
        Refract.DB.insert([], TestRepo, "ledger")
      end

      assert_raise ArgumentError, ~r/schema must be an ecto schema module/, fn ->
        Refract.DB.insert([], TestRepo, {"ledger", Shape})
      end
    end

    test "the repo must be a repo" do
      assert_raise ArgumentError, ~r/repo must be an ecto repo module/, fn ->
        Refract.DB.insert([], Ledger, Ledger)
      end
    end

    test "chunk, transaction and timeout are checked" do
      assert_raise ArgumentError, ~r/chunk must be a positive integer/, fn ->
        Refract.DB.insert([], TestRepo, Ledger, chunk: 0)
      end

      assert_raise ArgumentError, ~r/transaction must be true or false/, fn ->
        Refract.DB.insert([], TestRepo, Ledger, transaction: :yes)
      end

      assert_raise ArgumentError, ~r/timeout must be a positive integer or :infinity/, fn ->
        Refract.DB.insert([], TestRepo, Ledger, timeout: -1)
      end

      assert_raise ArgumentError, fn -> Refract.DB.insert([], TestRepo, Ledger, chunks: 2) end
    end
  end
end
