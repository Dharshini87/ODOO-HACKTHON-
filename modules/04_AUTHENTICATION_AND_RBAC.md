# MODULE 04: 04_AUTHENTICATION_AND_RBAC

============================================================
5. AUTHENTICATION
============================================================

Implement:

Login
Register
Forgot Password
OTP Verification
Reset Password

Backend endpoints:

POST /api/auth/register
POST /api/auth/login
POST /api/auth/forgot-password
POST /api/auth/reset-password

Authentication:

- JWT access token
- Secure password hashing
- Secure token storage
- Role-based authorization
- Protected API endpoints

Store JWT using:

flutter_secure_storage

Do not store authentication tokens in plain shared preferences.

Application launch:

Splash
    ↓
Check token
    ↓
Authenticated?
    ├── YES → Dashboard
    └── NO → Login

============================================================
6. USER ROLES
============================================================

Roles:

WAREHOUSE_STAFF
INVENTORY_MANAGER

Permissions:

                         STAFF       MANAGER

View Dashboard            YES          YES
View Stock                YES          YES
View Products             YES          YES
Create Receipt            YES          YES
Validate Receipt          YES          YES
Create Delivery           YES          YES
Validate Delivery         YES          YES
Create Transfer           YES          YES
Validate Transfer         YES          YES
Create Adjustment         YES          YES
Validate Adjustment       NO           YES
Manage Products           NO           YES
Manage Categories         NO           YES
Manage Warehouses         NO           YES
Manage Locations          NO           YES
View Ledger               YES          YES
View Move History         YES          YES
Cancel own transaction    YES          YES
Cancel another user's
transaction                NO           YES

Enforce permissions in FastAPI.

Frontend visibility is NOT a security mechanism.

============================================================
8. USERS
============================================================

users:

- id
- name
- email
- password_hash
- role
- is_active
- created_at
- updated_at

Email must be unique.

Passwords must never be stored in plaintext.

============================================================
