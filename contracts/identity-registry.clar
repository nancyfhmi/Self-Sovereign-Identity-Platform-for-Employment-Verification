;; Identity Registry Contract
;; Clarity v2 (assuming latest syntax as of 2025, compatible with Stacks 2.1+)
;; Manages decentralized identifiers (DIDs) and linked verifiable credentials for self-sovereign identities.
;; Supports registration, updates, credential linking/unlinking, queries, admin controls, pausing, and event emissions.
;; Designed for robustness: error handling, access controls, limits to prevent abuse, and read-only functions for transparency.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED u100) ;; Caller not authorized (e.g., not owner or admin)
(define-constant ERR-ALREADY-REGISTERED u101) ;; Identity already exists for user
(define-constant ERR-NOT-REGISTERED u102) ;; No identity found for user
(define-constant ERR-INVALID-DID u103) ;; DID format invalid (e.g., too long/short)
(define-constant ERR-CREDENTIAL-LIMIT-REACHED u104) ;; Max credentials per identity reached
(define-constant ERR-INVALID-CREDENTIAL-ID u105) ;; Credential ID invalid
(define-constant ERR-PAUSED u106) ;; Contract is paused
(define-constant ERR-ZERO-ADDRESS u107) ;; Invalid principal (zero address)
(define-constant ERR-CREDENTIAL-NOT-FOUND u108) ;; Credential not linked to identity
(define-constant ERR-INVALID-UPDATE u109) ;; Invalid update attempt (e.g., no change)

;; Constants
(define-constant MAX-CREDENTIALS-PER-IDENTITY u50) ;; Limit to prevent map bloat
(define-constant MIN-DID-LENGTH u10) ;; Enforce reasonable DID length
(define-constant MAX-DID-LENGTH u64) ;; As per map key
(define-constant CONTRACT-OWNER tx-sender) ;; Deployer is initial owner

;; Data variables
(define-data-var admin principal CONTRACT-OWNER) ;; Admin for pausing/updating contract
(define-data-var paused bool false) ;; Pause flag for critical operations
(define-data-var total-identities uint u0) ;; Counter for registered identities

;; Maps
(define-map identities
  { user: principal } ;; Key: user's principal
  {
    did: (string-ascii 64), ;; Decentralized Identifier (DID)
    credentials: (list 50 (string-ascii 128)), ;; List of credential IDs (e.g., hashes or URIs)
    created-at: uint, ;; Block height of creation
    updated-at: uint ;; Last update block height
  }
)

;; Optional: Map for reverse lookup (DID to user), useful for queries
(define-map did-to-user
  { did: (string-ascii 64) }
  { user: principal }
)

;; Private helpers

;; Check if caller is admin
(define-private (is-admin)
  (is-eq tx-sender (var-get admin))
)

;; Check if caller is the identity owner
(define-private (is-owner (user principal))
  (is-eq tx-sender user)
)

;; Ensure contract not paused
(define-private (ensure-not-paused)
  (asserts! (not (var-get paused)) (err ERR-PAUSED))
)

;; Validate DID format (basic: length check)
(define-private (validate-did (did (string-ascii 64)))
  (and
    (>= (len did) MIN-DID-LENGTH)
    (<= (len did) MAX-DID-LENGTH)
  )
)

;; Validate credential ID (basic: non-empty string)
(define-private (validate-credential-id (cred-id (string-ascii 128)))
  (> (len cred-id) u0)
)

