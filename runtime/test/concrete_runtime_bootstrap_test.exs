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

  test "first boot is an empty CoT — no auto-King" do
    status = ConcreteRuntime.Bootstrap.status()
    assert status.node_id == "node-1"
    assert status.king == nil
    assert status.genesis_complete == false
    assert status.principals == []

    assert {:error, :capability_denied} =
             ConcreteRuntime.Bootstrap.authorize("mldsa87:anyone", "mutate")
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
