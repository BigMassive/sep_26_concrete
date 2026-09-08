defmodule ConcreteRuntime.BootstrapTest do
  use ExUnit.Case, async: false

  setup do
    dir = Path.join(System.tmp_dir!(), "concrete-bootstrap-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    # Stop app children if running in test — start Bootstrap alone
    start_supervised!({ConcreteRuntime.Bootstrap, data_dir: dir})
    %{dir: dir}
  end

  test "first boot mints bootstrap cap to King" do
    status = ConcreteRuntime.Bootstrap.status()
    assert status.node_id == "node-1"
    assert status.king.display_name == "King"
    assert status.bootstrap_capability.meaning == "bootstrap/do-anything"
    assert status.bootstrap_capability.holder_principal_id == status.king.id

    assert {:ok, :allowed, _} = ConcreteRuntime.Bootstrap.authorize(status.king.id, "mutate")
  end

  test "second principal is denied" do
    {:ok, eve} = ConcreteRuntime.Bootstrap.ensure_principal("Eve")
    assert {:error, :capability_denied} = ConcreteRuntime.Bootstrap.authorize(eve.id, "mutate")
  end

  test "state persists across process restart", %{dir: dir} do
    status1 = ConcreteRuntime.Bootstrap.status()
    king_id = status1.king.id

    stop_supervised!(ConcreteRuntime.Bootstrap)
    start_supervised!({ConcreteRuntime.Bootstrap, data_dir: dir})

    status2 = ConcreteRuntime.Bootstrap.status()
    assert status2.king.id == king_id
    assert {:ok, :allowed, _} = ConcreteRuntime.Bootstrap.authorize(king_id, "mutate")
  end
end
