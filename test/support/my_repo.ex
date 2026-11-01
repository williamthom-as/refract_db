defmodule Refract.DB.MyRepo do
  use Ecto.Repo, otp_app: :refract_db, adapter: Ecto.Adapters.MyXQL

  def options do
    [
      hostname: System.get_env("MYSQL_HOST", "127.0.0.1"),
      port: String.to_integer(System.get_env("MYSQL_PORT", "3306")),
      username: System.get_env("MYSQL_USER", "root"),
      password: System.get_env("MYSQL_PASSWORD", "mysql"),
      database: System.get_env("MYSQL_DATABASE", "refract_db_test"),
      log: false
    ]
  end
end
