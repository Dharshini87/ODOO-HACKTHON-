import os
import uuid
from typing import Tuple
from fastapi import UploadFile, HTTPException

# Storage configuration
MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024  # 10 MB
ALLOWED_MIME_TYPES = {
    "application/pdf": ".pdf",
    "image/png": ".png",
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
}
ALLOWED_EXTENSIONS = {".pdf", ".png", ".jpg", ".jpeg"}

# Private storage directory: backend/storage/receipt_documents/
BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
STORAGE_ROOT = os.path.join(BASE_DIR, "storage", "receipt_documents")
os.makedirs(STORAGE_ROOT, exist_ok=True)


class StorageService:
    """
    Secure local private document storage (Sections 6, 7, 8).
    - Validates file MIME types, extensions, size limits
    - Uses UUID-based keys; never exposes filesystem paths
    - Prevents directory traversal
    """

    @staticmethod
    def validate_file_meta(filename: str, content_type: str, file_size: int):
        if file_size > MAX_FILE_SIZE_BYTES:
            raise HTTPException(
                status_code=413,
                detail=f"File exceeds maximum allowed size of {MAX_FILE_SIZE_BYTES // (1024*1024)} MB."
            )
        
        _, ext = os.path.splitext(filename or "")
        ext = ext.lower()
        if ext not in ALLOWED_EXTENSIONS:
            raise HTTPException(
                status_code=400,
                detail="Unsupported file type. Please upload a PDF, PNG, JPG, or JPEG."
            )

        norm_content_type = (content_type or "").lower().split(";")[0].strip()
        if norm_content_type not in ALLOWED_MIME_TYPES and norm_content_type != "application/octet-stream":
            raise HTTPException(
                status_code=400,
                detail="Unsupported MIME type. Please upload a valid PDF or image file."
            )

    @classmethod
    async def save_upload(cls, upload_file: UploadFile) -> Tuple[str, str, int, str]:
        """
        Saves uploaded file to private storage.
        Returns (storage_key, mime_type, file_size, safe_ext)
        """
        orig_filename = upload_file.filename or "receipt.pdf"
        _, ext = os.path.splitext(orig_filename)
        ext = ext.lower()
        if not ext or ext not in ALLOWED_EXTENSIONS:
            ext = ".pdf"

        # Read content and measure size
        content = await upload_file.read()
        file_size = len(content)

        cls.validate_file_meta(orig_filename, upload_file.content_type or "", file_size)

        if file_size == 0:
            raise HTTPException(status_code=400, detail="Uploaded file is empty.")

        # Generate unique storage key
        unique_id = uuid.uuid4().hex
        storage_key = f"receipt_doc_{unique_id}{ext}"
        destination_path = cls.get_file_path(storage_key)

        with open(destination_path, "wb") as f:
            f.write(content)

        # Reset upload file pointer
        await upload_file.seek(0)

        mime_type = upload_file.content_type or "application/octet-stream"
        return storage_key, mime_type, file_size, ext

    @classmethod
    def get_file_path(cls, storage_key: str) -> str:
        """
        Safely resolves a storage_key to an absolute filesystem path.
        Guarantees path is strictly within STORAGE_ROOT.
        """
        safe_key = os.path.basename(storage_key)
        full_path = os.path.abspath(os.path.join(STORAGE_ROOT, safe_key))
        if not full_path.startswith(os.path.abspath(STORAGE_ROOT)):
            raise HTTPException(status_code=400, detail="Invalid storage path detected.")
        return full_path

    @classmethod
    def file_exists(cls, storage_key: str) -> bool:
        path = cls.get_file_path(storage_key)
        return os.path.exists(path) and os.path.isfile(path)
