import { Routes, Route, Navigate } from "react-router-dom";
import { AuthProvider, useAuth } from "./AuthContext";
import AppShell from "./components/AppShell";

import Login from "./pages/Login";
import Signup from "./pages/Signup";
import ForgotPassword from "./pages/ForgotPassword";
import Dashboard from "./pages/Dashboard";
import Products from "./pages/Products";
import Warehouses from "./pages/Warehouses";
import Stock from "./pages/Stock";
import Receipts from "./pages/Receipts";
import Deliveries from "./pages/Deliveries";
import Transfers from "./pages/Transfers";
import Adjustments from "./pages/Adjustments";
import MoveHistory from "./pages/MoveHistory";

function ProtectedRoute({ children }) {
  const { user } = useAuth();
  if (!user) return <Navigate to="/login" replace />;
  return <AppShell>{children}</AppShell>;
}

function AppRoutes() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route path="/signup" element={<Signup />} />
      <Route path="/forgot-password" element={<ForgotPassword />} />

      <Route path="/dashboard" element={<ProtectedRoute><Dashboard /></ProtectedRoute>} />
      <Route path="/products" element={<ProtectedRoute><Products /></ProtectedRoute>} />
      <Route path="/warehouses" element={<ProtectedRoute><Warehouses /></ProtectedRoute>} />
      <Route path="/stock" element={<ProtectedRoute><Stock /></ProtectedRoute>} />
      <Route path="/receipts" element={<ProtectedRoute><Receipts /></ProtectedRoute>} />
      <Route path="/deliveries" element={<ProtectedRoute><Deliveries /></ProtectedRoute>} />
      <Route path="/transfers" element={<ProtectedRoute><Transfers /></ProtectedRoute>} />
      <Route path="/adjustments" element={<ProtectedRoute><Adjustments /></ProtectedRoute>} />
      <Route path="/move-history" element={<ProtectedRoute><MoveHistory /></ProtectedRoute>} />

      <Route path="/" element={<Navigate to="/dashboard" replace />} />
      <Route path="*" element={<Navigate to="/dashboard" replace />} />
    </Routes>
  );
}

export default function App() {
  return (
    <AuthProvider>
      <AppRoutes />
    </AuthProvider>
  );
}