;; Emit event (Clarity doesn't have native events, but we can use print for logging)
(define-private (emit-event (event-type (string-ascii 32)) (details (string-ascii 256)))
  (print { event: event-type, details: details, sender: tx-sender, block: block-height })
)

;; Public functions

;; Transfer admin rights
(define-public (transfer-admin (new-admin principal))
  (begin
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    (asserts! (not (is-eq new-admin 'SP000000000000000000002Q6VF78)) (err ERR-ZERO-ADDRESS))
    (var-set admin new-admin)
    (emit-event "admin-transfer" (concat "New admin: " (principal-to-string new-admin)))
    (ok true)
  )
)

;; Pause/unpause contract
(define-public (set-paused (pause bool))
  (begin
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    (var-set paused pause)
    (emit-event "pause-status" (if pause "Paused" "Unpaused"))
    (ok pause)
  )
)

;; Register a new identity
(define-public (register-identity (did (string-ascii 64)))
  (begin
    (ensure-not-paused)
    (asserts! (validate-did did) (err ERR-INVALID-DID))
    (asserts! (is-none (map-get? identities { user: tx-sender })) (err ERR-ALREADY-REGISTERED))
    (asserts! (is-none (map-get? did-to-user { did: did })) (err ERR-ALREADY-REGISTERED)) ;; Prevent DID duplication
    (let ((current-block block-height))
      (map-set identities
        { user: tx-sender }
        { did: did, credentials: (list), created-at: current-block, updated-at: current-block }
      )
      (map-set did-to-user { did: did } { user: tx-sender })
      (var-set total-identities (+ (var-get total-identities) u1))
      (emit-event "identity-registered" (concat "DID: " did))
      (ok true)
    )
  )
)

;; Update DID (only owner, rare operation)
(define-public (update-did (new-did (string-ascii 64)))
  (begin
    (ensure-not-paused)
    (let ((identity (unwrap! (map-get? identities { user: tx-sender }) (err ERR-NOT-REGISTERED))))
      (asserts! (validate-did new-did) (err ERR-INVALID-DID))
      (asserts! (not (is-eq new-did (get did identity))) (err ERR-INVALID-UPDATE))
      (asserts! (is-none (map-get? did-to-user { did: new-did })) (err ERR-ALREADY-REGISTERED))
      ;; Update maps
      (map-delete did-to-user { did: (get did identity) })
      (map-set did-to-user { did: new-did } { user: tx-sender })
      (map-set identities
        { user: tx-sender }
        (merge identity { did: new-did, updated-at: block-height })
      )
      (emit-event "did-updated" (concat "New DID: " new-did))
      (ok true)
    )
  )
)

;; Link a credential to identity (owner only)
(define-public (link-credential (cred-id (string-ascii 128)))
  (begin
    (ensure-not-paused)
    (asserts! (validate-credential-id cred-id) (err ERR-INVALID-CREDENTIAL-ID))
    (let ((identity (unwrap! (map-get? identities { user: tx-sender }) (err ERR-NOT-REGISTERED))))
      (let ((creds (get credentials identity)))
        (asserts! (< (len creds) MAX-CREDENTIALS-PER-IDENTITY) (err ERR-CREDENTIAL-LIMIT-REACHED))
        (asserts! (not (is-some (index-of creds cred-id))) (err ERR-ALREADY-REGISTERED)) ;; Prevent duplicates
        (map-set identities
          { user: tx-sender }
          (merge identity {
            credentials: (append creds cred-id),
            updated-at: block-height
          })
        )
        (emit-event "credential-linked" (concat "Cred ID: " cred-id))
        (ok true)
      )
    )
  )
)

;; Unlink a credential (owner only)
(define-public (unlink-credential (cred-id (string-ascii 128)))
  (begin
    (ensure-not-paused)
    (let ((identity (unwrap! (map-get? identities { user: tx-sender }) (err ERR-NOT-REGISTERED))))
      (let ((creds (get credentials identity)))
        (let ((index (index-of creds cred-id)))
          (asserts! (is-some index) (err ERR-CREDENTIAL-NOT-FOUND))
          (let ((new-creds (filter (lambda (c) (not (is-eq c cred-id))) creds)))
            (map-set identities
              { user: tx-sender }
              (merge identity {
                credentials: new-creds,
                updated-at: block-height
              })
            )
            (emit-event "credential-unlinked" (concat "Cred ID: " cred-id))
            (ok true)
          )
        )
      )
    )
  )
)

;; Read-only functions

;; Get identity by user
(define-read-only (get-identity (user principal))
  (map-get? identities { user: user })
)

;; Get user by DID
(define-read-only (get-user-by-did (did (string-ascii 64)))
  (map-get? did-to-user { did: did })
)

;; Get total identities
(define-read-only (get-total-identities)
  (ok (var-get total-identities))
)

;; Check if registered
(define-read-only (is-registered (user principal))
  (ok (is-some (map-get? identities { user: user })))
)

;; Get admin
(define-read-only (get-admin)
  (ok (var-get admin))
)

;; Check paused
(define-read-only (is-paused)
  (ok (var-get paused))
)

;; Helper: principal to string (for events, assuming custom impl)
(define-private (principal-to-string (p principal))
  (unwrap-panic (principal-to-ascii p))
)

;; Filter lambda for unlink (Clarity requires explicit lambda)
(define-private (not-equal-to (item (string-ascii 128)) (target (string-ascii 128)))
  (not (is-eq item target))
)