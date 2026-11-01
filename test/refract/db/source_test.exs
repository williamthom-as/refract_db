defmodule Refract.DB.SourceTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 2]

  alias Refract.DB.Source
  alias Refract.DB.TestRepo
  alias Refract.DB.TestSchemas.Account
  alias Refract.DB.TestSchemas.Keyless

  @moduletag timeout: 10_000

  describe "keys" do
    test "a schema pages by its primary key, ordered by it" do
      assert %Source{paging: :keyset, key: :id, key_column: "id", schema: Account, query: query} =
               Refract.DB.source(TestRepo, Account)

      assert [%{expr: [asc: _key]}] = query.order_bys
    end

    test "key names another column, its source name is the key column" do
      assert %Source{key: :holder, key_column: "holder_name"} =
               Refract.DB.source(TestRepo, Account, key: :holder)
    end

    test "a schemaless query pages by the key it is given" do
      query = from(l in "ledger", select: map(l, [:entry_no, :amount]))

      assert %Source{key: :entry_no, key_column: "entry_no", schema: nil} =
               Refract.DB.source(TestRepo, query, key: :entry_no)
    end

    test "offset paging keeps the query order and has no key" do
      query = from(a in Account, order_by: a.account)

      assert %Source{paging: :offset, key: nil, key_column: nil, query: ^query} =
               Refract.DB.source(TestRepo, query, paging: :offset)
    end

    test "a schemaless query without a key raises" do
      query = from(l in "ledger", select: map(l, [:entry_no]))

      assert_raise ArgumentError, ~r/give key: or paging: :offset/, fn ->
        Refract.DB.source(TestRepo, query)
      end
    end

    test "a schema with no single column primary key raises" do
      assert_raise ArgumentError, ~r/no single column primary key/, fn ->
        Refract.DB.source(TestRepo, Keyless)
      end
    end

    test "a key that is not a field raises" do
      assert_raise ArgumentError, ~r/:nope is not a field/, fn ->
        Refract.DB.source(TestRepo, Account, key: :nope)
      end
    end
  end

  describe "queries" do
    test "a schemaless query must select" do
      assert_raise ArgumentError, ~r/must select/, fn ->
        Refract.DB.source(TestRepo, "ledger", key: :entry_no)
      end
    end

    test "a limit or offset on the query raises" do
      assert_raise ArgumentError, ~r/drop its limit and offset/, fn ->
        Refract.DB.source(TestRepo, from(a in Account, limit: 10))
      end

      assert_raise ArgumentError, ~r/drop its limit and offset/, fn ->
        Refract.DB.source(TestRepo, from(a in Account, offset: 10))
      end
    end

    test "keyset paging refuses the query own order" do
      assert_raise ArgumentError, ~r/drop order_by or give paging: :offset/, fn ->
        Refract.DB.source(TestRepo, from(a in Account, order_by: a.account))
      end
    end

    test "offset paging needs an order" do
      assert_raise ArgumentError, ~r/needs order_by/, fn ->
        Refract.DB.source(TestRepo, Account, paging: :offset)
      end
    end
  end

  describe "options" do
    test "a module that is not a repo raises" do
      assert_raise ArgumentError, ~r/must be an ecto repo module/, fn ->
        Refract.DB.source(Account, Account)
      end

      assert_raise ArgumentError, ~r/must be an ecto repo module/, fn ->
        Refract.DB.source("repo", Account)
      end
    end

    test "key and paging are checked" do
      assert_raise ArgumentError, ~r/key must be a field name atom/, fn ->
        Refract.DB.source(TestRepo, Account, key: "id")
      end

      assert_raise ArgumentError, ~r/paging must be :keyset or :offset/, fn ->
        Refract.DB.source(TestRepo, Account, paging: :cursor)
      end
    end

    test "unknown options raise" do
      assert_raise ArgumentError, fn -> Refract.DB.source(TestRepo, Account, order: :id) end
    end
  end
end
