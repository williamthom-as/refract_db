defmodule Refract.DB.PostgresTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 2]

  alias Refract.Classify.Result
  alias Refract.DB.Fixture
  alias Refract.DB.PgFixture
  alias Refract.DB.PgRepo
  alias Refract.DB.TestSchemas.Profile

  @moduletag :postgres
  @moduletag timeout: 30_000

  defp lines(source, opts \\ []) do
    assert {:ok, lines} = Refract.DB.open(source, opts)
    Enum.to_list(lines)
  end

  defp profiles(table), do: Refract.DB.source(PgRepo, {table, Profile})

  def handle_query(_event, _measurements, %{repo: _repo}, {test_pid, repo}) do
    if PgRepo.get_dynamic_repo() == repo and self() == test_pid, do: send(test_pid, :query)
  end

  defp count_queries(repo) do
    id = {__MODULE__, make_ref()}
    event = [:refract, :db, :pg_repo, :query]

    :telemetry.attach(id, event, &__MODULE__.handle_query/4, {self(), repo})

    on_exit(fn -> :telemetry.detach(id) end)
  end

  defp queries_received(count) do
    receive do
      :query -> queries_received(count + 1)
    after
      0 -> count
    end
  end

  describe "reading" do
    test "a schema query loads every type" do
      table = PgFixture.profiles!([Fixture.profile(1)])

      assert [header, [id | values]] = lines(profiles(table))

      assert header == [
               "id",
               "handle",
               "tags",
               "settings",
               "balance",
               "seen_at",
               "tier",
               "verified",
               "avatar",
               "inserted_at",
               "updated_at"
             ]

      assert {:ok, _uuid} = Ecto.UUID.cast(id)

      assert [
               "user-1",
               ~s(["a","b"]),
               ~s({"theme":"dark"}),
               balance,
               ~U[2024-01-31 10:00:00.123456Z],
               "gold",
               true,
               "00ff10",
               %DateTime{},
               %DateTime{}
             ] = values

      assert Decimal.to_string(balance) == "12.50"
    end

    test "a schemaless query gives the adapter values" do
      PgFixture.raw!("""
      CREATE TABLE readings (
        id bigint PRIMARY KEY, ref uuid, tags int[], meta jsonb, amount numeric, at timestamptz,
        on_day date, at_time time, wait interval
      )
      """)

      PgFixture.raw!("""
      INSERT INTO readings VALUES (
        1, 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', '{1,2}', '{"k": 1}', 3.10,
        '2024-01-31 10:00:00+00', '2024-01-31', '10:30:00', '1 day 02:00:00'
      )
      """)

      query =
        from(r in "readings",
          select: map(r, [:id, :ref, :tags, :meta, :amount, :at, :on_day, :at_time, :wait])
        )

      assert [_header, [1, ref, tags, meta, amount, at, on_day, at_time, wait]] =
               lines(Refract.DB.source(PgRepo, query, key: :id))

      assert ref == "a0eebc999c0b4ef8bb6d6bb9bd380a11"
      assert tags == "[1,2]"
      assert meta == ~s({"k":1})
      assert Decimal.to_string(amount) == "3.10"
      assert at == ~U[2024-01-31 10:00:00.000000Z]
      assert on_day == ~D[2024-01-31]
      assert at_time == ~T[10:30:00.000000]
      assert wait == "%Postgrex.Interval{months: 0, days: 1, secs: 7200, microsecs: 0}"
    end

    test "intervals decoded as a duration read as iso 8601" do
      {:ok, repo} =
        PgRepo.start_link(
          Keyword.merge(PgRepo.options(), name: nil, types: Refract.DB.DurationTypes)
        )

      PgRepo.put_dynamic_repo(repo)
      on_exit(fn -> Process.exit(repo, :normal) end)

      PgFixture.raw!("CREATE TABLE waits (id bigint PRIMARY KEY, wait interval)")
      PgFixture.raw!("INSERT INTO waits VALUES (1, '1 day 02:00:00')")
      query = from(w in "waits", select: map(w, [:id, :wait]))

      assert [_header, [1, "P1DT7200.000000S"]] =
               lines(Refract.DB.source(PgRepo, query, key: :id))
    end

    test "a dynamic repo is read and written through" do
      {:ok, repo} = PgRepo.start_link(Keyword.merge(PgRepo.options(), name: nil, pool_size: 1))
      PgRepo.put_dynamic_repo(repo)
      on_exit(fn -> Process.exit(repo, :normal) end)

      table = PgFixture.profiles!()
      count_queries(repo)

      assert {:ok, 1} = Refract.DB.insert([%{"handle" => "ada"}], PgRepo, {table, Profile})
      assert [_header, [_id, "ada" | _rest]] = lines(profiles(table))
      assert queries_received(0) >= 2
    end

    test "keyset pages follow a uuid key on a schema query" do
      table = PgFixture.profiles!(Enum.map(1..5, &Fixture.profile/1))

      assert [_header | rows] = lines(profiles(table), page_size: 2)
      assert length(Enum.uniq_by(rows, &hd/1)) == 5
    end

    test "keyset pages follow a uuid key on a schemaless query" do
      table = PgFixture.profiles!(Enum.map(1..5, &Fixture.profile/1))
      query = from(p in table, select: map(p, [:id, :handle]))

      assert [_header | rows] = lines(Refract.DB.source(PgRepo, query, key: :id), page_size: 2)
      assert rows |> Enum.map(&List.last/1) |> Enum.sort() == Enum.map(1..5, &"user-#{&1}")
    end

    test "classify and validate a table against its schema shape" do
      table = PgFixture.profiles!(Enum.map(1..3, &Fixture.profile/1))
      shape = Refract.DB.shape(Profile, required: [:handle])

      assert {:ok, %Result{verdict: :match}} = Refract.DB.classify(profiles(table), [shape])

      assert {:ok, %Refract.Validate.Result{valid: true, rows: 3}} =
               Refract.DB.validate(profiles(table), shape)
    end
  end

  describe "inserting" do
    test "text from a file is cast, json text for maps and arrays" do
      table = PgFixture.profiles!()

      row = %{
        "handle" => "ada",
        "tags" => ~s(["x","y"]),
        "settings" => ~s({"theme":"light"}),
        "balance" => "4.20",
        "seen_at" => "2024-02-01T09:00:00Z",
        "tier" => "silver",
        "verified" => "true"
      }

      assert {:ok, 1} = Refract.DB.insert([row], PgRepo, {table, Profile})

      assert [%Profile{} = profile] = PgRepo.all({table, Profile})
      assert profile.tags == ["x", "y"]
      assert profile.settings == %{"theme" => "light"}
      assert Decimal.to_string(profile.balance) == "4.20"
      assert profile.tier == :silver
      assert profile.verified == true
      assert %DateTime{} = profile.inserted_at
      assert {:ok, _uuid} = Ecto.UUID.cast(profile.id)
    end

    test "json text that does not decode fails the cast" do
      table = PgFixture.profiles!()

      assert {:error, {:cast_failed, %{line: 1, column: "settings"}}} =
               Refract.DB.insert([%{"settings" => "{not json"}], PgRepo, {table, Profile})
    end

    test "a table read from one database goes into another unchanged" do
      from_table =
        PgFixture.profiles!(Enum.map(1..3, &Map.put(Fixture.profile(&1), :avatar, nil)))

      to_table = PgFixture.profiles!()

      assert {:ok, rows} = Refract.DB.stream(profiles(from_table))
      assert {:ok, 3} = Refract.DB.insert(rows, PgRepo, {to_table, Profile})

      read = fn table ->
        from(p in {table, Profile}, order_by: p.handle)
        |> PgRepo.all()
        |> Enum.map(&Map.delete(Map.from_struct(&1), :__meta__))
      end

      assert read.(to_table) == read.(from_table)
    end

    test "upsert on a unique column" do
      table = PgFixture.profiles!()
      upsert = [on_conflict: {:replace, [:balance, :updated_at]}, conflict_target: [:handle]]

      assert {:ok, 1} =
               Refract.DB.insert(
                 [%{"handle" => "ada", "balance" => "1"}],
                 PgRepo,
                 {table, Profile}
               )

      assert {:ok, 2} =
               Refract.DB.insert(
                 [%{"handle" => "ada", "balance" => "9"}, %{"handle" => "bob", "balance" => "2"}],
                 PgRepo,
                 {table, Profile},
                 upsert
               )

      assert [ada, bob] = PgRepo.all(from(p in {table, Profile}, order_by: p.handle))
      assert {ada.handle, Decimal.to_string(ada.balance)} == {"ada", "9"}
      assert bob.handle == "bob"
    end

    test "the default chunk stays under the bind parameter limit" do
      table = PgFixture.profiles!()
      rows = Enum.map(1..20_000, &%{"handle" => "user-#{&1}", "balance" => "1"})

      assert {:ok, 20_000} = Refract.DB.insert(rows, PgRepo, {table, Profile})
    end
  end
end
