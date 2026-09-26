import { useEffect, useState } from "react";
import { Search } from "lucide-react";
import { api } from "../api";
import StatusBadge from "../components/StatusBadge";

const TYPE_LABELS = {
  receipt: "Receipt",
  delivery: "Delivery",
  transfer: "Transfer",
  adjustment: "Adjustment",
};

export default function MoveHistory() {
  const [moves, setMoves] = useState([]);
  const [search, setSearch] = useState("");
  const [typeFilter, setTypeFilter] = useState("");
  const [statusFilter, setStatusFilter] = useState("");

  const load = () => {
    const params = {};
    if (typeFilter) params.move_type = typeFilter;
    if (statusFilter) params.status = statusFilter;
    if (search) params.search = search;
    api.getMoveHistory(params).then(setMoves);
  };

  useEffect(() => {
    const t = setTimeout(load, 250); // debounce search
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search, typeFilter, statusFilter]);

  const isIncoming = (m) => m.move_type === "receipt" || (m.move_type === "adjustment" && m.from_location_name === "Inventory Adjustment");

  return (
    <div>
      <div className="mb-8">
        <h1 className="font-display font-bold text-2xl">Move History</h1>
        <p className="text-ink/60 text-sm mt-1">The complete stock ledger — every transaction, permanently logged</p>
      </div>

      <div className="flex flex-wrap gap-3 mb-5">
        <div className="relative flex-1 min-w-[220px]">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-ink/40" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search by reference or contact..."
            className="w-full pl-9 pr-3.5 py-2.5 rounded-lg border border-line bg-panel text-sm"
          />
        </div>
        <select value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)} className="px-3.5 py-2.5 rounded-lg border border-line bg-panel text-sm">
          <option value="">All types</option>
          <option value="receipt">Receipt</option>
          <option value="delivery">Delivery</option>
          <option value="transfer">Transfer</option>
          <option value="adjustment">Adjustment</option>
        </select>
        <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} className="px-3.5 py-2.5 rounded-lg border border-line bg-panel text-sm">
          <option value="">All statuses</option>
          <option value="draft">Draft</option>
          <option value="waiting">Waiting</option>
          <option value="ready">Ready</option>
          <option value="done">Done</option>
          <option value="cancelled">Cancelled</option>
        </select>
      </div>

      <div className="bg-panel border border-line rounded-xl overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-canvas text-left text-ink/60 text-xs uppercase tracking-wide">
              <th className="px-5 py-3 font-medium">Reference</th>
              <th className="px-5 py-3 font-medium">Type</th>
              <th className="px-5 py-3 font-medium">Product</th>
              <th className="px-5 py-3 font-medium">From</th>
              <th className="px-5 py-3 font-medium">To</th>
              <th className="px-5 py-3 font-medium text-right">Qty</th>
              <th className="px-5 py-3 font-medium">Status</th>
              <th className="px-5 py-3 font-medium">Date</th>
            </tr>
          </thead>
          <tbody>
            {moves.map((m) => (
              <tr key={m.id} className="border-t border-line">
                <td className="px-5 py-3 font-mono text-xs">{m.reference}</td>
                <td className="px-5 py-3 text-ink/70">{TYPE_LABELS[m.move_type]}</td>
                <td className="px-5 py-3">{m.product_name}</td>
                <td className="px-5 py-3 text-ink/60">{m.from_location_name}</td>
                <td className="px-5 py-3 text-ink/60">{m.to_location_name}</td>
                <td className={`px-5 py-3 text-right font-medium ${isIncoming(m) ? "text-status-done ledger-plus" : "text-status-cancelled ledger-minus"}`}>
                  {m.quantity}
                </td>
                <td className="px-5 py-3"><StatusBadge status={m.status} /></td>
                <td className="px-5 py-3 text-ink/50 text-xs">
                  {new Date(m.done_at || m.created_at).toLocaleString()}
                </td>
              </tr>
            ))}
            {moves.length === 0 && (
              <tr><td colSpan={8} className="px-5 py-10 text-center text-ink/40">No moves match your filters.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
