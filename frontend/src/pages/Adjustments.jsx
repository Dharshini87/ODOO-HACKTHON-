import { useEffect, useState } from "react";
import { Plus, ClipboardList } from "lucide-react";
import { api } from "../api";
import Modal from "../components/Modal";

export default function Adjustments() {
  const [adjustments, setAdjustments] = useState([]);
  const [products, setProducts] = useState([]);
  const [locations, setLocations] = useState([]);
  const [modalOpen, setModalOpen] = useState(false);
  const [form, setForm] = useState({ product_id: "", location_id: "", counted_quantity: "", contact: "" });
  const [recordedQty, setRecordedQty] = useState(null);
  const [error, setError] = useState("");

  const load = () => {
    api.getAdjustments().then(setAdjustments);
    api.getProducts().then(setProducts);
    api.getLocations().then((l) => setLocations(l.filter((x) => !x.is_virtual)));
  };
  useEffect(load, []);

  useEffect(() => {
    if (form.product_id && form.location_id) {
      api.getStock(Number(form.location_id)).then((rows) => {
        const row = rows.find((r) => r.product_id === Number(form.product_id));
        setRecordedQty(row ? row.on_hand : 0);
      });
    } else {
      setRecordedQty(null);
    }
  }, [form.product_id, form.location_id]);

  const openCreate = () => {
    setForm({ product_id: "", location_id: "", counted_quantity: "", contact: "" });
    setError("");
    setModalOpen(true);
  };

  const submit = async (e) => {
    e.preventDefault();
    setError("");
    try {
      await api.createAdjustment({
        product_id: Number(form.product_id),
        location_id: Number(form.location_id),
        counted_quantity: Number(form.counted_quantity),
        contact: form.contact || "Stock Count",
      });
      setModalOpen(false);
      load();
    } catch (err) {
      setError(err.message);
    }
  };

  const diff = recordedQty !== null && form.counted_quantity !== "" ? Number(form.counted_quantity) - recordedQty : null;

  return (
    <div>
      <div className="flex items-center justify-between mb-8">
        <div>
          <h1 className="font-display font-bold text-2xl">Stock Adjustments</h1>
          <p className="text-ink/60 text-sm mt-1">Reconcile a physical count against the ledger</p>
        </div>
        <button onClick={openCreate} className="flex items-center gap-2 bg-brand hover:bg-brand-dark text-white px-4 py-2.5 rounded-lg text-sm font-medium transition-colors">
          <Plus size={16} /> New adjustment
        </button>
      </div>

      <div className="bg-panel border border-line rounded-xl overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-canvas text-left text-ink/60 text-xs uppercase tracking-wide">
              <th className="px-5 py-3 font-medium">Reference</th>
              <th className="px-5 py-3 font-medium">Product</th>
              <th className="px-5 py-3 font-medium">Location</th>
              <th className="px-5 py-3 font-medium">Reason</th>
              <th className="px-5 py-3 font-medium text-right">Change</th>
            </tr>
          </thead>
          <tbody>
            {adjustments.map((a) => {
              const isIncrease = a.from_location_name === "Inventory Adjustment";
              const location = isIncrease ? a.to_location_name : a.from_location_name;
              return (
                <tr key={a.id} className="border-t border-line">
                  <td className="px-5 py-3 font-mono text-xs">{a.reference}</td>
                  <td className="px-5 py-3">{a.product_name}</td>
                  <td className="px-5 py-3 text-ink/60">{location}</td>
                  <td className="px-5 py-3 text-ink/60">{a.contact || "—"}</td>
                  <td className={`px-5 py-3 text-right font-medium ${isIncrease ? "text-status-done ledger-plus" : "text-status-cancelled ledger-minus"}`}>
                    {a.quantity}
                  </td>
                </tr>
              );
            })}
            {adjustments.length === 0 && (
              <tr><td colSpan={5} className="px-5 py-10 text-center text-ink/40">No adjustments logged yet.</td></tr>
            )}
          </tbody>
        </table>
      </div>

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title="New stock adjustment">
        {error && <div className="mb-4 text-status-cancelled text-sm">{error}</div>}
        <form onSubmit={submit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-ink/80 mb-1.5">Product</label>
            <select required value={form.product_id} onChange={(e) => setForm({ ...form, product_id: e.target.value })}
              className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm">
              <option value="">Select product</option>
              {products.map((p) => <option key={p.id} value={p.id}>{p.name} ({p.sku})</option>)}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-ink/80 mb-1.5">Location</label>
            <select required value={form.location_id} onChange={(e) => setForm({ ...form, location_id: e.target.value })}
              className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm">
              <option value="">Select location</option>
              {locations.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
            </select>
          </div>

          {recordedQty !== null && (
            <div className="flex items-center gap-2 px-3.5 py-2.5 rounded-lg bg-canvas border border-line text-sm">
              <ClipboardList size={15} className="text-ink/50" />
              Recorded stock at this location: <span className="font-medium">{recordedQty}</span>
            </div>
          )}

          <div>
            <label className="block text-sm font-medium text-ink/80 mb-1.5">Counted quantity</label>
            <input type="number" step="0.01" required value={form.counted_quantity} onChange={(e) => setForm({ ...form, counted_quantity: e.target.value })}
              className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm" />
            {diff !== null && diff !== 0 && (
              <div className={`text-xs mt-1.5 font-medium ${diff > 0 ? "text-status-done" : "text-status-cancelled"}`}>
                This will log a {diff > 0 ? "+" : ""}{diff} adjustment
              </div>
            )}
          </div>
          <div>
            <label className="block text-sm font-medium text-ink/80 mb-1.5">Reason</label>
            <input value={form.contact} onChange={(e) => setForm({ ...form, contact: e.target.value })}
              className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm" placeholder="Damaged in transit, cycle count, etc." />
          </div>
          <button type="submit" className="w-full bg-brand hover:bg-brand-dark text-white font-medium py-2.5 rounded-lg transition-colors">
            Log adjustment
          </button>
        </form>
      </Modal>
    </div>
  );
}
