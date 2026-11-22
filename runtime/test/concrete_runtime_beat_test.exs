defmodule ConcreteRuntime.BeatTest do
  @moduledoc """
  One HTTP walk of Helen → Alice scenes 1–7 (docs/11–12).
  Fakes IPFS/Identity. Live lab path is scripts/beat-smoke.sh.
  """
  use ExUnit.Case, async: false

  alias ConcreteRuntime.TestKit

  setup do
    TestKit.put_fakes()
    {:ok, _} = start_supervised(TestKit.Store)
    TestKit.Store.reset()

    dir = TestKit.tmp_dir()
    Enum.each(TestKit.children(dir), &start_supervised!/1)

    on_exit(fn -> TestKit.clear_fakes() end)
    :ok
  end

  test "scenes 1–7: empty CoT → W0 → W1 Alice → Exit → login → discovery → W2" do
    helen = TestKit.helen_attrs()
    alice = TestKit.alice_attrs()

    # 1. Power on, empty CoT (no auto-King)
    lab = json_get("/v1/lab")
    assert lab.status == 200
    assert json(lab)["powered"] == true
    assert json(lab)["genesis_complete"] == false

    boot = json_get("/v1/bootstrap")
    assert boot.status == 200
    assert json(boot)["king"] == nil
    assert json(boot)["principals"] == []

    # 2. W0 genesis once; replay fails
    genesis =
      json_post("/v1/genesis", %{
        "username" => helen.username,
        "public_key" => helen.public_key,
        "private_key" => helen.private_key,
        "pin" => helen.pin
      })

    assert genesis.status == 201
    g = json(genesis)
    assert g["principal"]["id"] == helen.public_key
    assert g["principal"]["role"] == "king" or g["principal"]["display_name"] == "Helen"
    assert String.starts_with?(g["g_did"], "did:")
    assert String.starts_with?(g["d2_did"], "did:")
    assert String.starts_with?(g["d4_did"], "did:")
    assert String.starts_with?(g["d5_did"], "did:")
    assert is_binary(g["ek_public_key"])

    replay =
      json_post("/v1/genesis", %{
        "username" => helen.username,
        "public_key" => helen.public_key,
        "private_key" => helen.private_key,
        "pin" => helen.pin
      })

    assert replay.status == 409
    assert json(replay)["error"] == "genesis_replay"

    # 3. W1 admits Alice; GraphEdit cannot widen caps
    locked =
      json_post("/v1/workspaces/save", %{
        "principal_id" => helen.public_key,
        "id" => "w1",
        "layout" => %{"grants" => [%{"verb" => "bootstrap"}]}
      })

    assert locked.status == 403
    assert json(locked)["error"] == "graph_locked"

    listed = json_get("/v1/workspaces?principal_id=#{enc(helen.public_key)}")
    assert listed.status == 200
    ids = Enum.map(json(listed)["workspaces"], & &1["id"])
    assert "w1" in ids
    assert "w2" in ids
    refute "w0" in ids

    introduced =
      json_post("/v1/workspaces/run", %{
        "principal_id" => helen.public_key,
        "id" => "w1",
        "username" => alice.username,
        "public_key" => alice.public_key
      })

    assert introduced.status == 201
    intro = json(introduced)
    assert intro["principal"]["id"] == alice.public_key
    assert intro["pin"] =~ ~r/^\d{5}$/
    assert String.starts_with?(intro["d5_did"], "did:")

    # 4. Exit session (not Esc)
    logout =
      json_post("/v1/session/logout", %{
        "principal_id" => helen.public_key
      })

    assert logout.status == 200
    assert json(logout)["logged_in"] == false
    refute ConcreteRuntime.Vault.usable?(helen.public_key)

    # 5. Alice login fail-closed, then success starts her vault
    bad_pin =
      json_post("/v1/session/login", %{
        "username" => "Alice",
        "pin" => "00000",
        "private_key" => alice.private_key
      })

    assert bad_pin.status == 403
    assert json(bad_pin)["error"] == "pin_mismatch"

    missing_key =
      json_post("/v1/session/login", %{
        "username" => "Alice",
        "pin" => intro["pin"],
        "private_key" => ""
      })

    assert missing_key.status == 400

    login =
      json_post("/v1/session/login", %{
        "username" => "Alice",
        "pin" => intro["pin"],
        "private_key" => alice.private_key
      })

    assert login.status == 200
    assert json(login)["principal"]["id"] == alice.public_key
    assert ConcreteRuntime.Vault.usable?(alice.public_key)
    refute ConcreteRuntime.Vault.usable?(helen.public_key)

    # Alice cannot run W1
    alice_w1 =
      json_post("/v1/workspaces/run", %{
        "principal_id" => alice.public_key,
        "id" => "w1",
        "username" => "Mallory",
        "public_key" => "mldsa87:mallory"
      })

    assert alice_w1.status == 403

    # 6. Discovery from D5[Alice]: G present, D4 marker only
    disc1 = json_get("/v1/discovery?principal_id=#{enc(alice.public_key)}")
    assert disc1.status == 200
    graph1 = json(disc1)
    dids1 = Enum.map(graph1["nodes"], & &1["did"])
    assert g["g_did"] in dids1

    d4_node = Enum.find(graph1["nodes"], &(&1["did"] == g["d4_did"]))
    assert d4_node
    assert d4_node["kind"] == "data"
    assert d4_node["marker"] == true
    refute Map.has_key?(d4_node, "payload")
    refute Map.has_key?(d4_node, "pin")

    d4 =
      json_get("/v1/data_object?principal_id=#{enc(alice.public_key)}&did=#{enc(g["d4_did"])}")

    assert d4.status == 200
    d4_body = json(d4)
    assert d4_body["marker"] == true
    refute Map.has_key?(d4_body, "payload")

    # 7. W2 authors info, auto-links D5; discovery shows it
    written =
      json_post("/v1/workspaces/run", %{
        "principal_id" => alice.public_key,
        "id" => "w2",
        "text" => "Hello from Alice",
        "readers" => ["Helen", "Alice"],
        "writers" => ["Alice"],
        "link_did" => g["g_did"]
      })

    assert written.status == 201
    info = json(written)
    assert is_binary(info["did"])
    assert String.starts_with?(info["did"], "did:")

    disc2 = json_get("/v1/discovery?principal_id=#{enc(alice.public_key)}")
    assert disc2.status == 200
    dids2 = Enum.map(json(disc2)["nodes"], & &1["did"])
    assert info["did"] in dids2
    assert g["g_did"] in dids2
    info_node = Enum.find(json(disc2)["nodes"], &(&1["did"] == info["did"]))
    assert info_node["kind"] == "info"
    assert info_node["marker"] == false
  end

  defp json_get(path) do
    Plug.Test.conn(:get, path)
    |> ConcreteRuntime.API.call([])
  end

  defp json_post(path, params) do
    Plug.Test.conn(:post, path, params)
    |> ConcreteRuntime.API.call([])
  end

  defp json(conn), do: Jason.decode!(conn.resp_body)

  defp enc(value), do: URI.encode(value, &URI.char_unreserved?/1)
end
