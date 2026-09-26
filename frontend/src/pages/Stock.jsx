import { useEffect, useState } from "react";
import { AlertTriangle } from "lucide-react";
import { api } from "../api";

export default function Stock() {
  const [stock, setStock] = useState([]);

  useEffect(() => {
    api.getStock().then(setStock);
  }, []);

  return (
    <div>
      <div className="mb-8">
        <h1 className="font-display font-bold text-2xl">Stock</h1>
        <p className="text-ink/60 text-sm mt-1">Live, ledger-derived stock levels across all warehouses</p>
      </div>

      <div className="bg-panel border border-line rounded-xl overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-canvas text-left text-ink/60 text-xs uppercase tracking-wide">
              <th className="px-5 py-3 font-medium">Product</th>
              <th className="px-5 py-3 font-medium text-right">Cost / unit</th>
              <th className="px-5 py-3 font-medium text-right">On hand</th>
              <th className="px-5 py-3 font-medium text-right">Free to use</th>
              <th className="px-5 py-3 font-medium text-right">Reorder point</th>
              <th className="px-5 py-3 font-medium"></th>
            </tr>
          </thead>
          <tbody>
            {stock.map((s) => (
              <tr key={s.product_id} className="border-t border-line">
                <td className="px-5 py-3">
                  <div className="font-medium">{s.product_name}</div>
                  <div className="text-xs text-ink/50 font-mono">{s.sku}</div>
                </td>
                <td className="px-5 py-3 text-right">₹{s.cost_per_unit.toFixed(2)}</td>
                <td className="px-5 py-3 text-right font-medium">{s.on_hand}</td>
                <td className="px-5 py-3 text-right">{s.free_to_use}</td>
                <td className="px-5 py-3 text-right text-ink/60">{s.reorder_point}</td>
                <td className="px-5 py-3">
                  {s.low_stock && (
                    <span className="inline-flex items-center gap-1 text-xs font-medium text-status-waiting">
                      <AlertTriangle size={13} /> Low stock
                    </span>
                  )}
                </td>
              </tr>
            ))}
            {stock.length === 0 && (
              <tr><td colSpan={6} className="px-5 py-10 text-center text-ink/40">No products to show stock for yet.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
