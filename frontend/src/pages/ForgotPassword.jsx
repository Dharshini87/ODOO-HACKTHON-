import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { api } from "../api";

export default function ForgotPassword() {
  const navigate = useNavigate();
  const [step, setStep] = useState(1); // 1 = request OTP, 2 = reset with OTP
  const [email, setEmail] = useState("");
  const [otp, setOtp] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [demoOtp, setDemoOtp] = useState("");

  const requestOtp = async (e) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      const res = await api.forgotPassword(email);
      setMessage(res.message);
      if (res.demo_otp) setDemoOtp(res.demo_otp); // hackathon demo only - no real email provider wired up
      setStep(2);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const resetPassword = async (e) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await api.resetPassword({ email, otp_code: otp, new_password: newPassword });
      navigate("/login");
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-canvas px-4">
      <div className="w-full max-w-md">
        <div className="text-center mb-8">
          <div className="font-display font-bold text-3xl text-brand tracking-tight">StockSense</div>
          <p className="text-ink/60 mt-2 text-sm">Reset your password</p>
        </div>

        <div className="bg-panel border border-line rounded-xl shadow-sm p-8">
          {error && (
            <div className="mb-4 px-4 py-3 rounded-lg bg-status-cancelled/10 border border-status-cancelled/30 text-status-cancelled text-sm">
              {error}
            </div>
          )}
          {message && step === 2 && (
            <div className="mb-4 px-4 py-3 rounded-lg bg-status-ready/10 border border-status-ready/30 text-status-ready text-sm">
              {message}
              {demoOtp && (
                <div className="mt-1 font-mono text-xs text-ink/70">
                  Demo mode (no email provider configured) — your OTP is <b>{demoOtp}</b>
                </div>
              )}
            </div>
          )}

          {step === 1 ? (
            <form onSubmit={requestOtp} className="space-y-4">
              <h1 className="font-display font-semibold text-xl mb-2">Forgot password</h1>
              <p className="text-sm text-ink/60 mb-4">Enter your account email and we'll send a one-time code.</p>
              <div>
                <label className="block text-sm font-medium text-ink/80 mb-1.5">Email</label>
                <input
                  type="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="w-full px-3.5 py-2.5 rounded-lg border border-line bg-white focus:outline-none focus:ring-2 focus:ring-brand/40 focus:border-brand text-sm"
                  placeholder="you@company.com"
                />
              </div>
              <button
                type="submit"
                disabled={loading}
                className="w-full bg-brand hover:bg-brand-dark text-white font-medium py-2.5 rounded-lg transition-colors disabled:opacity-60"
              >
                {loading ? "Sending..." : "Send OTP"}
              </button>
            </form>
          ) : (
            <form onSubmit={resetPassword} className="space-y-4">
              <h1 className="font-display font-semibold text-xl mb-2">Enter OTP & new password</h1>
              <div>
                <label className="block text-sm font-medium text-ink/80 mb-1.5">OTP code</label>
                <input
                  required
                  maxLength={6}
                  value={otp}
                  onChange={(e) => setOtp(e.target.value)}
                  className="w-full px-3.5 py-2.5 rounded-lg border border-line bg-white focus:outline-none focus:ring-2 focus:ring-brand/40 focus:border-brand text-sm tracking-widest"
                  placeholder="6-digit code"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-ink/80 mb-1.5">New password</label>
                <input
                  type="password"
                  required
                  minLength={6}
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  className="w-full px-3.5 py-2.5 rounded-lg border border-line bg-white focus:outline-none focus:ring-2 focus:ring-brand/40 focus:border-brand text-sm"
                  placeholder="At least 6 characters"
                />
              </div>
              <button
                type="submit"
                disabled={loading}
                className="w-full bg-brand hover:bg-brand-dark text-white font-medium py-2.5 rounded-lg transition-colors disabled:opacity-60"
              >
                {loading ? "Resetting..." : "Reset password"}
              </button>
            </form>
          )}

          <p className="text-center text-sm text-ink/60 mt-6">
            <Link to="/login" className="text-brand font-medium hover:underline">
              Back to login
            </Link>
          </p>
        </div>
      </div>
    </div>
  );
}
