defmodule Refract.DB.TestRepo do
  use Ecto.Repo, otp_app: :refract_db, adapter: Ecto.Adapters.SQLite3
end
