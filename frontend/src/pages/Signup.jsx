import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useAuth } from "../AuthContext";

export default function Signup() {
  const { signup } = useAuth();
  const navigate = useNavigate();
  const [form, setForm] = useState({ name: "", email: "", password: "", role: "staff" });
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  const update = (k, v) => setForm((f) => ({ ...f, [k]: v }));

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await signup(form.name, form.email, form.password, form.role);
      navigate("/dashboard");
    } catch (err) {
      setError(err.message || "Signup failed");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-canvas px-4">
      <div className="w-full max-w-md">
        <div className="text-center mb-8">
          <div className="font-display font-bold text-3xl text-brand tracking-tight">StockSense</div>
          <p className="text-ink/60 mt-2 text-sm">Create your account</p>
        </div>

        <div className="bg-panel border border-line rounded-xl shadow-sm p-8">
          <h1 className="font-display font-semibold text-xl mb-6">Sign up</h1>

          {error && (
            <div className="mb-4 px-4 py-3 rounded-lg bg-status-cancelled/10 border border-status-cancelled/30 text-status-cancelled text-sm">
              {error}
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-ink/80 mb-1.5">Full name</label>
              <input
                required
                value={form.name}
                onChange={(e) => update("name", e.target.value)}
                className="w-full px-3.5 py-2.5 rounded-lg border border-line bg-white focus:outline-none focus:ring-2 focus:ring-brand/40 focus:border-brand text-sm"
                placeholder="Asha Verma"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-ink/80 mb-1.5">Email</label>
              <input
                type="email"
                required
                value={form.email}
                onChange={(e) => update("email", e.target.value)}
                className="w-full px-3.5 py-2.5 rounded-lg border border-line bg-white focus:outline-none focus:ring-2 focus:ring-brand/40 focus:border-brand text-sm"
                placeholder="you@company.com"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-ink/80 mb-1.5">Password</label>
              <input
                type="password"
                required
                minLength={6}
                value={form.password}
                onChange={(e) => update("password", e.target.value)}
                className="w-full px-3.5 py-2.5 rounded-lg border border-line bg-white focus:outline-none focus:ring-2 focus:ring-brand/40 focus:border-brand text-sm"
                placeholder="At least 6 characters"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-ink/80 mb-1.5">Role</label>
              <select
                value={form.role}
                onChange={(e) => update("role", e.target.value)}
                className="w-full px-3.5 py-2.5 rounded-lg border border-line bg-white focus:outline-none focus:ring-2 focus:ring-brand/40 focus:border-brand text-sm"
              >
                <option value="staff">Warehouse Staff</option>
                <option value="manager">Inventory Manager</option>
              </select>
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full bg-brand hover:bg-brand-dark text-white font-medium py-2.5 rounded-lg transition-colors disabled:opacity-60"
            >
              {loading ? "Creating account..." : "Create account"}
            </button>
          </form>

          <p className="text-center text-sm text-ink/60 mt-6">
            Already have an account?{" "}
            <Link to="/login" className="text-brand font-medium hover:underline">
              Log in
            </Link>
          </p>
        </div>
      </div>
    </div>
  );
}
