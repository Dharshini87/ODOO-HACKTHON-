import { useEffect, useState } from "react";
import { Plus, Warehouse as WarehouseIcon, MapPin } from "lucide-react";
import { api } from "../api";
import Modal from "../components/Modal";

export default function Warehouses() {
  const [warehouses, setWarehouses] = useState([]);
  const [locations, setLocations] = useState([]);
  const [whModal, setWhModal] = useState(false);
  const [locModal, setLocModal] = useState(false);
  const [whForm, setWhForm] = useState({ name: "", short_code: "", address: "" });
  const [locForm, setLocForm] = useState({ name: "", short_code: "", warehouse_id: "" });
  const [error, setError] = useState("");

  const load = () => {
    api.getWarehouses().then(setWarehouses);
    api.getLocations().then(setLocations);
  };
  useEffect(load, []);

  const submitWarehouse = async (e) => {
    e.preventDefault();
    setError("");
    try {
      await api.createWarehouse(whForm);
      setWhModal(false);
      setWhForm({ name: "", short_code: "", address: "" });
      load();
    } catch (err) {
      setError(err.message);
    }
  };

  const submitLocation = async (e) => {
    e.preventDefault();
    setError("");
    try {
      await api.createLocation({ ...locForm, warehouse_id: locForm.warehouse_id ? Number(locForm.warehouse_id) : null });
      setLocModal(false);
      setLocForm({ name: "", short_code: "", warehouse_id: "" });
      load();
    } catch (err) {
      setError(err.message);
    }
  };

  const warehouseName = (id) => warehouses.find((w) => w.id === id)?.name || "—";

  return (
    <div>
      <div className="mb-8">
        <h1 className="font-display font-bold text-2xl">Settings</h1>
        <p className="text-ink/60 text-sm mt-1">Manage warehouses and their internal locations</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-panel border border-line rounded-xl overflow-hidden">
          <div className="flex items-center justify-between px-5 py-4 border-b border-line">
            <div className="flex items-center gap-2 font-display font-semibold">
              <WarehouseIcon size={18} className="text-brand" /> Warehouses
            </div>
            <button onClick={() => setWhModal(true)} className="flex items-center gap-1.5 text-sm text-brand font-medium hover:underline">
              <Plus size={15} /> Add
            </button>
          </div>
          <div className="divide-y divide-line">
            {warehouses.map((w) => (
              <div key={w.id} className="px-5 py-3.5">
                <div className="font-medium text-sm">{w.name}</div>
                <div className="text-xs text-ink/50 mt-0.5">
                  <span className="font-mono">{w.short_code}</span>{w.address ? ` · ${w.address}` : ""}
                </div>
              </div>
            ))}
            {warehouses.length === 0 && <div className="px-5 py-8 text-center text-ink/40 text-sm">No warehouses yet</div>}
          </div>
        </div>

        <div className="bg-panel border border-line rounded-xl overflow-hidden">
          <div className="flex items-center justify-between px-5 py-4 border-b border-line">
            <div className="flex items-center gap-2 font-display font-semibold">
              <MapPin size={18} className="text-brand" /> Locations
            </div>
            <button onClick={() => setLocModal(true)} className="flex items-center gap-1.5 text-sm text-brand font-medium hover:underline">
              <Plus size={15} /> Add
            </button>
          </div>
          <div className="divide-y divide-line">
            {locations.filter((l) => !l.is_virtual).map((l) => (
              <div key={l.id} className="px-5 py-3.5">
                <div className="font-medium text-sm">{l.name}</div>
                <div className="text-xs text-ink/50 mt-0.5">
                  <span className="font-mono">{l.short_code}</span> · {warehouseName(l.warehouse_id)}
                </div>
              </div>
            ))}
            {locations.filter((l) => !l.is_virtual).length === 0 && (
              <div className="px-5 py-8 text-center text-ink/40 text-sm">No locations yet</div>
            )}
          </div>
        </div>
      </div>

      <Modal open={whModal} onClose={() => setWhModal(false)} title="New warehouse">
        {error && <div className="mb-4 text-status-cancelled text-sm">{error}</div>}
        <form onSubmit={submitWarehouse} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-ink/80 mb-1.5">Name</label>
            <input required value={whForm.name} onChange={(e) => setWhForm({ ...whForm, name: e.target.value })}
              className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm" placeholder="Main Factory" />
          </div>
          <div>
            <label className="block text-sm font-medium text-ink/80 mb-1.5">Short code</label>
            <input required value={whForm.short_code} onChange={(e) => setWhForm({ ...whForm, short_code: e.target.value.toUpperCase() })}
              className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm font-mono" placeholder="WH" />
          </div>
          <div>
            <label className="block text-sm font-medium text-ink/80 mb-1.5">Address</label>
            <input value={whForm.address} onChange={(e) => setWhForm({ ...whForm, address: e.target.value })}
              className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm" />
          </div>
          <button type="submit" className="w-full bg-brand hover:bg-brand-dark text-white font-medium py-2.5 rounded-lg transition-colors">
            Create warehouse
          </button>
        </form>
      </Modal>

      <Modal open={locModal} onClose={() => setLocModal(false)} title="New location">
        {error && <div className="mb-4 text-status-cancelled text-sm">{error}</div>}
        <form onSubmit={submitLocation} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-ink/80 mb-1.5">Name</label>
            <input required value={locForm.name} onChange={(e) => setLocForm({ ...locForm, name: e.target.value })}
              className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm" placeholder="Stock Room 1" />
          </div>
          <div>
            <label className="block text-sm font-medium text-ink/80 mb-1.5">Short code</label>
            <input required value={locForm.short_code} onChange={(e) => setLocForm({ ...locForm, short_code: e.target.value.toUpperCase() })}
              className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm font-mono" placeholder="STOCK1" />
          </div>
          <div>
            <label className="block text-sm font-medium text-ink/80 mb-1.5">Warehouse</label>
            <select required value={locForm.warehouse_id} onChange={(e) => setLocForm({ ...locForm, warehouse_id: e.target.value })}
              className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm">
              <option value="">Select a warehouse</option>
              {warehouses.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
            </select>
          </div>
          <button type="submit" className="w-full bg-brand hover:bg-brand-dark text-white font-medium py-2.5 rounded-lg transition-colors">
            Create location
          </button>
        </form>
      </Modal>
    </div>
  );
}
