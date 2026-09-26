import { useEffect, useState } from "react";
import { Plus, Pencil, Trash2 } from "lucide-react";
import { api } from "../api";
import Modal from "../components/Modal";

const emptyForm = { name: "", sku: "", category_id: "", unit_of_measure: "unit", cost_per_unit: 0, reorder_point: 0 };

export default function Products() {
  const [products, setProducts] = useState([]);
  const [categories, setCategories] = useState([]);
  const [modalOpen, setModalOpen] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [form, setForm] = useState(emptyForm);
  const [newCategory, setNewCategory] = useState("");
  const [error, setError] = useState("");

  const load = () => {
    api.getProducts().then(setProducts);
    api.getCategories().then(setCategories);
  };

  useEffect(load, []);

  const openCreate = () => {
    setEditingId(null);
    setForm(emptyForm);
    setError("");
    setModalOpen(true);
  };

  const openEdit = (p) => {
    setEditingId(p.id);
    setForm({
      name: p.name, sku: p.sku, category_id: p.category_id || "",
      unit_of_measure: p.unit_of_measure, cost_per_unit: p.cost_per_unit, reorder_point: p.reorder_point,
    });
    setError("");
    setModalOpen(true);
  };

  const submit = async (e) => {
    e.preventDefault();
    setError("");
    try {
      const payload = {
        ...form,
        category_id: form.category_id ? Number(form.category_id) : null,
        cost_per_unit: Number(form.cost_per_unit),
        reorder_point: Number(form.reorder_point),
      };
      if (editingId) {
        await api.updateProduct(editingId, payload);
      } else {
        await api.createProduct(payload);
      }
      setModalOpen(false);
      load();
    } catch (err) {
      setError(err.message);
    }
  };

  const remove = async (id) => {
    if (!confirm("Delete this product? This cannot be undone.")) return;
    await api.deleteProduct(id);
    load();
  };

  const addCategory = async () => {
    if (!newCategory.trim()) return;
    const cat = await api.createCategory(newCategory.trim());
    setCategories((c) => [...c, cat]);
    setForm((f) => ({ ...f, category_id: cat.id }));
    setNewCategory("");
  };

  const categoryName = (id) => categories.find((c) => c.id === id)?.name || "—";

  return (
    <div>
      <div className="flex items-center justify-between mb-8">
        <div>
          <h1 className="font-display font-bold text-2xl">Products</h1>
          <p className="text-ink/60 text-sm mt-1">Catalog and reorder rules for everything you stock</p>
        </div>
        <button
          onClick={openCreate}
          className="flex items-center gap-2 bg-brand hover:bg-brand-dark text-white px-4 py-2.5 rounded-lg text-sm font-medium transition-colors"
        >
          <Plus size={16} /> New product
        </button>
      </div>

      <div className="bg-panel border border-line rounded-xl overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-canvas text-left text-ink/60 text-xs uppercase tracking-wide">
              <th className="px-5 py-3 font-medium">Name</th>
              <th className="px-5 py-3 font-medium">SKU</th>
              <th className="px-5 py-3 font-medium">Category</th>
              <th className="px-5 py-3 font-medium">UoM</th>
              <th className="px-5 py-3 font-medium text-right">Cost / unit</th>
              <th className="px-5 py-3 font-medium text-right">Reorder point</th>
              <th className="px-5 py-3 font-medium"></th>
            </tr>
          </thead>
          <tbody>
            {products.map((p) => (
              <tr key={p.id} className="border-t border-line">
                <td className="px-5 py-3 font-medium">{p.name}</td>
                <td className="px-5 py-3 text-ink/70 font-mono text-xs">{p.sku}</td>
                <td className="px-5 py-3 text-ink/70">{categoryName(p.category_id)}</td>
                <td className="px-5 py-3 text-ink/70">{p.unit_of_measure}</td>
                <td className="px-5 py-3 text-right">₹{p.cost_per_unit.toFixed(2)}</td>
                <td className="px-5 py-3 text-right">{p.reorder_point}</td>
                <td className="px-5 py-3">
                  <div className="flex items-center gap-2 justify-end">
                    <button onClick={() => openEdit(p)} className="p-1.5 rounded-md hover:bg-canvas text-ink/60 hover:text-brand">
                      <Pencil size={15} />
                    </button>
                    <button onClick={() => remove(p.id)} className="p-1.5 rounded-md hover:bg-canvas text-ink/60 hover:text-status-cancelled">
                      <Trash2 size={15} />
                    </button>
                  </div>
                </td>
              </tr>
            ))}
            {products.length === 0 && (
              <tr>
                <td colSpan={7} className="px-5 py-10 text-center text-ink/40">
                  No products yet. Create your first one to start tracking stock.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editingId ? "Edit product" : "New product"}>
        {error && <div className="mb-4 text-status-cancelled text-sm">{error}</div>}
        <form onSubmit={submit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-ink/80 mb-1.5">Name</label>
            <input required value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })}
              className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm" />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-ink/80 mb-1.5">SKU / Code</label>
              <input required value={form.sku} onChange={(e) => setForm({ ...form, sku: e.target.value })}
                className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm font-mono" />
            </div>
            <div>
              <label className="block text-sm font-medium text-ink/80 mb-1.5">Unit of measure</label>
              <input value={form.unit_of_measure} onChange={(e) => setForm({ ...form, unit_of_measure: e.target.value })}
                className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm" placeholder="box, kg, unit..." />
            </div>
          </div>
          <div>
            <label className="block text-sm font-medium text-ink/80 mb-1.5">Category</label>
            <div className="flex gap-2">
              <select value={form.category_id} onChange={(e) => setForm({ ...form, category_id: e.target.value })}
                className="flex-1 px-3.5 py-2.5 rounded-lg border border-line text-sm">
                <option value="">None</option>
                {categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
              </select>
              <input value={newCategory} onChange={(e) => setNewCategory(e.target.value)} placeholder="Add new..."
                className="w-32 px-3 py-2.5 rounded-lg border border-line text-sm" />
              <button type="button" onClick={addCategory} className="px-3 rounded-lg border border-line text-sm hover:bg-canvas">Add</button>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-ink/80 mb-1.5">Cost per unit (₹)</label>
              <input type="number" step="0.01" min="0" value={form.cost_per_unit} onChange={(e) => setForm({ ...form, cost_per_unit: e.target.value })}
                className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm" />
            </div>
            <div>
              <label className="block text-sm font-medium text-ink/80 mb-1.5">Reorder point</label>
              <input type="number" step="1" min="0" value={form.reorder_point} onChange={(e) => setForm({ ...form, reorder_point: e.target.value })}
                className="w-full px-3.5 py-2.5 rounded-lg border border-line text-sm" />
            </div>
          </div>
          <button type="submit" className="w-full bg-brand hover:bg-brand-dark text-white font-medium py-2.5 rounded-lg transition-colors">
            {editingId ? "Save changes" : "Create product"}
          </button>
        </form>
      </Modal>
    </div>
  );
}
