import datetime
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Query, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from .. import models
from ..database import get_db
from ..core.dependencies import get_current_user
from ..services.storage_service import StorageService
from ..services.ocr_service import OCRService
from ..services.receipt_matching_service import ReceiptMatchingService

router = APIRouter(tags=["Physical Receipt OCR Verification"])


def _serialize_document_meta(doc: models.ReceiptDocument) -> dict:
    return {
        "id": doc.id,
        "transaction_id": doc.transaction_id,
        "original_filename": doc.original_filename,
        "storage_key": doc.storage_key,
        "mime_type": doc.mime_type,
        "file_size": doc.file_size,
        "page_count": doc.page_count,
        "ocr_status": doc.ocr_status,
        "ocr_confidence": float(doc.ocr_confidence) if doc.ocr_confidence is not None else None,
        "uploaded_by": doc.uploaded_by,
        "uploaded_at": doc.uploaded_at.isoformat() if doc.uploaded_at else None,
        "processed_at": doc.processed_at.isoformat() if doc.processed_at else None,
        "verification_result": doc.verification_result,
        "has_verification": doc.verification_result is not None,
    }


def _get_receipt_tx(tx_id: int, db: Session) -> models.Transaction:
    tx = db.query(models.Transaction).filter(models.Transaction.id == tx_id).first()
    if not tx:
        raise HTTPException(status_code=404, detail="Transaction not found.")
    if tx.type != models.TransactionType.RECEIPT:
        raise HTTPException(status_code=400, detail="Document OCR verification is only applicable to Receipt transactions.")
    return tx


