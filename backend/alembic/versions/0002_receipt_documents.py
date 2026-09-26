"""0002_receipt_documents

Revision ID: 0002_receipt_documents
Revises: 0001_core_schema
Create Date: 2026-09-26 21:05:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = '0002_receipt_documents'
down_revision: Union[str, Sequence[str], None] = '0001_core_schema'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'receipt_documents',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('transaction_id', sa.Integer(), sa.ForeignKey('transactions.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('original_filename', sa.String(length=255), nullable=False),
        sa.Column('storage_key', sa.String(length=255), nullable=False, unique=True, index=True),
        sa.Column('mime_type', sa.String(length=100), nullable=False),
        sa.Column('file_size', sa.Integer(), nullable=False),
        sa.Column('page_count', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('ocr_status', sa.String(length=50), nullable=False, server_default='UPLOADED'),
        sa.Column('ocr_confidence', sa.Numeric(precision=5, scale=4), nullable=True),
        sa.Column('extracted_data_json', sa.Text(), nullable=True),
        sa.Column('verification_result_json', sa.Text(), nullable=True),
        sa.Column('uploaded_by', sa.Integer(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('uploaded_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('processed_at', sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_table('receipt_documents')
