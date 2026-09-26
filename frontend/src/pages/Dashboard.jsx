import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { Package, AlertTriangle, XCircle, ArrowDownToLine, ArrowUpFromLine, ArrowLeftRight } from "lucide-react";
import { api } from "../api";

function Tile({ icon: Icon, label, value, tone = "brand", to }) {
  const toneClasses = {
    brand: "bg-brand/10 text-brand",
    amber: "bg-amber/15 text-amber",
    danger: "bg-status-cancelled/10 text-status-cancelled",
  };
  const content = (
    <div className="bg-panel border border-line rounded-xl p-5 flex items-center gap-4 hover:shadow-sm transition-shadow">
      <div className={`w-11 h-11 rounded-lg flex items-center justify-center shrink-0 ${toneClasses[tone]}`}>
        <Icon size={20} />
      </div>
      <div>
        <div className="font-display font-bold text-2xl leading-none">{value}</div>
        <div className="text-sm text-ink/60 mt-1">{label}</div>
      </div>
    </div>
  );
  return to ? <Link to={to}>{content}</Link> : content;
}

export default function Dashboard() {
  const [data, setData] = useState(null);
  const [error, setError] = useState("");

  useEffect(() => {
    api.getDashboard().then(setData).catch((e) => setError(e.message));
  }, []);

  return (
    <div>
      <div className="mb-8">
        <h1 className="font-display font-bold text-2xl">Dashboard</h1>
        <p className="text-ink/60 text-sm mt-1">Real-time snapshot of inventory operations</p>
      </div>

      {error && <div className="text-status-cancelled text-sm mb-4">{error}</div>}

      {data && (
        <>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 mb-8">
            <Tile icon={Package} label="Total Products" value={data.total_products} to="/products" />
            <Tile icon={AlertTriangle} label="Low Stock Alerts" value={data.low_stock_count} tone="amber" to="/stock" />
            <Tile icon={XCircle} label="Out of Stock" value={data.out_of_stock_count} tone="danger" to="/stock" />
            <Tile icon={ArrowDownToLine} label="Pending Receipts" value={data.pending_receipts} to="/receipts" />
            <Tile icon={ArrowUpFromLine} label="Pending Deliveries" value={data.pending_deliveries} to="/deliveries" />
            <Tile icon={ArrowLeftRight} label="Transfers Scheduled" value={data.transfers_scheduled} to="/transfers" />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <Link to="/receipts" className="bg-charcoal text-white rounded-xl p-6 hover:opacity-95 transition-opacity">
              <ArrowDownToLine size={22} className="mb-3 text-amber" />
              <div className="font-display font-semibold text-lg">Log a Receipt</div>
              <div className="text-white/60 text-sm mt-1">Record incoming stock from a vendor or production line</div>
            </Link>
            <Link to="/deliveries" className="bg-brand text-white rounded-xl p-6 hover:opacity-95 transition-opacity">
              <ArrowUpFromLine size={22} className="mb-3 text-white" />
              <div className="font-display font-semibold text-lg">Log a Delivery</div>
              <div className="text-white/70 text-sm mt-1">Ship stock out to a customer or retail client</div>
            </Link>
          </div>
        </>
      )}
    </div>
  );
}
