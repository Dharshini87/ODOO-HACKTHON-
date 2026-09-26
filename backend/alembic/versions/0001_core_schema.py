"""0001_core_schema

Revision ID: 0001_core_schema
Revises: 
Create Date: 2026-09-26 13:40:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = '0001_core_schema'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. users
    op.create_table(
        'users',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('email', sa.String(length=255), nullable=False, unique=True, index=True),
        sa.Column('password_hash', sa.String(length=255), nullable=False),
        sa.Column('role', sa.String(length=50), nullable=False, server_default='staff'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
        sa.Column('otp_code', sa.String(length=10), nullable=True),
        sa.Column('otp_expiry', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )

    # 2. categories
    op.create_table(
        'categories',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('name', sa.String(length=255), nullable=False, unique=True, index=True),
        sa.Column('description', sa.String(length=500), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )

    # 3. products
    op.create_table(
        'products',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('sku', sa.String(length=100), nullable=False, unique=True, index=True),
        sa.Column('category_id', sa.Integer(), sa.ForeignKey('categories.id', ondelete='RESTRICT'), nullable=True),
        sa.Column('unit_of_measure', sa.String(length=50), nullable=False, server_default='unit'),
        sa.Column('cost_per_unit', sa.Numeric(precision=12, scale=2), nullable=False, server_default='0.00'),
        sa.Column('reorder_point', sa.Numeric(precision=12, scale=3), nullable=False, server_default='0.000'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )

    # 4. warehouses
    op.create_table(
        'warehouses',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('short_code', sa.String(length=50), nullable=False, unique=True, index=True),
        sa.Column('address', sa.String(length=500), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )

    # 5. locations
    op.create_table(
        'locations',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('short_code', sa.String(length=50), nullable=False, index=True),
        sa.Column('warehouse_id', sa.Integer(), sa.ForeignKey('warehouses.id', ondelete='RESTRICT'), nullable=True),
        sa.Column('is_virtual', sa.Boolean(), nullable=False, server_default=sa.text('0')),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )

    # 6. stock
    op.create_table(
        'stock',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('product_id', sa.Integer(), sa.ForeignKey('products.id', ondelete='RESTRICT'), nullable=False, index=True),
        sa.Column('location_id', sa.Integer(), sa.ForeignKey('locations.id', ondelete='RESTRICT'), nullable=False, index=True),
        sa.Column('on_hand', sa.Numeric(precision=12, scale=3), nullable=False, server_default='0.000'),
        sa.Column('reserved', sa.Numeric(precision=12, scale=3), nullable=False, server_default='0.000'),
        sa.Column('version', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint('product_id', 'location_id', name='uq_stock_product_location'),
        sa.CheckConstraint('on_hand >= 0', name='chk_stock_on_hand_non_negative'),
        sa.CheckConstraint('reserved >= 0', name='chk_stock_reserved_non_negative'),
        sa.CheckConstraint('reserved <= on_hand', name='chk_stock_reserved_lte_on_hand'),
    )

    # 7. transactions
    op.create_table(
        'transactions',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('reference', sa.String(length=100), nullable=False, unique=True, index=True),
        sa.Column('type', sa.String(length=50), nullable=False, index=True),
        sa.Column('status', sa.String(length=50), nullable=False, server_default='DRAFT', index=True),
        sa.Column('source_location_id', sa.Integer(), sa.ForeignKey('locations.id', ondelete='RESTRICT'), nullable=True, index=True),
        sa.Column('destination_location_id', sa.Integer(), sa.ForeignKey('locations.id', ondelete='RESTRICT'), nullable=True, index=True),
        sa.Column('party_name', sa.String(length=255), nullable=True),
        sa.Column('contact', sa.String(length=255), nullable=True),
        sa.Column('delivery_address', sa.String(length=500), nullable=True),
        sa.Column('schedule_date', sa.DateTime(timezone=True), nullable=True),
        sa.Column('reason', sa.String(length=500), nullable=True),
        sa.Column('created_by', sa.Integer(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('validated_by', sa.Integer(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('validated_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('canceled_at', sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint("type IN ('RECEIPT', 'DELIVERY', 'TRANSFER', 'ADJUSTMENT')", name='chk_valid_transaction_type'),
        sa.CheckConstraint("status IN ('DRAFT', 'WAITING', 'READY', 'DONE', 'CANCELED')", name='chk_valid_transaction_status'),
    )

    # 8. transaction_items
    op.create_table(
        'transaction_items',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('transaction_id', sa.Integer(), sa.ForeignKey('transactions.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('product_id', sa.Integer(), sa.ForeignKey('products.id', ondelete='RESTRICT'), nullable=False, index=True),
        sa.Column('quantity', sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column('adjustment_delta', sa.Numeric(precision=12, scale=3), nullable=True),
        sa.CheckConstraint('quantity >= 0', name='chk_transaction_item_quantity_non_negative'),
    )

    # 9. stock_ledger
    op.create_table(
        'stock_ledger',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('transaction_id', sa.Integer(), sa.ForeignKey('transactions.id', ondelete='RESTRICT'), nullable=True, index=True),
        sa.Column('product_id', sa.Integer(), sa.ForeignKey('products.id', ondelete='RESTRICT'), nullable=False, index=True),
        sa.Column('location_id', sa.Integer(), sa.ForeignKey('locations.id', ondelete='RESTRICT'), nullable=False, index=True),
        sa.Column('quantity_change', sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column('running_balance', sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column('reference', sa.String(length=100), nullable=False, index=True),
        sa.Column('movement_type', sa.String(length=50), nullable=False, index=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now(), index=True),
        sa.Column('created_by', sa.Integer(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
    )

    # 10. password_reset_tokens
    op.create_table(
        'password_reset_tokens',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('token', sa.String(length=255), nullable=False, unique=True, index=True),
        sa.Column('otp_code', sa.String(length=10), nullable=True),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('is_used', sa.Boolean(), nullable=False, server_default=sa.text('0')),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )

    # 11. idempotency_keys
    op.create_table(
        'idempotency_keys',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('key', sa.String(length=255), nullable=False, unique=True, index=True),
        sa.Column('endpoint', sa.String(length=255), nullable=False),
        sa.Column('request_hash', sa.String(length=255), nullable=True),
        sa.Column('response_code', sa.Integer(), nullable=True),
        sa.Column('response_body', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
    )


def downgrade() -> None:
    op.drop_table('idempotency_keys')
    op.drop_table('password_reset_tokens')
    op.drop_table('stock_ledger')
    op.drop_table('transaction_items')
    op.drop_table('transactions')
    op.drop_table('stock')
    op.drop_table('locations')
    op.drop_table('warehouses')
    op.drop_table('products')
    op.drop_table('categories')
    op.drop_table('users')
