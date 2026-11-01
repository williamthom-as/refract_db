defmodule Refract.DB.Fixture do
  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL
  alias Refract.DB.TestRepo
  alias Refract.DB.TestSchemas.Account

  def lines!([], dir), do: lines!([["empty"]], dir)

  def lines!([header | rows], _dir) do
    table = unique("lines")
    width = Enum.max(Enum.map([header | rows], &length/1))
    names = Enum.map(header, &quoted/1)

    SQL.query!(
      TestRepo,
      "CREATE TABLE #{quoted(table)} (#{Enum.map_join(names, ", ", &"#{&1} TEXT")})"
    )

    Enum.each(rows, fn row ->
      values = row ++ List.duplicate(nil, width - length(row))
      marks = Enum.map_join(values, ", ", fn _value -> "?" end)
      SQL.query!(TestRepo, "INSERT INTO #{quoted(table)} VALUES (#{marks})", values)
    end)

    fields = Enum.map(header, &String.to_atom/1)

    Refract.DB.source(
      TestRepo,
      from(t in table, order_by: fragment("rowid"), select: map(t, ^fields)),
      paging: :offset
    )
  end

  def accounts!(entries) do
    table = unique("accounts")

    SQL.query!(TestRepo, """
    CREATE TABLE #{quoted(table)} (
      id INTEGER PRIMARY KEY, account TEXT, amount DECIMAL, opened_on DATE, active BOOLEAN,
      notes TEXT, holder_name TEXT
    )
    """)

    TestRepo.insert_all({table, Account}, entries)

    table
  end

  def ledger! do
    table = unique("ledger")

    SQL.query!(TestRepo, """
    CREATE TABLE #{quoted(table)} (
      id INTEGER PRIMARY KEY, entry_no INTEGER UNIQUE, amount DECIMAL, posted_on DATE, memo TEXT,
      inserted_at TEXT, updated_at TEXT
    )
    """)

    table
  end

  def customers!(entries) do
    table = unique("customers")

    SQL.query!(TestRepo, """
    CREATE TABLE #{quoted(table)} (
      id TEXT PRIMARY KEY, email TEXT, tier TEXT, score REAL, joined_at TEXT, ref TEXT,
      verified BOOLEAN
    )
    """)

    TestRepo.insert_all({table, Refract.DB.TestSchemas.Customer}, entries)

    table
  end

  def accounts(count) do
    Enum.map(1..count//1, &%{id: &1, account: "A-#{&1}", amount: Decimal.new("#{&1}.50")})
  end

  def profile(n) do
    %{
      handle: "user-#{n}",
      tags: ["a", "b"],
      settings: %{"theme" => "dark"},
      balance: Decimal.new("12.50"),
      seen_at: ~U[2024-01-31 10:00:00.123456Z],
      tier: :gold,
      verified: true,
      avatar: <<0, 255, 16>>
    }
  end

  def stamped(entry) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    Map.merge(%{id: Ecto.UUID.generate(), inserted_at: now, updated_at: now}, entry)
  end

  def raw!(table, sql), do: SQL.query!(TestRepo, String.replace(sql, "$table", quoted(table)))

  defp unique(prefix), do: "#{prefix}_#{System.unique_integer([:positive])}"

  defp quoted(name), do: ~s("#{String.replace(name, ~s("), ~s(""))}")
end
