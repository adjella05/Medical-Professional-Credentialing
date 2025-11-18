# 🏥 Medical Professional Credentialing

A decentralized registry for medical licenses and certifications, verifiable by employers and patients on the Stacks blockchain.

## 🎯 Overview

The Credential smart contract provides a secure, transparent, and tamper-proof system for managing medical professional credentials. Healthcare institutions can issue credentials, professionals can manage their licenses, and employers/patients can verify authenticity instantly.

## ✨ Features

- 🔐 **Secure Credential Issuance** - Only authorized medical institutions can issue credentials
- 📋 **Multiple Credential Types** - Support for various medical licenses and certifications  
- ⏰ **Expiry Management** - Automatic expiry tracking and renewal functionality
- 🔍 **Instant Verification** - Real-time credential validation for employers and patients
- 📊 **Audit Trail** - Complete history of credential changes and verifications
- 💼 **Transfer Support** - Credentials can be transferred between holders
- 🚫 **Revocation System** - Issuers can revoke or suspend credentials when necessary

## 🚀 Quick Start

### Deploy Contract
```bash
clarinet console
::deploy_contract contracts/Credential.clar
```

### Issue a Credential
```clarity
(contract-call? .Credential issue-credential 
  'SP1234567890123456789012345678901234567890
  "MD"
  "MD-12345"
  "Johns Hopkins Medical School"
  "Cardiology"
  u1000000)
```

### Verify a Credential
```clarity
(contract-call? .Credential verify-credential u1 "Employment Verification")
```

## 📚 Usage Guide

### 👨‍⚕️ For Medical Institutions

**Authorize as Issuer** (Owner only)
```clarity
(contract-call? .Credential authorize-issuer 
  'SP-INSTITUTION-ADDRESS
  "Johns Hopkins Medical Center"
  "Medical School")
```

**Issue Medical Credentials**
```clarity
(contract-call? .Credential issue-credential
  'SP-DOCTOR-ADDRESS
  "MD"
  "MD-67890"
  "Harvard Medical School"
  "Neurology"
  u2000000)
```

**Revoke Credentials**
```clarity
(contract-call? .Credential revoke-credential u1 "License suspended")
```

### 🏥 For Healthcare Professionals

**Renew Credentials**
```clarity
(contract-call? .Credential renew-credential u1 u3000000)
```

**Transfer Credentials**
```clarity
(contract-call? .Credential transfer-credential u1 'SP-NEW-HOLDER)
```

**View Your Credentials**
```clarity
(contract-call? .Credential get-credentials-by-holder tx-sender)
```

### 🏢 For Employers & Patients

**Verify a Professional**
```clarity
(contract-call? .Credential verify-credential u1 "Employment Background Check")
```

**Check Credential Validity**
```clarity
(contract-call? .Credential is-credential-valid u1)
```

**Bulk Verification**
```clarity
(contract-call? .Credential bulk-verify-credentials (list u1 u2 u3))
```

## 📋 Credential Status Codes

| Status | Code | Description |
|--------|------|-------------|
| ✅ Active | `1` | Valid and current credential |
| ⏰ Expired | `2` | Credential past expiry date |
| 🚫 Revoked | `3` | Permanently revoked credential |
| ⏸️ Suspended | `4` | Temporarily suspended credential |

## 💰 Fee Structure

| Action | Fee (STX) | Description |
|--------|-----------|-------------|
| Issue Credential | `1.0 STX` | One-time issuance fee |
| Renew Credential | `0.5 STX` | Renewal processing fee |
| Verify Credential | `0.1 STX` | Per-verification fee |

## 🔍 Read-Only Functions

### Credential Queries
- `get-credential(credential-id)` - Get full credential details
- `get-credentials-by-holder(holder)` - List all credentials for a holder
- `get-credentials-by-issuer(issuer)` - List all credentials by an issuer
- `is-credential-valid(credential-id)` - Check if credential is active and not expired

### Search Functions
- `search-credentials-by-type(type)` - Find credentials by type (e.g., "MD", "RN")
- `search-credentials-by-specialization(specialization)` - Find by medical specialty
- `get-expiring-credentials(blocks-ahead)` - Find credentials expiring soon

### Analytics
- `get-contract-stats()` - Overall contract usage statistics
- `get-active-credentials-count(holder)` - Count of valid credentials per holder
- `get-verification-history(credential-id, verifier)` - Verification audit trail

## 🛡️ Security Features

- **Multi-signature Authorization** - Only pre-approved institutions can issue credentials
- **Immutable Records** - Credential history cannot be altered once recorded
- **Expiry Enforcement** - Automatic invalidation of expired credentials
- **Revocation Support** - Immediate credential invalidation when necessary
- **Transfer Tracking** - Complete audit trail of credential ownership changes

## 🧪 Testing

Run contract tests:
```bash
clarinet test
```

Check contract syntax:
```bash
clarinet check
```

## 📄 License

This project is open source and available under the MIT License.

## 🤝 Contributing

Contributions are welcome! Please read our contributing guidelines and submit pull requests for any improvements.

---

Built with ❤️ for the medical community using Stacks blockchain technology.
