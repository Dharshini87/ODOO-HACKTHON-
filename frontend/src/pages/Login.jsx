import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { useAuth } from "../AuthContext";

export default function Login() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState("manager@stocksense.com");
  const [password, setPassword] = useState("password123");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await login(email, password);
      navigate("/dashboard");
    } catch (err) {
      setError(err.message || "Login failed");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-canvas px-4">
      <div className="w-full max-w-md">
        <div className="text-center mb-8">
          <div className="font-display font-bold text-3xl text-brand tracking-tight">StockSense</div>
          <p className="text-ink/60 mt-2 text-sm">Ledger-based inventory management</p>
        </div>

        <div className="bg-panel border border-line rounded-xl shadow-sm p-8">
          <h1 className="font-display font-semibold text-xl mb-6">Log in</h1>

          {error && (
            <div className="mb-4 px-4 py-3 rounded-lg bg-status-cancelled/10 border border-status-cancelled/30 text-status-cancelled text-sm">
              {error}
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-ink/80 mb-1.5">Login ID / Email</label>
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="w-full px-3.5 py-2.5 rounded-lg border border-line bg-white focus:outline-none focus:ring-2 focus:ring-brand/40 focus:border-brand text-sm"
                placeholder="you@company.com"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-ink/80 mb-1.5">Password</label>
              <input
                type="password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full px-3.5 py-2.5 rounded-lg border border-line bg-white focus:outline-none focus:ring-2 focus:ring-brand/40 focus:border-brand text-sm"
                placeholder="••••••••"
              />
            </div>

            <div className="flex justify-end">
              <Link to="/forgot-password" className="text-sm text-brand hover:underline">
                Forgot password?
              </Link>
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full bg-brand hover:bg-brand-dark text-white font-medium py-2.5 rounded-lg transition-colors disabled:opacity-60"
            >
              {loading ? "Signing in..." : "Sign in"}
            </button>
          </form>

          <p className="text-center text-sm text-ink/60 mt-6">
            New here?{" "}
            <Link to="/signup" className="text-brand font-medium hover:underline">
              Create an account
            </Link>
          </p>
        </div>

        <p className="text-center text-xs text-ink/40 mt-6">
          Demo login is pre-filled: manager@stocksense.com / password123
        </p>
      </div>
    </div>
  );
}