# -------------------------------------------------------------
# 1. UPLOAD PHYSICAL RECEIPT (Section 40)
# -------------------------------------------------------------
@router.post("/transactions/{transaction_id}/receipt-document", status_code=status.HTTP_201_CREATED)
@router.post("/receipts/{transaction_id}/receipt-document", status_code=status.HTTP_201_CREATED)
async def upload_receipt_document(
    transaction_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """
    Upload a physical supplier receipt (PDF, PNG, JPG, JPEG).
    Stores document privately and records metadata in receipt_documents table.
    NEVER mutates inventory or creates ledger entries.
    """
    tx = _get_receipt_tx(transaction_id, db)

    # Save to secure private storage
    storage_key, mime_type, file_size, _ = await StorageService.save_upload(file)

    doc = models.ReceiptDocument(
        transaction_id=tx.id,
        original_filename=file.filename or "receipt.pdf",
        storage_key=storage_key,
        mime_type=mime_type,
        file_size=file_size,
        ocr_status="UPLOADED",
        uploaded_by=user.id,
        uploaded_at=datetime.datetime.utcnow(),
    )
    db.add(doc)
    db.commit()
    db.refresh(doc)

    return {
        "status": "success",
        "message": "Physical receipt uploaded successfully. Ready for OCR verification.",
        "document": _serialize_document_meta(doc),
    }


# -------------------------------------------------------------
# 2. RUN OCR & VERIFY (Section 40)
# -------------------------------------------------------------
@router.post("/transactions/{transaction_id}/receipt-document/verify")
@router.post("/receipts/{transaction_id}/receipt-document/verify")
def verify_receipt_document(
    transaction_id: int,
    document_id: Optional[int] = Query(None, description="Optional specific document ID"),
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """
    Executes OCR document extraction on the uploaded physical receipt,
    extracts structured fields, compares against the digital Receipt transaction,
    and returns MATCH or REVIEW_REQUIRED verification analysis.
    NEVER mutates inventory or creates ledger entries.
    """
    tx = _get_receipt_tx(transaction_id, db)

    # Locate target document (latest or specific)
    query = db.query(models.ReceiptDocument).filter(models.ReceiptDocument.transaction_id == tx.id)
    if document_id:
        doc = query.filter(models.ReceiptDocument.id == document_id).first()
    else:
        doc = query.order_by(models.ReceiptDocument.id.desc()).first()

    if not doc:
        raise HTTPException(
            status_code=404,
            detail="No physical receipt document found for this receipt. Please upload a receipt first."
        )

    file_path = StorageService.get_file_path(doc.storage_key)
    if not StorageService.file_exists(doc.storage_key):
        raise HTTPException(status_code=404, detail="Physical document file missing from storage.")

    # 1. OCR Extraction (Section 9, 10, 11, 12, 13, 14, 15)
    try:
        ocr_result = OCRService.extract_from_file(file_path)
    except Exception as e:
        doc.ocr_status = "FAILED"
        db.commit()
        raise HTTPException(status_code=500, detail=f"Failed to process and OCR physical document: {str(e)}")

    # 2. Matching Engine (Section 16 - 25)
    comparison = ReceiptMatchingService.compare(tx, ocr_result)

    # 3. Store structured audit results (Section 39, 42)
    doc.ocr_status = comparison["status"]
    doc.ocr_confidence = comparison["confidence"]
    doc.page_count = ocr_result.page_count
    doc.extracted_data = ocr_result.to_dict()
    doc.verification_result = comparison
    doc.processed_at = datetime.datetime.utcnow()
    db.commit()
    db.refresh(doc)

    return {
        "status": "success",
        "document_id": doc.id,
        "verification": comparison,
    }


# -------------------------------------------------------------
# 3. GET UPLOADED DOCUMENT METADATA (Section 40)
# -------------------------------------------------------------
@router.get("/transactions/{transaction_id}/receipt-document")
@router.get("/receipts/{transaction_id}/receipt-document")
def get_receipt_document_metadata(
    transaction_id: int,
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_user),
):
    """
    Get uploaded document metadata for a receipt.
    """
    tx = _get_receipt_tx(transaction_id, db)
    doc = (
        db.query(models.ReceiptDocument)
        .filter(models.ReceiptDocument.transaction_id == tx.id)
        .order_by(models.ReceiptDocument.id.desc())
        .first()
    )
    if not doc:
        return {"has_document": False, "document": None}

    return {
        "has_document": True,
        "document": _serialize_document_meta(doc),
    }


# -------------------------------------------------------------
# 4. GET LATEST VERIFICATION RESULT (Section 40)
# -------------------------------------------------------------
@router.get("/transactions/{transaction_id}/receipt-verification")
@router.get("/receipts/{transaction_id}/receipt-verification")
def get_receipt_verification(
    transaction_id: int,
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_user),
):
    """
    Get latest OCR verification result for a receipt.
    """
    tx = _get_receipt_tx(transaction_id, db)
    doc = (
        db.query(models.ReceiptDocument)
        .filter(models.ReceiptDocument.transaction_id == tx.id)
        .order_by(models.ReceiptDocument.id.desc())
        .first()
    )
    if not doc or not doc.verification_result:
        return {
            "verified": False,
            "status": "UNVERIFIED",
            "message": "No verification performed yet.",
            "verification": None,
        }

    return {
        "verified": True,
        "status": doc.ocr_status,
        "document_id": doc.id,
        "confidence": float(doc.ocr_confidence) if doc.ocr_confidence else None,
        "verification": doc.verification_result,
    }


# -------------------------------------------------------------
# 5. SECURE DOCUMENT DOWNLOAD (Section 7, 41)
# -------------------------------------------------------------
@router.get("/transactions/{transaction_id}/receipt-document/download")
@router.get("/receipts/{transaction_id}/receipt-document/download")
def download_receipt_document(
    transaction_id: int,
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_user),
):
    """
    Authorized document download.
    Never exposes internal filesystem paths.
    """
    tx = _get_receipt_tx(transaction_id, db)
    doc = (
        db.query(models.ReceiptDocument)
        .filter(models.ReceiptDocument.transaction_id == tx.id)
        .order_by(models.ReceiptDocument.id.desc())
        .first()
    )
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found.")

    file_path = StorageService.get_file_path(doc.storage_key)
    if not StorageService.file_exists(doc.storage_key):
        raise HTTPException(status_code=404, detail="File not found on storage.")

    return FileResponse(
        path=file_path,
        media_type=doc.mime_type,
        filename=doc.original_filename,
    )
