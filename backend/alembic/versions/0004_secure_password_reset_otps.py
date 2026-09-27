"""0004_secure_password_reset_otps

Adds a dedicated, security-hardened password_reset_otps table.

Rules enforced in this schema:
- otp_hash: SHA-256 hash of the 6-digit OTP — NEVER plaintext.
- expires_at: 10-minute TTL enforced at application layer.
- attempts: max 5 failed attempts before the record is locked.
- is_used: single-use; set True after a successful reset.
- last_resend_at: enforces 60-second resend cooldown per user.
- A new OTP for the same user invalidates previous unused challenges
  (handled at application layer by marking old records as used).

Revision ID: 0004_secure_password_reset_otps
Revises: 0003_standardize_user_roles
Create Date: 2026-09-27 09:00:00.000000
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = '0004_secure_password_reset_otps'
down_revision: Union[str, Sequence[str], None] = '0003_standardize_user_roles'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'password_reset_otps',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column(
            'user_id',
            sa.Integer(),
            sa.ForeignKey('users.id', ondelete='CASCADE'),
            nullable=False,
            index=True,
        ),
        # SHA-256 hex digest (64 chars) of the plaintext OTP — never store raw OTP
        sa.Column('otp_hash', sa.String(length=64), nullable=False),
        sa.Column(
            'expires_at',
            sa.DateTime(timezone=True),
            nullable=False,
        ),
        # Number of failed verification attempts (max 5)
        sa.Column('attempts', sa.Integer(), nullable=False, server_default='0'),
        # Set to True after a successful reset or when superseded by a new OTP
        sa.Column('is_used', sa.Boolean(), nullable=False, server_default=sa.false()),
        # Timestamp of the last time this user requested a new OTP (resend cooldown)
        sa.Column('last_resend_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            'created_at',
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )

    # Speed up "find newest unused OTP for user" queries
    op.create_index(
        'ix_prot_user_id_is_used_created',
        'password_reset_otps',
        ['user_id', 'is_used', 'created_at'],
    )


def downgrade() -> None:
    op.drop_index('ix_prot_user_id_is_used_created', table_name='password_reset_otps')
    op.drop_table('password_reset_otps')
