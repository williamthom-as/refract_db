defmodule Refract.DB.PgFixture do
  alias Ecto.Adapters.SQL
  alias Refract.DB.Fixture
  alias Refract.DB.PgRepo
  alias Refract.DB.TestSchemas.Profile

  def profiles!(entries \\ []) do
    table = "profiles_#{System.unique_integer([:positive])}"

    SQL.query!(PgRepo, """
    CREATE TABLE #{table} (
      id uuid PRIMARY KEY, handle text UNIQUE, tags text[], settings jsonb, balance numeric,
      seen_at timestamptz, tier text, verified boolean, avatar bytea,
      inserted_at timestamptz, updated_at timestamptz
    )
    """)

    PgRepo.insert_all({table, Profile}, Enum.map(entries, &Fixture.stamped/1))

    table
  end

  def raw!(sql, params \\ []), do: SQL.query!(PgRepo, sql, params)
end
