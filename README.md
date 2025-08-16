# Self-Sovereign Identity Platform for Employment Verification

A blockchain-powered platform enabling individuals to manage their own identity credentials for employment verification, ensuring privacy, security, and efficiency in hiring processes.

---

## Overview

This platform uses five main smart contracts built with Clarity to create a decentralized, transparent, and user-controlled identity ecosystem for employment verification:

1. **Identity Registry Contract** – Manages user identity profiles and links verifiable credentials.
2. **Credential Issuer Contract** – Issues tamper-proof credentials (e.g., degrees, certifications, work history) as digital assets.
3. **Verification Request Contract** – Handles employer requests for credential verification with user consent.
4. **Access Control Contract** – Manages permissions and selective disclosure of user data.
5. **Reputation Oracle Contract** – Integrates off-chain data for validating issuer credibility and updates.

---

## Features

- **Self-sovereign identity profiles** for user-controlled data management  
- **Tamper-proof credentials** issued as blockchain-based assets  
- **Consent-based verification** for secure employer access to data  
- **Selective disclosure** to share only necessary information  
- **Issuer reputation tracking** to ensure trusted credential sources  
- **Privacy-preserving workflows** using zero-knowledge proofs for minimal data exposure  
- **Decentralized storage integration** for secure off-chain data management  
- **Cross-platform compatibility** for use in hiring, freelancing, and more  

---

## Problem Solved

Traditional employment verification is slow, costly (often $50-$200 per check), and prone to fraud or errors. Employers rely on third parties, risking data breaches (e.g., Equifax 2017 breach exposing 147M records). Candidates lose control over their data, facing repeated disclosures. This platform empowers users to own their data, reduces verification costs, and ensures secure, fraud-resistant processes.

---

## Smart Contracts

### Identity Registry Contract
- Registers user DIDs (Decentralized Identifiers) on-chain
- Links credentials to user profiles
- Allows profile updates with user consent

```clarity
(define-data-var identity-counter uint u0)

(define-map identities
  { user: principal }
  { did: (string-ascii 64), credentials: (list 100 (string-ascii 128)) })

(define-public (register-identity (did (string-ascii 64)))
  (let ((user-id (var-get identity-counter)))
    (var-set identity-counter (+ user-id u1))
    (map-insert identities { user: tx-sender } { did: did, credentials: (list) })
    (ok true)))
```

### Credential Issuer Contract
- Issues credentials (e.g., work history, certifications) as digital assets
- Stores credential metadata on-chain
- Verifies issuer authority

```clarity
(define-map credentials
  { credential-id: (string-ascii 128) }
  { issuer: principal, holder: principal, data: (string-ascii 256), issued-at: uint })

(define-public (issue-credential (credential-id (string-ascii 128)) (holder principal) (data (string-ascii 256)))
  (begin
    (asserts! (is-authorized-issuer tx-sender) (err u401))
    (map-insert credentials
      { credential-id: credential-id }
      { issuer: tx-sender, holder: holder, data: data, issued-at: block-height })
    (ok true)))
```

### Verification Request Contract
- Manages employer verification requests
- Requires user consent for data access
- Logs verification events

```clarity
(define-map verification-requests
  { request-id: uint }
  { requester: principal, holder: principal, credential-id: (string-ascii 128), approved: bool })

(define-data-var request-counter uint u0)

(define-public (request-verification (holder principal) (credential-id (string-ascii 128)))
  (let ((request-id (var-get request-counter)))
    (var-set request-counter (+ request-id u1))
    (map-insert verification-requests
      { request-id: request-id }
      { requester: tx-sender, holder: holder, credential-id: credential-id, approved: false })
    (ok request-id)))
```

### Access Control Contract
- Enforces selective disclosure of credentials
- Supports zero-knowledge proof integration for privacy
- Manages access permissions

```clarity
(define-map access-permissions
  { credential-id: (string-ascii 128), requester: principal }
  { approved: bool, fields: (list 10 (string-ascii 64)) })

(define-public (grant-access (credential-id (string-ascii 128)) (requester principal) (fields (list 10 (string-ascii 64))))
  (begin
    (asserts! (is-credential-holder credential-id tx-sender) (err u403))
    (map-insert access-permissions
      { credential-id: credential-id, requester: requester }
      { approved: true, fields: fields })
    (ok true)))
```

### Reputation Oracle Contract
- Integrates off-chain data to validate issuer credibility
- Tracks issuer reputation scores
- Updates credential status based on external data

```clarity
(define-map issuer-reputation
  { issuer: principal }
  { score: uint, last-updated: uint })

(define-public (update-reputation (issuer principal) (score uint))
  (begin
    (asserts! (is-oracle tx-sender) (err u401))
    (map-set issuer-reputation
      { issuer: issuer }
      { score: score, last-updated: block-height })
    (ok true)))
```

---

## Installation

1. Install [Clarinet CLI](https://docs.hiro.so/clarinet/getting-started)
2. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/ssi-employment.git
   ```
3. Run tests:
    ```bash
    npm test
    ```
4. Deploy contracts:
    ```bash
    clarinet deploy
    ```

---

## Usage

1. Users register their DID via the **Identity Registry Contract**.
2. Authorized issuers (e.g., employers, universities) issue credentials using the **Credential Issuer Contract**.
3. Employers submit verification requests through the **Verification Request Contract**.
4. Users grant selective access via the **Access Control Contract**.
5. The **Reputation Oracle Contract** ensures issuer trustworthiness with off-chain data.

Refer to individual contract documentation for detailed function calls and parameters.

---

## License

MIT License

