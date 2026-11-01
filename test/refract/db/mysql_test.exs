defmodule Refract.DB.MySQLTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 2]

  alias Refract.Classify.Result
  alias Refract.DB.Fixture
  alias Refract.DB.MyFixture
  alias Refract.DB.MyRepo
  alias Refract.DB.TestSchemas.Profile

  @moduletag :mysql
  @moduletag timeout: 30_000

  defp lines(source, opts \\ []) do
    assert {:ok, lines} = Refract.DB.open(source, opts)
    Enum.to_list(lines)
  end

  defp profiles(table), do: Refract.DB.source(MyRepo, {table, Profile})

  defp fields(table) do
    from(p in {table, Profile}, order_by: p.handle)
    |> MyRepo.all()
    |> Enum.map(&Map.delete(Map.from_struct(&1), :__meta__))
  end

  describe "reading" do
    test "a schema query loads every type" do
      table = MyFixture.profiles!([Fixture.profile(1)])

      assert [_header, [id | values]] = lines(profiles(table))
      assert {:ok, _uuid} = Ecto.UUID.cast(id)

      assert [
               "user-1",
               tags,
               settings,
               balance,
               %DateTime{} = seen_at,
               "gold",
               true,
               "00ff10",
               %DateTime{},
               %DateTime{}
             ] = values

      assert JSON.decode!(tags) == ["a", "b"]
      assert JSON.decode!(settings) == %{"theme" => "dark"}
      assert Decimal.to_string(balance) == "12.50"
      assert seen_at == ~U[2024-01-31 10:00:00.123456Z]
    end

    test "a schemaless query gives the adapter values" do
      table = MyFixture.profiles!([Fixture.profile(1)])
      query = from(p in table, select: map(p, [:handle, :id, :verified, :settings, :balance]))

      assert [_header, ["user-1", id, verified, settings, balance]] =
               lines(Refract.DB.source(MyRepo, query, key: :handle))

      assert String.length(id) == 32
      assert verified == 1
      assert JSON.decode!(settings) == %{"theme" => "dark"}
      assert Decimal.to_string(balance) == "12.50"
    end

    test "keyset pages follow a binary uuid key" do
      table = MyFixture.profiles!(Enum.map(1..5, &Fixture.profile/1))
      schemaless = from(p in table, select: map(p, [:id, :handle]))

      assert [_header | rows] = lines(profiles(table), page_size: 2)
      assert length(Enum.uniq_by(rows, &hd/1)) == 5

      assert [_header | rows] =
               lines(Refract.DB.source(MyRepo, schemaless, key: :id), page_size: 2)

      assert rows |> Enum.map(&List.last/1) |> Enum.sort() == Enum.map(1..5, &"user-#{&1}")
    end

    test "classify and validate a table against its schema shape" do
      table = MyFixture.profiles!(Enum.map(1..3, &Fixture.profile/1))
      shape = Refract.DB.shape(Profile, required: [:handle])

      assert {:ok, %Result{verdict: :match}} = Refract.DB.classify(profiles(table), [shape])

      assert {:ok, %Refract.Validate.Result{valid: true, rows: 3}} =
               Refract.DB.validate(profiles(table), shape)
    end
  end

  describe "inserting" do
    test "text from a file is cast, json text for maps and arrays" do
      table = MyFixture.profiles!()

      row = %{
        "handle" => "ada",
        "tags" => ~s(["x","y"]),
        "settings" => ~s({"theme":"light"}),
        "balance" => "4.20",
        "seen_at" => "2024-02-01T09:00:00Z",
        "tier" => "silver",
        "verified" => "true"
      }

      assert {:ok, 1} = Refract.DB.insert([row], MyRepo, {table, Profile})

      assert [profile] = fields(table)
      assert profile.tags == ["x", "y"]
      assert profile.settings == %{"theme" => "light"}
      assert Decimal.to_string(profile.balance) == "4.20"
      assert profile.tier == :silver
      assert profile.verified == true
      assert %DateTime{} = profile.inserted_at
    end

    test "a table read from one database goes into another unchanged" do
      from_table =
        MyFixture.profiles!(Enum.map(1..3, &Map.put(Fixture.profile(&1), :avatar, nil)))

      to_table = MyFixture.profiles!()

      assert {:ok, rows} = Refract.DB.stream(profiles(from_table))
      assert {:ok, 3} = Refract.DB.insert(rows, MyRepo, {to_table, Profile})
      assert fields(to_table) == fields(from_table)
    end

    test "upsert without a conflict target, an updated row counts twice" do
      table = MyFixture.profiles!()

      assert {:ok, 1} =
               Refract.DB.insert(
                 [%{"handle" => "ada", "balance" => "1"}],
                 MyRepo,
                 {table, Profile}
               )

      assert {:ok, 3} =
               Refract.DB.insert(
                 [%{"handle" => "ada", "balance" => "9"}, %{"handle" => "bob", "balance" => "2"}],
                 MyRepo,
                 {table, Profile},
                 on_conflict: {:replace, [:balance, :updated_at]}
               )

      assert [ada, bob] = fields(table)
      assert {ada.handle, Decimal.to_string(ada.balance)} == {"ada", "9.00"}
      assert bob.handle == "bob"
    end

    test "a conflict target is refused by ecto" do
      table = MyFixture.profiles!()

      assert_raise ArgumentError, ~r/conflict_target is not supported/, fn ->
        Refract.DB.insert([%{"handle" => "ada"}], MyRepo, {table, Profile},
          on_conflict: :nothing,
          conflict_target: [:handle]
        )
      end
    end

    test "the default chunk stays under the bind parameter limit" do
      table = MyFixture.profiles!()
      rows = Enum.map(1..20_000, &%{"handle" => "user-#{&1}", "balance" => "1"})

      assert {:ok, 20_000} = Refract.DB.insert(rows, MyRepo, {table, Profile})
    end
  end
end
