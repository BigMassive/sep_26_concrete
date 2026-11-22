defmodule ConcreteRuntime.BootstrapTest do
  use ExUnit.Case, async: false

  alias ConcreteRuntime.TestKit

  setup do
    TestKit.put_fakes()
    {:ok, _} = start_supervised(TestKit.Store)
    TestKit.Store.reset()

    dir = TestKit.tmp_dir()
    Enum.each(TestKit.children(dir), &start_supervised!/1)

    on_exit(fn -> TestKit.clear_fakes() end)
    %{dir: dir}
  end

  test "W0 layout previews genesis writes, processes, and locked wires" do
    layout = ConcreteRuntime.Workspaces.w0_layout()
    by_id = Map.new(layout["nodes"], &{&1["id"], &1})

    assert by_id["run"]["type"] == "commit"
    assert length(by_id["run"]["ports"]) == 5
    assert by_id["populate"]["type"] == "populate"
    assert by_id["prompt"]["type"] == "note"
    refute Map.has_key?(by_id, "pt_username")
    refute Map.has_key?(by_id, "pt_pubkey")
    assert by_id["d2"]["type"] == "data"
    assert by_id["d2"]["subtitle"] =~ "will write"
    assert by_id["g"]["type"] == "info"
    assert by_id["vault"]["type"] == "process"
    assert by_id["identity"]["type"] == "process"
    assert by_id["d2"]["y"] - by_id["d1"]["y"] >= 180
    assert ["populate", "username"] in layout["wires"]

    assert %{
             "from" => "username",
             "from_port" => 0,
             "to" => "run",
             "to_port" => 0
           } in layout["wires"]

    assert %{
             "from" => "run",
             "from_port" => 1,
             "to" => "d1",
             "to_port" => 0
           } in layout["wires"]

    assert %{
             "from" => "run",
             "from_port" => 2,
             "to" => "vault",
             "to_port" => 0
           } in layout["wires"]

    assert %{
             "from" => "run",
             "from_port" => 3,
             "to" => "d4",
             "to_port" => 0
           } in layout["wires"]

    assert %{
             "from" => "run",
             "from_port" => 4,
             "to" => "identity",
             "to_port" => 0
           } in layout["wires"]

    refute Enum.any?(layout["wires"], &("prompt" in List.wrap(&1)))
  end

  test "W1 layout previews D1/D3/D4/D5/G and uses a combined commit block" do
    layout = ConcreteRuntime.Workspaces.w1_layout()
    by_id = Map.new(layout["nodes"], &{&1["id"], &1})

    assert by_id["run"]["type"] == "commit"
    assert by_id["populate"]["type"] == "populate"
    assert by_id["d1"]["type"] == "data"
    assert by_id["d5"]["subtitle"] =~ "will write"
    assert by_id["g"]["type"] == "info"
    refute Map.has_key?(by_id, "d2")
  end

  test "W2 layout previews the new info object and D5 auto-link" do
    layout = ConcreteRuntime.Workspaces.w2_layout()
    by_id = Map.new(layout["nodes"], &{&1["id"], &1})

    assert by_id["run"]["type"] == "commit"
    assert by_id["info"]["type"] == "info"
    assert by_id["d5"]["type"] == "data"
    assert by_id["d5"]["subtitle"] =~ "will link"
  end

  test "first boot is an empty CoT — no auto-King" do
    status = ConcreteRuntime.Bootstrap.status()
    assert status.node_id == "node-1"
    assert status.king == nil
    assert status.genesis_complete == false
    assert status.principals == []

    assert {:error, :capability_denied} =
             ConcreteRuntime.Bootstrap.authorize("mldsa87:anyone", "mutate")
  end

  test "genesis rejects a PIN that is not five digits" do
    bad = Map.put(TestKit.helen_attrs(), :pin, "12")
    assert {:error, :pin_invalid} = ConcreteRuntime.Workspaces.genesis(bad)
    letters = Map.put(TestKit.helen_attrs(), :pin, "abcde")
    assert {:error, :pin_invalid} = ConcreteRuntime.Workspaces.genesis(letters)
  end

  test "genesis mints bootstrap cap to Helen and writes this EK on D2" do
    assert {:ok, result} = ConcreteRuntime.Workspaces.genesis(TestKit.helen_attrs())
    assert result.principal.display_name == "Helen"
    assert result.principal.id == "mldsa87:helen-test-pk"
    assert result.ek_public_key =~ "ek:node-1:"

    status = ConcreteRuntime.Bootstrap.status()
    assert status.king.id == "mldsa87:helen-test-pk"
    assert status.bootstrap_capability.holder_principal_id == status.king.id
    assert {:ok, :allowed, _} = ConcreteRuntime.Bootstrap.authorize(status.king.id, "mutate")

    d2 = ConcreteRuntime.DataObjects.record(result.d2_did)
    assert result.ek_public_key in d2.payload["eks"]
    assert ConcreteRuntime.Vault.usable?(status.king.id)
  end

  test "replay genesis fails unless zeroise" do
    assert {:ok, _} = ConcreteRuntime.Workspaces.genesis(TestKit.helen_attrs())
    assert {:error, :genesis_replay} = ConcreteRuntime.Workspaces.genesis(TestKit.helen_attrs())

    assert :ok = ConcreteRuntime.Workspaces.zeroise()
    assert {:ok, again} = ConcreteRuntime.Workspaces.genesis(TestKit.helen_attrs())
    assert again.principal.display_name == "Helen"
  end

  test "state persists across process restart", %{dir: dir} do
    assert {:ok, _} = ConcreteRuntime.Workspaces.genesis(TestKit.helen_attrs())
    king_id = ConcreteRuntime.Bootstrap.status().king.id

    stop_supervised!(ConcreteRuntime.Bootstrap)
    start_supervised!({ConcreteRuntime.Bootstrap, data_dir: dir})

    status2 = ConcreteRuntime.Bootstrap.status()
    assert status2.king.id == king_id
    assert status2.genesis_complete
    assert {:ok, :allowed, _} = ConcreteRuntime.Bootstrap.authorize(king_id, "mutate")
  end

  test "identity process does not start on boot when the node is powered off", %{dir: dir} do
    assert {:ok, _} = ConcreteRuntime.Workspaces.genesis(TestKit.helen_attrs())
    assert ConcreteRuntime.IdentityProcess.running?()

    assert :ok = ConcreteRuntime.Lab.set_powered(false)
    refute ConcreteRuntime.IdentityProcess.running?()

    stop_supervised!(ConcreteRuntime.Workspaces)
    stop_supervised!(ConcreteRuntime.Bootstrap)
    stop_supervised!(ConcreteRuntime.Lab)

    start_supervised!({ConcreteRuntime.Lab, data_dir: dir})
    start_supervised!({ConcreteRuntime.Bootstrap, data_dir: dir})
    start_supervised!({ConcreteRuntime.Workspaces, data_dir: dir})

    refute ConcreteRuntime.Lab.powered?()
    assert ConcreteRuntime.Bootstrap.genesis_complete?()
    refute ConcreteRuntime.IdentityProcess.running?()

    assert :ok = ConcreteRuntime.Lab.set_powered(true)
    assert ConcreteRuntime.IdentityProcess.running?()
  end
end
