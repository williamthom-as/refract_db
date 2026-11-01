defmodule Refract.DB.MyFixture do
  alias Ecto.Adapters.SQL
  alias Refract.DB.Fixture
  alias Refract.DB.MyRepo
  alias Refract.DB.TestSchemas.Profile

  def profiles!(entries \\ []) do
    table = "profiles_#{System.unique_integer([:positive])}"

    SQL.query!(MyRepo, """
    CREATE TABLE `#{table}` (
      id BINARY(16) PRIMARY KEY, handle VARCHAR(255) UNIQUE, tags JSON, settings JSON,
      balance DECIMAL(12, 2), seen_at DATETIME(6), tier VARCHAR(16), verified BOOLEAN,
      avatar BLOB, inserted_at DATETIME, updated_at DATETIME
    )
    """)

    MyRepo.insert_all({table, Profile}, Enum.map(entries, &Fixture.stamped/1))

    table
  end

  def raw!(sql, params \\ []), do: SQL.query!(MyRepo, sql, params)
end
