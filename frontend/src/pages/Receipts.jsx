import { useEffect, useState } from "react";
import { Plus, Check, X } from "lucide-react";
import { api } from "../api";
import Modal from "../components/Modal";
import StatusBadge from "../components/StatusBadge";

export default function Receipts() {
  const [receipts, setReceipts] = useState([]);
  const [products, setProducts] = useState([]);
  const [locations, setLocations] = useState([]);
  const [modalOpen, setModalOpen] = useState(false);
  const [form, setForm] = useState({ product_id: "", to_location_id: "", quantity: "", contact: "" });
  const [error, setError] = useState("");
  const [actionError, setActionError] = useState("");

  const load = () => {
    api.getReceipts().then(setReceipts);
    api.getProducts().then(setProducts);
    api.getLocations().then((l) => setLocations(l.filter((x) => !x.is_virtual)));
  };
  useEffect(load, []);

  const openCreate = () => {
    setForm({ product_id: "", to_location_id: "", quantity: "", contact: "" });
    setError("");
    setModalOpen(true);
  };

  const submit = async (e) => {
    e.preventDefault();
    setError("");
    try {
      await api.createReceipt({
        product_id: Number(form.product_id),
        to_location_id: Number(form.to_location_id),
        quantity: Number(form.quantity),
        contact: form.contact,
      });
      setModalOpen(false);
      load();
    } catch (err) {
      setError(err.message);
    }
  };

  const validate = async (id) => {
    setActionError("");
    try {
      await api.validateReceipt(id);
      load();
    } catch (err) {
      setActionError(err.message);
    }
  };

  const cancel = async (id) => {
    setActionError("");
    try {
      await api.cancelReceipt(id);
      load();
    } catch (err) {
      setActionError(err.message);
    }
  };

  return (
    <div>
      <div className="flex items-center justify-between mb-8">
        <div>
          <h1 className="font-display font-bold text-2xl">Receipts</h1>
          <p className="text-ink/60 text-sm mt-1">Incoming stock — validate to increase inventory</p>
        </div>
        <button onClick={openCreate} className="flex items-center gap-2 bg-brand hover:bg-brand-dark text-white px-4 py-2.5 rounded-lg text-sm font-medium transition-colors">
          <Plus size={16} /> New receipt
        </button>
      </div>

      {actionError && (
        <div className="mb-4 px-4 py-3 rounded-lg bg-status-cancelled/10 border border-status-cancelled/30 text-status-cancelled text-sm">
          {actionError}
        </div>
      )}

      <div className="bg-panel border border-line rounded-xl overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-canvas text-left text-ink/60 text-xs uppercase tracking-wide">
              <th className="px-5 py-3 font-medium">Reference</th>
              <th className="px-5 py-3 font-medium">Product</th>
              <th className="px-5 py-3 font-medium">From</th>
              <th className="px-5 py-3 font-medium">To</th>
              <th className="px-5 py-3 font-medium">Contact</th>
              <th className="px-5 py-3 font-medium text-right">Qty</th>
              <th className="px-5 py-3 font-medium">Status</th>
              <th className="px-5 py-3 font-medium"></th>
            </tr>
          </thead>
          <tbody>
            {receipts.map((r) => (
              <tr key={r.id} className="border-t border-line">
                <td className="px-5 py-3 font-mono text-xs">{r.reference}</td>
                <td className="px-5 py-3">{r.product_name}</td>
                <td className="px-5 py-3 text-ink/60">{r.from_location_name}</td>
                <td className="px-5 py-3 text-ink/60">{r.to_location_name}</td>
                <td className="px-5 py-3 text-ink/60">{r.contact || "—"}</td>
                <td className="px-5 py-3 text-right ledger-plus text-status-done font-medium">{r.quantity}</td>
                <td className="px-5 py-3"><StatusBadge status={r.status} /></td>
                <td className="px-5 py-3">
                  {r.status === "draft" && (
                    <div className="flex items-center gap-2 justify-end">
                      <button onClick={() => validate(r.id)} className="p-1.5 rounded-md hover:bg-status-done/10 text-status-done" title="Validate">
                        <Check size={16} />
                      </button>
                      <button onClick={() => cancel(r.id)} className="p-1.5 rounded-md hover:bg-status-cancelled/10 text-status-cancelled" title="Cancel">
                        <X size={16} />
                      </button>
                    </div>
                  )}
                </td>
              </tr>
            ))}
            {receipts.length === 0 && (
              <tr><td colSpan={8} className="px-5 py-10 text-center text-ink/40">No receipts yet.</td></tr>
            )}
          </tbody>
        </table>
      </div>

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title="New receipt">
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
            <label className="block text-sm font-medium text-ink/80 mb-1.5">Destination location</label>
            <select required value={form.to_location_id} onChange={(e) => setForm({ ...form, to_location_id: e.target.value })}
              className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm">
              <option value="">Select location</option>
              {locations.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-ink/80 mb-1.5">Vendor / contact</label>
            <input value={form.contact} onChange={(e) => setForm({ ...form, contact: e.target.value })}
              className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm" placeholder="Production Batch #204" />
          </div>
          <div>
            <label className="block text-sm font-medium text-ink/80 mb-1.5">Quantity</label>
            <input type="number" min="0.01" step="0.01" required value={form.quantity} onChange={(e) => setForm({ ...form, quantity: e.target.value })}
              className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm" />
          </div>
          <button type="submit" className="w-full bg-brand hover:bg-brand-dark text-white font-medium py-2.5 rounded-lg transition-colors">
            Create receipt
          </button>
        </form>
      </Modal>
    </div>
  );
}
