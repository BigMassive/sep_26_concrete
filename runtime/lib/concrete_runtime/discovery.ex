defmodule ConcreteRuntime.Discovery do
  @moduledoc """
  Naive OTP walk from D5[user] (and G if linked). Information nodes are
  omitted unless this principal may read them. Data nodes are markers only
  (no D4 bytes). Godot does not scrape IPFS.
  """

  def walk(principal_id) when is_binary(principal_id) do
    with {:ok, _, _} <- ConcreteRuntime.Bootstrap.authorize(principal_id, "discovery") do
      cot = ConcreteRuntime.Bootstrap.cot_index()
      d5_map = cot["d5"] || %{}
      start = d5_map[principal_id] || cot["g_did"]

      if is_binary(start) do
        {:ok, bfs(start, principal_id)}
      else
        {:ok, %{nodes: [], edges: []}}
      end
    end
  end

  defp bfs(start, actor_id) do
    {nodes, edges, _} = do_bfs([start], MapSet.new(), [], [], actor_id)
    %{nodes: nodes, edges: edges}
  end

  defp do_bfs([], _seen, nodes, edges, _actor), do: {nodes, edges, :ok}

  defp do_bfs([did | rest], seen, nodes, edges, actor_id) do
    if MapSet.member?(seen, did) do
      do_bfs(rest, seen, nodes, edges, actor_id)
    else
      seen = MapSet.put(seen, did)

      case describe(did, actor_id) do
        {:skip, links} ->
          next = rest ++ Enum.map(links, & &1.did)
          do_bfs(next, seen, nodes, edges, actor_id)

        {:ok, node, links} ->
          new_edges =
            Enum.map(links, fn l ->
              %{from: did, to: l.did, kind: "wendy-link"}
            end)

          next = rest ++ Enum.map(links, & &1.did)
          do_bfs(next, seen, nodes ++ [node], edges ++ new_edges, actor_id)

        :missing ->
          do_bfs(rest, seen, nodes, edges, actor_id)
      end
    end
  end

  defp describe(did, actor_id) do
    case ConcreteRuntime.DataObjects.record(did) do
      rec when is_map(rec) ->
        {:ok,
         %{
           did: rec.did,
           title: rec.label,
           kind: "data",
           marker: true
         }, rec.links || []}

      _ ->
        case ConcreteRuntime.InfoObjects.index_get(did) do
          nil ->
            :missing

          obj ->
            if info_readable?(obj, actor_id) do
              {:ok,
               %{
                 did: info_did(obj),
                 title: obj.label,
                 kind: "info",
                 marker: false
               }, obj[:links] || Map.get(obj, :links) || []}
            else
              {:skip, []}
            end
        end
    end
  end

  defp info_readable?(obj, actor_id) do
    list = Map.get(obj, :read_list) || []

    cond do
      match?({:ok, _, _}, ConcreteRuntime.Bootstrap.authorize(actor_id, "mutate")) ->
        true

      list == [] ->
        false

      actor_id in list ->
        true

      true ->
        false
    end
  end

  defp info_did(obj) do
    case Map.get(obj, :iota_did) do
      did when is_binary(did) and did != "" -> did
      _ -> obj.did
    end
  end
end
