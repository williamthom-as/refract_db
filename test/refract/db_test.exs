defmodule Refract.DBTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 2]

  alias Refract.Classify.Facts
  alias Refract.Classify.Result
  alias Refract.DB.Fixture
  alias Refract.DB.TestRepo
  alias Refract.DB.TestSchemas.Account
  alias Refract.Shape
  alias Refract.Table
  alias Refract.Validate.Issue

  @moduletag timeout: 10_000

  defp accounts_source(table, opts \\ []),
    do: Refract.DB.source(TestRepo, {table, Account}, opts)

  defp lines(source, opts \\ []) do
    assert {:ok, lines} = Refract.DB.open(source, opts)
    Enum.to_list(lines)
  end

  defp account_shape(validation \\ []) do
    Shape.new(
      name: "account",
      spec:
        Table.spec(
          header: [columns: %{"account" => ["account"], "amount" => ["amount"]}],
          row: [match: %{"amount" => :number}]
        ),
      validation: validation
    )
  end

  def handle_query(_event, _measurements, %{query: sql}, {test_pid, table}) do
    if self() == test_pid and String.contains?(sql, table), do: send(test_pid, :query)
  end

  defp count_queries(table) do
    id = {__MODULE__, make_ref()}
    event = [:refract, :db, :test_repo, :query]

    :telemetry.attach(id, event, &__MODULE__.handle_query/4, {self(), table})

    on_exit(fn -> :telemetry.detach(id) end)
  end

  defp queries_received(count) do
    receive do
      :query -> queries_received(count + 1)
    after
      0 -> count
    end
  end

  describe "open" do
    test "the column names then a line per row, schema columns loaded" do
      table =
        Fixture.accounts!([
          %{
            id: 1,
            account: "A-1",
            amount: Decimal.new("12.5"),
            opened_on: ~D[2024-01-31],
            active: true,
            notes: %{"tier" => "gold"},
            holder: "Ada"
          }
        ])

      assert lines(accounts_source(table)) == [
               ["id", "account", "amount", "opened_on", "active", "notes", "holder_name"],
               [1, "A-1", Decimal.new("12.5"), ~D[2024-01-31], true, ~s({"tier":"gold"}), "Ada"]
             ]
    end

    test "nil stays nil" do
      table = Fixture.accounts!([%{id: 1, account: nil}])

      assert [_header, [1, nil, nil, nil, nil, nil, nil]] = lines(accounts_source(table))
    end

    test "a schemaless query gives the values as the adapter does" do
      table = Fixture.accounts!([%{id: 1, active: true, opened_on: ~D[2024-01-31]}])
      query = from(a in table, select: map(a, [:id, :active, :opened_on]))

      assert lines(Refract.DB.source(TestRepo, query, key: :id)) == [
               ["id", "active", "opened_on"],
               [1, 1, "2024-01-31"]
             ]
    end

    test "a binary that is not text is its hex" do
      table = Fixture.accounts!([%{id: 1}])
      Fixture.raw!(table, "UPDATE $table SET holder_name = X'00FF10'")
      query = from(a in table, select: map(a, [:id, :holder_name]))

      assert [_header, [1, "00ff10"]] = lines(Refract.DB.source(TestRepo, query, key: :id))
    end

    test "a query error comes back straight away" do
      assert {:error, %Exqlite.Error{}} =
               Refract.DB.open(accounts_source("missing_table"), [])
    end

    test "a key the query does not select is an error" do
      table = Fixture.accounts!(Fixture.accounts(1))
      query = from(a in {table, Account}, select: map(a, [:account]))

      assert {:error, {:key_not_selected, :id}} =
               Refract.DB.open(Refract.DB.source(TestRepo, query), [])
    end

    test "a source that is not a query source is unsupported" do
      assert {:error, {:unsupported_source, "accounts.csv"}} =
               Refract.DB.open("accounts.csv", [])
    end

    test "page_size is checked" do
      table = Fixture.accounts!([])

      assert_raise ArgumentError, ~r/page_size must be a positive integer/, fn ->
        Refract.DB.open(accounts_source(table), page_size: 0)
      end

      assert_raise ArgumentError, fn -> Refract.DB.open(accounts_source(table), size: 2) end
    end
  end

  describe "pages" do
    test "every row comes back once across pages, in key order" do
      table = Fixture.accounts!(Enum.reverse(Fixture.accounts(5)))

      assert [_header | rows] = lines(accounts_source(table), page_size: 2)
      assert Enum.map(rows, &hd/1) == [1, 2, 3, 4, 5]
    end

    test "rows that fill the last page exactly are not repeated" do
      table = Fixture.accounts!(Fixture.accounts(4))

      assert [_header | rows] = lines(accounts_source(table), page_size: 2)
      assert Enum.map(rows, &hd/1) == [1, 2, 3, 4]
    end

    test "an empty table gives the header only" do
      table = Fixture.accounts!([])

      assert [["id" | _columns]] = lines(accounts_source(table))
    end

    test "only the first page is read when the source opens" do
      table = Fixture.accounts!(Fixture.accounts(5))
      count_queries(table)

      assert {:ok, lines} = Refract.DB.open(accounts_source(table), page_size: 2)
      assert queries_received(0) == 1

      assert length(Enum.take(lines, 3)) == 3
      assert queries_received(0) == 0

      assert length(Enum.to_list(lines)) == 6
      assert queries_received(0) == 2
    end

    test "rows removed behind the page do not shift the next page" do
      table = Fixture.accounts!(Fixture.accounts(4))

      assert {:ok, lines} = Refract.DB.open(accounts_source(table), page_size: 2)
      Fixture.raw!(table, "DELETE FROM $table WHERE id = 1")

      assert Enum.map(Enum.drop(lines, 1), &hd/1) == [1, 2, 3, 4]
    end

    test "offset paging walks the query order" do
      table = Fixture.accounts!(Fixture.accounts(5))
      query = from(a in {table, Account}, order_by: [desc: a.id])

      assert [_header | rows] =
               lines(Refract.DB.source(TestRepo, query, paging: :offset), page_size: 2)

      assert Enum.map(rows, &hd/1) == [5, 4, 3, 2, 1]
    end

    test "a schemaless query pages by its key" do
      table = Fixture.accounts!(Fixture.accounts(3))
      query = from(a in table, select: map(a, [:account, :id]))

      assert lines(Refract.DB.source(TestRepo, query, key: :id), page_size: 2) == [
               ["account", "id"],
               ["A-1", 1],
               ["A-2", 2],
               ["A-3", 3]
             ]
    end
  end

  describe "refract tools" do
    test "stream gives row maps under the column names" do
      table = Fixture.accounts!(Fixture.accounts(2))

      assert {:ok, rows} = Refract.DB.stream(accounts_source(table))

      assert [%{"id" => 1, "account" => "A-1", "amount" => amount}, %{"id" => 2}] =
               Enum.to_list(rows)

      assert Decimal.equal?(amount, "1.50")
    end

    test "classify matches a table, no path, the source in the facts" do
      table = Fixture.accounts!(Fixture.accounts(3))

      assert {:ok, %Result{verdict: :match, file: file, drift: drift}} =
               Refract.DB.classify(accounts_source(table), [account_shape()])

      assert %Facts{path: nil, size: :unknown, format: format} = file
      assert format == %{table: table, schema: Account, paging: :keyset, key: :id, page_size: 500}

      assert Enum.map(drift.extra, &elem(&1, 1)) == [
               "id",
               "opened_on",
               "active",
               "notes",
               "holder_name"
             ]
    end

    test "validate counts issues by record" do
      table =
        Fixture.accounts!([
          %{id: 1, account: "A-1", amount: Decimal.new("1")},
          %{id: 2, account: "bad", amount: Decimal.new("2")},
          %{id: 3, account: "A-3", amount: Decimal.new("3")}
        ])

      shape = account_shape(columns: %{"account" => [~r/^A-\d+$/]})

      assert {:ok, %Refract.Validate.Result{valid: false, rows: 3, issues: [issue]}} =
               Refract.DB.validate(accounts_source(table), shape)

      assert %Issue{line: 2, column: "account"} = issue
    end

    test "profile reads every page" do
      table = Fixture.accounts!(Fixture.accounts(5))

      assert {:ok, %Refract.Profile.Result{rows: 5}} =
               Refract.DB.profile(accounts_source(table), account_shape(), page_size: 2)
    end

    test "load needs a sized source" do
      table = Fixture.accounts!(Fixture.accounts(1))

      assert {:error, {:unsupported_source, _source}} = Refract.DB.load(accounts_source(table))
    end
  end
end
