import { NavLink, useNavigate } from "react-router-dom";
import {
  LayoutDashboard, Package, Warehouse, ArrowDownToLine, ArrowUpFromLine,
  ArrowLeftRight, ClipboardList, History, Settings, LogOut, Boxes
} from "lucide-react";
import { useAuth } from "../AuthContext";

const NAV = [
  { to: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { to: "/products", label: "Products", icon: Package },
  { to: "/stock", label: "Stock", icon: Boxes },
  { to: "/receipts", label: "Receipts", icon: ArrowDownToLine },
  { to: "/deliveries", label: "Delivery", icon: ArrowUpFromLine },
  { to: "/transfers", label: "Transfers", icon: ArrowLeftRight },
  { to: "/adjustments", label: "Adjustments", icon: ClipboardList },
  { to: "/move-history", label: "Move History", icon: History },
  { to: "/warehouses", label: "Settings", icon: Settings },
];

export default function AppShell({ children }) {
  const { user, logout } = useAuth();
  const navigate = useNavigate();

  const handleLogout = () => {
    logout();
    navigate("/login");
  };

  return (
    <div className="flex h-screen bg-canvas">
      <aside className="w-64 bg-charcoal text-canvas flex flex-col shrink-0">
        <div className="px-6 py-5 border-b border-white/10">
          <div className="font-display font-bold text-xl tracking-tight text-white">StockSense</div>
          <div className="text-xs text-white/50 mt-0.5">Ledger-based Inventory</div>
        </div>

        <nav className="flex-1 px-3 py-4 space-y-1 overflow-y-auto">
          {NAV.map(({ to, label, icon: Icon }) => (
            <NavLink
              key={to}
              to={to}
              className={({ isActive }) =>
                `flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors ${
                  isActive
                    ? "bg-brand text-white"
                    : "text-white/70 hover:bg-white/10 hover:text-white"
                }`
              }
            >
              <Icon size={18} />
              {label}
            </NavLink>
          ))}
        </nav>

        <div className="px-3 py-4 border-t border-white/10">
          <div className="px-3 py-2 mb-1">
            <div className="text-sm font-medium text-white truncate">{user?.name}</div>
            <div className="text-xs text-white/50 capitalize">{user?.role}</div>
          </div>
          <button
            onClick={handleLogout}
            className="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium text-white/70 hover:bg-white/10 hover:text-white transition-colors"
          >
            <LogOut size={18} />
            Log out
          </button>
        </div>
      </aside>

      <main className="flex-1 overflow-y-auto">
        <div className="max-w-6xl mx-auto px-8 py-8">{children}</div>
      </main>
    </div>
  );
}
