defmodule Refract.DB.PgRepo do
  use Ecto.Repo, otp_app: :refract_db, adapter: Ecto.Adapters.Postgres

  def options do
    [
      hostname: System.get_env("PGHOST", "localhost"),
      port: String.to_integer(System.get_env("PGPORT", "5432")),
      username: System.get_env("PGUSER", "postgres"),
      password: System.get_env("PGPASSWORD", "postgres"),
      database: System.get_env("PGDATABASE", "refract_db_test"),
      after_connect: {Postgrex, :query!, ["SET search_path TO refract_db", []]},
      log: false
    ]
  end
end

Postgrex.Types.define(
  Refract.DB.DurationTypes,
  Ecto.Adapters.Postgres.extensions(),
  interval_decode_type: Duration
)
