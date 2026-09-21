defmodule ConcreteRuntime.CotTest do
  use ExUnit.Case, async: false

  alias ConcreteRuntime.TestKit

  setup do
    TestKit.put_fakes()
    {:ok, _} = start_supervised(TestKit.Store)
    TestKit.Store.reset()

    dir = TestKit.tmp_dir()
    Enum.each(TestKit.children(dir), &start_supervised!/1)

    on_exit(fn -> TestKit.clear_fakes() end)

    {:ok, genesis} = ConcreteRuntime.Workspaces.genesis(TestKit.helen_attrs())
    helen = genesis.principal.id
    %{helen: helen, genesis: genesis}
  end

  test "GraphEdit cannot widen caps; locked graph is denied", %{helen: helen} do
    before = ConcreteRuntime.Bootstrap.capabilities(helen)

    assert {:error, :graph_locked} =
             ConcreteRuntime.Workspaces.save_layout(helen, "w1", %{
               "grants" => [%{"verb" => "bootstrap"}]
             })

    assert ConcreteRuntime.Bootstrap.capabilities(helen) == before
  end

  test "W1 admits Alice; she cannot write D2 or rewire W1", %{helen: helen, genesis: genesis} do
    alice = TestKit.alice_attrs()

    assert {:ok, introduced} =
             ConcreteRuntime.Workspaces.introduce_user(helen, %{
               username: alice.username,
               public_key: alice.public_key
             })

    assert introduced.principal.id == alice.public_key
    assert String.match?(introduced.pin, ~r/^\d{5}$/)

    d1 = ConcreteRuntime.DataObjects.record(genesis.d1_did)
    assert alice.public_key in d1.payload["pubkeys"]

    d2 = ConcreteRuntime.DataObjects.record(genesis.d2_did)
    refute alice.public_key in (d2.payload["eks"] || [])

    assert {:error, :capability_denied} =
             ConcreteRuntime.DataObjects.update(
               alice.public_key,
               genesis.d2_did,
               %{eks: ["stolen"]},
               []
             )

    assert {:error, :graph_locked} =
             ConcreteRuntime.Workspaces.save_layout(alice.public_key, "w1", %{})

    assert {:error, :capability_denied} =
             ConcreteRuntime.Workspaces.introduce_user(alice.public_key, %{
               username: "Mallory",
               public_key: "mldsa87:mallory"
             })
  end

  test "Exit drops Helen use; Alice login starts her vault", %{helen: helen} do
    alice = TestKit.alice_attrs()

    {:ok, introduced} =
      ConcreteRuntime.Workspaces.introduce_user(helen, %{
        username: alice.username,
        public_key: alice.public_key
      })

    assert :ok = ConcreteRuntime.Workspaces.logout(helen)
    refute ConcreteRuntime.Vault.usable?(helen)
    assert ConcreteRuntime.Vault.has_material?(helen)

    assert {:error, :pin_mismatch} =
             ConcreteRuntime.Workspaces.login(%{
               username: "Alice",
               pin: "00000",
               private_key: alice.private_key
             })

    assert {:error, :missing_private_key} =
             ConcreteRuntime.Workspaces.login(%{
               username: "Alice",
               pin: introduced.pin,
               private_key: ""
             })

    assert {:ok, login} =
             ConcreteRuntime.Workspaces.login(%{
               username: "Alice",
               pin: introduced.pin,
               private_key: alice.private_key
             })

    assert login.principal.id == alice.public_key
    assert ConcreteRuntime.Vault.usable?(alice.public_key)
    refute ConcreteRuntime.Vault.usable?(helen)
  end

  test "Alice W2 authors info, auto-links D5, discovery shows it and omits D4 bytes", %{
    helen: helen,
    genesis: genesis
  } do
    alice = TestKit.alice_attrs()

    {:ok, introduced} =
      ConcreteRuntime.Workspaces.introduce_user(helen, %{
        username: alice.username,
        public_key: alice.public_key
      })

    :ok = ConcreteRuntime.Workspaces.logout(helen)

    {:ok, _} =
      ConcreteRuntime.Workspaces.login(%{
        username: "Alice",
        pin: introduced.pin,
        private_key: alice.private_key
      })

    assert {:ok, obj} =
             ConcreteRuntime.Workspaces.write_info(alice.public_key, %{
               text: "Hello from Alice",
               readers: ["Helen", "Alice"],
               writers: ["Alice"],
               link_did: genesis.g_did
             })

    assert obj.content == "Hello from Alice"
    assert alice.public_key in obj.read_list

    {:ok, graph} = ConcreteRuntime.Discovery.walk(alice.public_key)
    dids = Enum.map(graph.nodes, & &1.did)
    assert obj.did in dids
    assert genesis.g_did in dids

    d4_node = Enum.find(graph.nodes, &(&1.did == genesis.d4_did))
    assert d4_node
    assert d4_node.kind == "data"
    assert d4_node.marker == true
    refute Map.has_key?(d4_node, :payload)
    refute Map.has_key?(d4_node, :pin)

    {:ok, d4} = ConcreteRuntime.DataObjects.get(alice.public_key, genesis.d4_did)
    assert d4.marker == true
    refute Map.has_key?(d4, :payload)

    {:ok, d4_helen} = ConcreteRuntime.DataObjects.get(helen, genesis.d4_did)
    refute Map.get(d4_helen, :marker, false)
    assert d4_helen.payload["pairs"]
  end

  test "unread info is omitted from Alice discovery", %{helen: helen} do
    alice = TestKit.alice_attrs()

    {:ok, introduced} =
      ConcreteRuntime.Workspaces.introduce_user(helen, %{
        username: alice.username,
        public_key: alice.public_key
      })

    {:ok, secret} =
      ConcreteRuntime.InfoObjects.create(helen, "secret to Helen only",
        label: "secret",
        read_list: [helen],
        write_list: [helen],
        links: [%{did: ConcreteRuntime.Bootstrap.cot_index()["g_did"], cid: nil}]
      )

    :ok =
      ConcreteRuntime.InfoObjects.add_link(
        helen,
        ConcreteRuntime.Bootstrap.cot_index()["g_did"],
        secret.did,
        nil
      )

    :ok = ConcreteRuntime.Workspaces.logout(helen)

    {:ok, _} =
      ConcreteRuntime.Workspaces.login(%{
        username: "Alice",
        pin: introduced.pin,
        private_key: alice.private_key
      })

    {:ok, graph} = ConcreteRuntime.Discovery.walk(alice.public_key)
    dids = Enum.map(graph.nodes, & &1.did)
    refute secret.did in dids
  end

  test "power off refuses product routes", %{helen: helen} do
    assert :ok = ConcreteRuntime.Lab.set_powered(false)
    refute ConcreteRuntime.Lab.powered?()
    refute ConcreteRuntime.Vault.usable?(helen)

    conn =
      Plug.Test.conn(:get, "/v1/bootstrap")
      |> ConcreteRuntime.API.call([])

    assert conn.status == 503

    conn_lab =
      Plug.Test.conn(:get, "/v1/lab")
      |> ConcreteRuntime.API.call([])

    assert conn_lab.status == 200
  end

  test "caps point at workspace CIDs; layout is read from workspace data", %{
    helen: helen,
    genesis: genesis
  } do
    w1 = Enum.find(genesis.workspaces, &(&1.id == "w1"))
    assert is_binary(w1.data_cid)
    assert String.starts_with?(w1.data_cid, "bafy")
    refute String.starts_with?(w1.data_cid, "did:")

    caps = ConcreteRuntime.Bootstrap.capabilities(helen)
    introduce = Enum.find(caps, &(&1.verb == "introduce-user"))
    assert introduce.workspace_cid == w1.data_cid

    {:ok, ws} = ConcreteRuntime.Workspaces.get(helen, "w1")
    assert ws.data_cid == w1.data_cid
    assert ws.layout["workspace_id"] == "w1"
    assert ws.layout["locked"] == true
  end

  test "W1 rolls back a half-admitted user", %{helen: helen, genesis: genesis} do
    alice = TestKit.alice_attrs()
    before_keys = ConcreteRuntime.DataObjects.record(genesis.d1_did).payload["pubkeys"]
    before_ids = Enum.map(ConcreteRuntime.Bootstrap.status().principals, & &1.id)

    TestKit.Store.succeed_then_fail(0)

    assert {:error, _} =
             ConcreteRuntime.Workspaces.introduce_user(helen, %{
               username: alice.username,
               public_key: alice.public_key
             })

    assert Enum.map(ConcreteRuntime.Bootstrap.status().principals, & &1.id) == before_ids
    assert ConcreteRuntime.DataObjects.record(genesis.d1_did).payload["pubkeys"] == before_keys
    refute ConcreteRuntime.Bootstrap.lookup_principal(alice.public_key)

    assert {:ok, _} =
             ConcreteRuntime.Workspaces.introduce_user(helen, %{
               username: alice.username,
               public_key: alice.public_key
             })
  end

  test "W2 rolls back orphaned info when a Wendy-link write fails", %{helen: helen} do
    alice = TestKit.alice_attrs()

    {:ok, introduced} =
      ConcreteRuntime.Workspaces.introduce_user(helen, %{
        username: alice.username,
        public_key: alice.public_key
      })

    :ok = ConcreteRuntime.Workspaces.logout(helen)

    {:ok, _} =
      ConcreteRuntime.Workspaces.login(%{
        username: "Alice",
        pin: introduced.pin,
        private_key: alice.private_key
      })

    before = ConcreteRuntime.InfoObjects.list(alice.public_key)
    cot = ConcreteRuntime.Bootstrap.cot_index()
    d5_before = ConcreteRuntime.DataObjects.record(cot["d5"][alice.public_key])

    TestKit.Store.succeed_then_fail(3)

    assert {:error, _} =
             ConcreteRuntime.Workspaces.write_info(alice.public_key, %{
               text: "should not stick",
               readers: ["Alice"],
               writers: ["Alice"],
               link_did: cot["g_did"]
             })

    after_list = ConcreteRuntime.InfoObjects.list(alice.public_key)
    assert Enum.map(after_list, & &1.did) == Enum.map(before, & &1.did)

    d5_after = ConcreteRuntime.DataObjects.record(cot["d5"][alice.public_key])
    assert d5_after.links == d5_before.links
  end

  test "info GET/list require a principal and enforce read_list", %{helen: helen} do
    {:ok, secret} =
      ConcreteRuntime.InfoObjects.create(helen, "helen only",
        label: "secret",
        read_list: [helen],
        write_list: [helen]
      )

    conn =
      Plug.Test.conn(:get, "/v1/info_objects")
      |> ConcreteRuntime.API.call([])

    assert conn.status == 400

    alice = TestKit.alice_attrs()

    {:ok, introduced} =
      ConcreteRuntime.Workspaces.introduce_user(helen, %{
        username: alice.username,
        public_key: alice.public_key
      })

    :ok = ConcreteRuntime.Workspaces.logout(helen)

    {:ok, _} =
      ConcreteRuntime.Workspaces.login(%{
        username: "Alice",
        pin: introduced.pin,
        private_key: alice.private_key
      })

    listed = ConcreteRuntime.InfoObjects.list(alice.public_key)
    refute Enum.any?(listed, &(&1.did == secret.did))

    assert {:error, :not_found} = ConcreteRuntime.InfoObjects.get(alice.public_key, secret.did)
    assert {:ok, _} = ConcreteRuntime.InfoObjects.get(helen, secret.did)

    conn_alice =
      Plug.Test.conn(
        :get,
        "/v1/info_object?did=#{URI.encode(secret.did)}&principal_id=#{URI.encode(alice.public_key)}"
      )
      |> ConcreteRuntime.API.call([])

    assert conn_alice.status == 404

    assert {:error, :capability_denied} =
             ConcreteRuntime.InfoObjects.advance(alice.public_key, secret.did, "hijack")

    assert {:error, :vault_unusable} =
             ConcreteRuntime.Workspaces.write_info(helen, %{text: "after exit"})
  end

  test "launcher lists W1/W2; duplicate Alice name is taken", %{helen: helen} do
    assert {:ok, listed} = ConcreteRuntime.Workspaces.list(helen)
    ids = Enum.map(listed, & &1.id)
    assert "w1" in ids
    assert "w2" in ids
    refute Enum.any?(listed, &(&1.id == "w0"))

    alice = TestKit.alice_attrs()

    assert {:ok, _} =
             ConcreteRuntime.Workspaces.introduce_user(helen, %{
               username: alice.username,
               public_key: alice.public_key
             })

    assert {:error, :username_taken} =
             ConcreteRuntime.Workspaces.introduce_user(helen, %{
               username: "Alice",
               public_key: "mldsa87:other-alice"
             })
  end

  test "Alice cannot rewrite D2; D1 payload is members-only; G head follows W1", %{
    helen: helen,
    genesis: genesis
  } do
    alice = TestKit.alice_attrs()

    {:ok, introduced} =
      ConcreteRuntime.Workspaces.introduce_user(helen, %{
        username: alice.username,
        public_key: alice.public_key
      })

    {:ok, g} = ConcreteRuntime.InfoObjects.get(helen, genesis.g_did)
    assert alice.public_key in g.read_list
    assert Enum.any?(g.links, fn l -> l.did == introduced.d5_did end)

    assert {:error, :capability_denied} =
             ConcreteRuntime.DataObjects.add_link(
               alice.public_key,
               genesis.d2_did,
               genesis.g_did,
               nil
             )

    {:ok, d1_stranger} = ConcreteRuntime.DataObjects.get("mldsa87:stranger", genesis.d1_did)
    assert d1_stranger.marker == true

    {:ok, d1_alice} = ConcreteRuntime.DataObjects.get(alice.public_key, genesis.d1_did)
    refute Map.get(d1_alice, :marker, false)
    assert alice.public_key in d1_alice.payload["pubkeys"]

    :ok = ConcreteRuntime.Workspaces.logout(helen)

    {:ok, _} =
      ConcreteRuntime.Workspaces.login(%{
        username: "Alice",
        pin: introduced.pin,
        private_key: alice.private_key
      })

    assert {:error, :capability_denied} =
             ConcreteRuntime.Workspaces.write_info(alice.public_key, %{
               text: "link D2",
               readers: ["Alice"],
               writers: ["Alice"],
               link_did: genesis.d2_did
             })

    assert {:error, :unknown_username} =
             ConcreteRuntime.Workspaces.write_info(alice.public_key, %{
               text: "raw key",
               readers: ["mldsa87:not-in-d3"],
               writers: ["Alice"]
             })
  end
end
