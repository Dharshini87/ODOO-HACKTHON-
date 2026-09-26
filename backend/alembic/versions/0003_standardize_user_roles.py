"""0003_standardize_user_roles

Revision ID: 0003_standardize_user_roles
Revises: 0002_receipt_documents
Create Date: 2026-09-26 23:15:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision: str = '0003_standardize_user_roles'
down_revision: Union[str, Sequence[str], None] = '0002_receipt_documents'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    insp = inspect(bind)
    columns = [c['name'] for c in insp.get_columns('users')]

    # 1. If role column does not exist, add it through safe migration
    if 'role' not in columns:
        op.add_column(
            'users',
            sa.Column('role', sa.String(length=50), nullable=False, server_default='WAREHOUSE_STAFF')
        )
    else:
        # 2. Standardize existing data safely without guessing or deleting
        bind.execute(
            sa.text("UPDATE users SET role = 'WAREHOUSE_STAFF' WHERE LOWER(role) = 'staff' OR role IS NULL OR role = ''")
        )
        bind.execute(
            sa.text("UPDATE users SET role = 'INVENTORY_MANAGER' WHERE LOWER(role) = 'manager'")
        )

        # 3. Update server_default to WAREHOUSE_STAFF
        if bind.dialect.name == 'postgresql':
            op.alter_column('users', 'role', server_default='WAREHOUSE_STAFF')
            # Add role check constraint if it does not already exist
            existing_constraints = [c['name'] for c in insp.get_check_constraints('users')]
            if 'chk_user_roles' not in existing_constraints:
                op.create_check_constraint(
                    'chk_user_roles',
                    'users',
                    "role IN ('WAREHOUSE_STAFF', 'INVENTORY_MANAGER')"
                )


def downgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name == 'postgresql':
        insp = inspect(bind)
        existing_constraints = [c['name'] for c in insp.get_check_constraints('users')]
        if 'chk_user_roles' in existing_constraints:
            op.drop_constraint('chk_user_roles', 'users', type_='check')
        op.alter_column('users', 'role', server_default='staff')
