defmodule Refract.DB.TestSchemas.Account do
  use Ecto.Schema

  schema "accounts" do
    field(:account, :string)
    field(:amount, :decimal)
    field(:opened_on, :date)
    field(:active, :boolean)
    field(:notes, :map)
    field(:holder, :string, source: :holder_name)
  end
end

defmodule Refract.DB.TestSchemas.Keyless do
  use Ecto.Schema

  @primary_key false

  schema "keyless" do
    field(:account, :string)
  end
end

defmodule Refract.DB.TestSchemas.Ledger do
  use Ecto.Schema

  schema "ledger" do
    field(:entry_no, :integer)
    field(:amount, :decimal)
    field(:posted_on, :date)
    field(:memo, :string)

    timestamps()
  end
end

defmodule Refract.DB.TestSchemas.Customer do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "customers" do
    field(:email, :string)
    field(:tier, Ecto.Enum, values: [:gold, :silver])
    field(:score, :float)
    field(:joined_at, :utc_datetime)
    field(:ref, Ecto.UUID)
    field(:verified, :boolean)
  end
end

defmodule Refract.DB.TestSchemas.Profile do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "profiles" do
    field(:handle, :string)
    field(:tags, {:array, :string})
    field(:settings, :map)
    field(:balance, :decimal)
    field(:seen_at, :utc_datetime_usec)
    field(:tier, Ecto.Enum, values: [:gold, :silver])
    field(:verified, :boolean)
    field(:avatar, :binary)

    timestamps(type: :utc_datetime)
  end
end
