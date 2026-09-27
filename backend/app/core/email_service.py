"""
StockSense Email Service — password-reset OTP delivery.

Configuration (all via environment variables, never hard-coded):
  SMTP_HOST         SMTP server hostname (e.g., smtp.gmail.com)
  SMTP_PORT         SMTP server port (default 587 for STARTTLS)
  SMTP_USERNAME     Login username / sender address
  SMTP_PASSWORD     Login password or app-specific password
  SMTP_FROM         Display name + address, e.g. "StockSense <no-reply@example.com>"
  SMTP_USE_TLS      "1" to use STARTTLS (default), "0" to use SSL on port
  SMTP_USE_SSL      "1" to use SMTP_SSL wrapper instead of STARTTLS

Security rules:
- OTP plaintext is accepted only as a parameter; it is NEVER stored or logged here.
- The log line uses a masked token (first 2 digits + ****).
- If SMTP is unconfigured, an EmailConfigurationError is raised immediately
  so callers know the email was NOT delivered (no silent failures).
"""
import logging
import os
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Optional

logger = logging.getLogger(__name__)


class EmailConfigurationError(Exception):
    """Raised when required SMTP environment variables are absent."""


class EmailDeliveryError(Exception):
    """Raised when the email could not be delivered."""


def _get_smtp_config() -> dict:
    host = os.getenv("SMTP_HOST", "").strip()
    port_raw = os.getenv("SMTP_PORT", "587").strip()
    username = os.getenv("SMTP_USERNAME", "").strip()
    password = os.getenv("SMTP_PASSWORD", "").strip()
    from_addr = os.getenv(
        "SMTP_FROM", username or "StockSense <no-reply@stocksense.local>"
    ).strip()

    missing = []
    if not host:
        missing.append("SMTP_HOST")
    if not username:
        missing.append("SMTP_USERNAME")
    if not password:
        missing.append("SMTP_PASSWORD")

    if missing:
        raise EmailConfigurationError(
            f"SMTP is not configured. Missing environment variables: {', '.join(missing)}. "
            "Set them before enabling email delivery."
        )

    try:
        port = int(port_raw)
    except ValueError:
        port = 587

    use_ssl = os.getenv("SMTP_USE_SSL", "0").strip() == "1"
    use_tls = os.getenv("SMTP_USE_TLS", "1").strip() == "1" and not use_ssl

    return {
        "host": host,
        "port": port,
        "username": username,
        "password": password,
        "from_addr": from_addr,
        "use_ssl": use_ssl,
        "use_tls": use_tls,
    }


def _build_otp_email(to_email: str, otp_plaintext: str) -> MIMEMultipart:
    """
    Build the password-reset email.
    The OTP plaintext is embedded in the email body but NEVER logged.
    """
    msg = MIMEMultipart("alternative")
    msg["Subject"] = "StockSense — Password Reset OTP"
    msg["To"] = to_email

    # Plain-text version
    plain = (
        f"StockSense — Password Reset\n\n"
        f"Your one-time password (OTP) is: {otp_plaintext}\n\n"
        f"This OTP expires in 10 minutes.\n\n"
        f"If you did not request a password reset, please ignore this message "
        f"and your account will remain secure.\n\n"
        f"— The StockSense Team"
    )

    # HTML version
    html = f"""<!DOCTYPE html>
<html>
<body style="font-family: Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 24px;">
  <div style="background:#0f2027; border-radius:12px; padding:28px; text-align:center;">
    <h2 style="color:#2ec4b6; margin:0 0 4px;">StockSense</h2>
    <p style="color:#8fa3b1; font-size:13px; margin:0;">Inventory Management</p>
  </div>
  <div style="padding:28px 0; border-bottom:1px solid #e8ecef;">
    <h3 style="color:#1a2e3b; margin:0 0 12px;">Password Reset Request</h3>
    <p style="color:#4a5568; margin:0 0 20px;">
      Use the OTP below to reset your StockSense password.
    </p>
    <div style="background:#f0fdfb; border:2px solid #2ec4b6; border-radius:8px;
                padding:18px; text-align:center; letter-spacing:8px;
                font-size:32px; font-weight:bold; color:#0f2027;">
      {otp_plaintext}
    </div>
    <p style="color:#718096; font-size:13px; margin:16px 0 0;">
      ⏱ This OTP expires in <strong>10 minutes</strong>.
    </p>
  </div>
  <p style="color:#a0aec0; font-size:12px; margin:20px 0 0;">
    If you did not request a password reset, ignore this email — your account is safe.
  </p>
</body>
</html>"""

    msg.attach(MIMEText(plain, "plain"))
    msg.attach(MIMEText(html, "html"))
    return msg


def send_password_reset_otp(to_email: str, otp_plaintext: str) -> None:
    """
    Send the password-reset OTP to `to_email`.

    Raises:
        EmailConfigurationError: if SMTP env vars are not set.
        EmailDeliveryError: if the SMTP send fails.

    Security:
        - The OTP is embedded in the email body only.
        - Only a masked token (first 2 chars + ****) is logged.
        - Plaintext OTP is never written to any log output.
    """
    cfg = _get_smtp_config()  # raises EmailConfigurationError if unconfigured

    masked = otp_plaintext[:2] + "****"
    logger.info("Sending password-reset OTP [%s] to %s", masked, to_email)

    msg = _build_otp_email(to_email, otp_plaintext)
    msg["From"] = cfg["from_addr"]

    try:
        if cfg["use_ssl"]:
            with smtplib.SMTP_SSL(cfg["host"], cfg["port"]) as server:
                server.login(cfg["username"], cfg["password"])
                server.sendmail(cfg["from_addr"], [to_email], msg.as_string())
        else:
            with smtplib.SMTP(cfg["host"], cfg["port"]) as server:
                if cfg["use_tls"]:
                    server.starttls()
                server.login(cfg["username"], cfg["password"])
                server.sendmail(cfg["from_addr"], [to_email], msg.as_string())

        logger.info("Password-reset OTP delivered to %s", to_email)

    except smtplib.SMTPException as exc:
        logger.error("SMTP error delivering OTP to %s: %s", to_email, exc)
        raise EmailDeliveryError(
            f"Failed to deliver password-reset email: {exc}"
        ) from exc


def is_email_configured() -> bool:
    """Return True only when all required SMTP env vars are present."""
    try:
        _get_smtp_config()
        return True
    except EmailConfigurationError:
        return False
