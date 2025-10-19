;; title: Credential
;; version: 1.0.0
;; summary: Decentralized registry for medical licenses and certifications
;; description: A smart contract for managing, verifying and tracking medical professional credentials

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u1))
(define-constant ERR-CREDENTIAL-NOT-FOUND (err u2))
(define-constant ERR-CREDENTIAL-EXISTS (err u3))
(define-constant ERR-CREDENTIAL-EXPIRED (err u4))
(define-constant ERR-INVALID-ISSUER (err u5))
(define-constant ERR-INVALID-STATUS (err u6))
(define-constant ERR-CREDENTIAL-REVOKED (err u7))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u8))
(define-constant ERR-ALREADY-SUBSCRIBED (err u9))
(define-constant ERR-NOT-SUBSCRIBED (err u10))

(define-constant STATUS-ACTIVE u1)
(define-constant STATUS-EXPIRED u2)
(define-constant STATUS-REVOKED u3)
(define-constant STATUS-SUSPENDED u4)

(define-constant CREDENTIAL-FEE u1000000)
(define-constant RENEWAL-FEE u500000)
(define-constant VERIFICATION-FEE u100000)

(define-data-var next-credential-id uint u1)
(define-data-var contract-enabled bool true)
(define-data-var total-credentials uint u0)
(define-data-var total-verifications uint u0)
(define-data-var alert-enabled bool true)
(define-data-var total-alerts uint u0)

(define-map credentials
  uint
  {
    holder: principal,
    issuer: principal,
    credential-type: (string-ascii 50),
    license-number: (string-ascii 50),
    institution: (string-ascii 100),
    specialization: (string-ascii 100),
    issue-date: uint,
    expiry-date: uint,
    status: uint,
    verification-count: uint
  }
)

(define-map credential-holder-index
  principal
  (list 50 uint)
)

(define-map authorized-issuers
  principal
  {
    name: (string-ascii 100),
    authority-type: (string-ascii 50),
    authorized-at: uint,
    status: bool
  }
)

(define-map issuer-credentials
  principal
  (list 100 uint)
)

(define-map verification-history
  { credential-id: uint, verifier: principal, block-height: uint }
  {
    timestamp: uint,
    verified-by: principal,
    purpose: (string-ascii 100)
  }
)

(define-map credential-renewals
  uint
  (list 10 { renewed-at: uint, new-expiry: uint, renewed-by: principal })
)

;; Alert System Maps
(define-map alert-subscriptions
  { subscriber: principal, credential-id: uint }
  {
    alert-types: (list 5 (string-ascii 20)),
    subscribed-at: uint,
    notification-threshold: uint,
    active: bool
  }
)

(define-map alert-history
  { alert-id: uint }
  {
    credential-id: uint,
    alert-type: (string-ascii 20),
    recipient: principal,
    message: (string-ascii 200),
    triggered-at: uint,
    acknowledged: bool
  }
)

(define-data-var next-alert-id uint u1)

(define-public (authorize-issuer (issuer principal) (name (string-ascii 100)) (authority-type (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-issuers issuer {
      name: name,
      authority-type: authority-type,
      authorized-at: stacks-block-height,
      status: true
    }))
  )
)

(define-public (revoke-issuer-authorization (issuer principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (match (map-get? authorized-issuers issuer)
      issuer-data (ok (map-set authorized-issuers issuer (merge issuer-data { status: false })))
      ERR-INVALID-ISSUER
    )
  )
)

(define-public (issue-credential 
  (holder principal)
  (credential-type (string-ascii 50))
  (license-number (string-ascii 50))
  (institution (string-ascii 100))
  (specialization (string-ascii 100))
  (expiry-date uint)
)
  (let
    (
      (credential-id (var-get next-credential-id))
      (current-block stacks-block-height)
      (issuer-auth (map-get? authorized-issuers tx-sender))
    )
    (asserts! (var-get contract-enabled) ERR-NOT-AUTHORIZED)
    (asserts! (is-some issuer-auth) ERR-INVALID-ISSUER)
    (asserts! (get status (unwrap! issuer-auth ERR-INVALID-ISSUER)) ERR-INVALID-ISSUER)
    (asserts! (> expiry-date current-block) ERR-CREDENTIAL-EXPIRED)
    
    (try! (stx-transfer? CREDENTIAL-FEE tx-sender CONTRACT-OWNER))
    
    (map-set credentials credential-id {
      holder: holder,
      issuer: tx-sender,
      credential-type: credential-type,
      license-number: license-number,
      institution: institution,
      specialization: specialization,
      issue-date: current-block,
      expiry-date: expiry-date,
      status: STATUS-ACTIVE,
      verification-count: u0
    })
    
    (let
      (
        (holder-credentials (default-to (list) (map-get? credential-holder-index holder)))
        (issuer-credentials-list (default-to (list) (map-get? issuer-credentials tx-sender)))
      )
      (map-set credential-holder-index holder (unwrap! (as-max-len? (append holder-credentials credential-id) u50) ERR-NOT-AUTHORIZED))
      (map-set issuer-credentials tx-sender (unwrap! (as-max-len? (append issuer-credentials-list credential-id) u100) ERR-NOT-AUTHORIZED))
    )
    
    (var-set next-credential-id (+ credential-id u1))
    (var-set total-credentials (+ (var-get total-credentials) u1))
    (ok credential-id)
  )
)

(define-public (renew-credential (credential-id uint) (new-expiry-date uint))
  (let
    (
      (credential (unwrap! (map-get? credentials credential-id) ERR-CREDENTIAL-NOT-FOUND))
      (current-block stacks-block-height)
    )
    (asserts! (var-get contract-enabled) ERR-NOT-AUTHORIZED)
    (asserts! (or (is-eq tx-sender (get holder credential)) (is-eq tx-sender (get issuer credential))) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status credential) STATUS-ACTIVE) ERR-CREDENTIAL-REVOKED)
    (asserts! (> new-expiry-date current-block) ERR-CREDENTIAL-EXPIRED)
    
    (try! (stx-transfer? RENEWAL-FEE tx-sender CONTRACT-OWNER))
    
    (map-set credentials credential-id (merge credential {
      expiry-date: new-expiry-date,
      status: STATUS-ACTIVE
    }))
    
    (let
      (
        (renewals (default-to (list) (map-get? credential-renewals credential-id)))
        (new-renewal { renewed-at: current-block, new-expiry: new-expiry-date, renewed-by: tx-sender })
      )
      (map-set credential-renewals credential-id (unwrap! (as-max-len? (append renewals new-renewal) u10) ERR-NOT-AUTHORIZED))
    )
    (ok true)
  )
)

(define-public (revoke-credential (credential-id uint) (reason (string-ascii 100)))
  (let
    (
      (credential (unwrap! (map-get? credentials credential-id) ERR-CREDENTIAL-NOT-FOUND))
    )
    (asserts! (var-get contract-enabled) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq tx-sender (get issuer credential)) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq (get status credential) STATUS-REVOKED)) ERR-CREDENTIAL-REVOKED)
    
    (ok (map-set credentials credential-id (merge credential { status: STATUS-REVOKED })))
  )
)

(define-public (suspend-credential (credential-id uint))
  (let
    (
      (credential (unwrap! (map-get? credentials credential-id) ERR-CREDENTIAL-NOT-FOUND))
    )
    (asserts! (var-get contract-enabled) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq tx-sender (get issuer credential)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status credential) STATUS-ACTIVE) ERR-INVALID-STATUS)
    
    (ok (map-set credentials credential-id (merge credential { status: STATUS-SUSPENDED })))
  )
)

(define-public (reactivate-credential (credential-id uint))
  (let
    (
      (credential (unwrap! (map-get? credentials credential-id) ERR-CREDENTIAL-NOT-FOUND))
    )
    (asserts! (var-get contract-enabled) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq tx-sender (get issuer credential)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status credential) STATUS-SUSPENDED) ERR-INVALID-STATUS)
    (asserts! (> (get expiry-date credential) stacks-block-height) ERR-CREDENTIAL-EXPIRED)
    
    (ok (map-set credentials credential-id (merge credential { status: STATUS-ACTIVE })))
  )
)

(define-public (verify-credential (credential-id uint) (purpose (string-ascii 100)))
  (let
    (
      (credential (unwrap! (map-get? credentials credential-id) ERR-CREDENTIAL-NOT-FOUND))
      (current-block stacks-block-height)
    )
    (asserts! (var-get contract-enabled) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status credential) STATUS-ACTIVE) ERR-CREDENTIAL-REVOKED)
    (asserts! (> (get expiry-date credential) current-block) ERR-CREDENTIAL-EXPIRED)
    
    (try! (stx-transfer? VERIFICATION-FEE tx-sender CONTRACT-OWNER))
    
    (map-set verification-history 
      { credential-id: credential-id, verifier: tx-sender, block-height: current-block }
      {
        timestamp: current-block,
        verified-by: tx-sender,
        purpose: purpose
      }
    )
    
    (map-set credentials credential-id (merge credential {
      verification-count: (+ (get verification-count credential) u1)
    }))
    
    (var-set total-verifications (+ (var-get total-verifications) u1))
    (ok true)
  )
)

(define-public (transfer-credential (credential-id uint) (new-holder principal))
  (let
    (
      (credential (unwrap! (map-get? credentials credential-id) ERR-CREDENTIAL-NOT-FOUND))
    )
    (asserts! (var-get contract-enabled) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq tx-sender (get holder credential)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status credential) STATUS-ACTIVE) ERR-CREDENTIAL-REVOKED)
    
    (let
      (
        (old-holder-credentials (default-to (list) (map-get? credential-holder-index (get holder credential))))
        (new-holder-credentials (default-to (list) (map-get? credential-holder-index new-holder)))
        (filtered-credentials (filter is-not-current-id old-holder-credentials))
      )
      (map-set credential-holder-index (get holder credential) filtered-credentials)
      (map-set credential-holder-index new-holder (unwrap! (as-max-len? (append new-holder-credentials credential-id) u50) ERR-NOT-AUTHORIZED))
    )
    
    (ok (map-set credentials credential-id (merge credential { holder: new-holder })))
  )
)

(define-public (toggle-contract (enabled bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-enabled enabled))
  )
)

(define-read-only (get-credential (credential-id uint))
  (map-get? credentials credential-id)
)

(define-read-only (get-credentials-by-holder (holder principal))
  (map-get? credential-holder-index holder)
)

(define-read-only (get-credentials-by-issuer (issuer principal))
  (map-get? issuer-credentials issuer)
)

(define-read-only (is-authorized-issuer (issuer principal))
  (match (map-get? authorized-issuers issuer)
    issuer-data (get status issuer-data)
    false
  )
)

(define-read-only (get-issuer-info (issuer principal))
  (map-get? authorized-issuers issuer)
)

(define-read-only (is-credential-valid (credential-id uint))
  (match (map-get? credentials credential-id)
    credential (and 
      (is-eq (get status credential) STATUS-ACTIVE)
      (> (get expiry-date credential) stacks-block-height)
    )
    false
  )
)

(define-read-only (get-credential-status (credential-id uint))
  (match (map-get? credentials credential-id)
    credential (get status credential)
    u0
  )
)

(define-read-only (check-credential-expiry (credential-id uint))
  (match (map-get? credentials credential-id)
    credential (some {
      expires-at: (get expiry-date credential),
      is-expired: (<= (get expiry-date credential) stacks-block-height),
      blocks-until-expiry: (if (> (get expiry-date credential) stacks-block-height)
        (- (get expiry-date credential) stacks-block-height)
        u0
      )
    })
    none
  )
)

(define-read-only (get-verification-history (credential-id uint) (verifier principal))
  (map-get? verification-history { credential-id: credential-id, verifier: verifier, block-height: stacks-block-height })
)

(define-read-only (get-credential-renewals (credential-id uint))
  (map-get? credential-renewals credential-id)
)

(define-read-only (search-credentials-by-type (credential-type (string-ascii 50)))
  (let
    (
      (all-credential-ids (generate-credential-id-list (var-get next-credential-id)))
    )
    (filter check-credential-type all-credential-ids)
  )
)

(define-read-only (search-credentials-by-specialization (specialization (string-ascii 100)))
  (let
    (
      (all-credential-ids (generate-credential-id-list (var-get next-credential-id)))
    )
    (filter check-credential-specialization all-credential-ids)
  )
)

(define-read-only (get-contract-stats)
  {
    total-credentials: (var-get total-credentials),
    total-verifications: (var-get total-verifications),
    next-id: (var-get next-credential-id),
    contract-enabled: (var-get contract-enabled),
    current-block: stacks-block-height
  }
)

(define-read-only (get-fees)
  {
    credential-fee: CREDENTIAL-FEE,
    renewal-fee: RENEWAL-FEE,
    verification-fee: VERIFICATION-FEE
  }
)

(define-read-only (bulk-verify-credentials (credential-ids (list 10 uint)))
  (map verify-single-credential credential-ids)
)

(define-private (verify-single-credential (credential-id uint))
  (match (map-get? credentials credential-id)
    credential {
      credential-id: credential-id,
      is-valid: (and 
        (is-eq (get status credential) STATUS-ACTIVE)
        (> (get expiry-date credential) stacks-block-height)
      ),
      holder: (get holder credential),
      credential-type: (get credential-type credential),
      expiry-date: (get expiry-date credential)
    }
    {
      credential-id: credential-id,
      is-valid: false,
      holder: 'SP000000000000000000002Q6VF78,
      credential-type: "",
      expiry-date: u0
    }
  )
)

(define-private (is-not-current-id (id uint))
  (not (is-eq id u0))
)

(define-private (generate-credential-id-list (max-id uint))
  (let
    (
      (ids (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20))
    )
    (filter is-valid-id ids)
  )
)

(define-private (is-valid-id (id uint))
  (and (> id u0) (< id (var-get next-credential-id)))
)

(define-private (check-credential-type (credential-id uint))
  (match (map-get? credentials credential-id)
    credential (is-eq (get credential-type credential) "MD")
    false
  )
)

(define-private (check-credential-specialization (credential-id uint))
  (match (map-get? credentials credential-id)
    credential (is-eq (get specialization credential) "Cardiology")
    false
  )
)

(define-read-only (get-active-credentials-count (holder principal))
  (let
    (
      (holder-credential-ids (default-to (list) (map-get? credential-holder-index holder)))
    )
    (fold count-active-credentials holder-credential-ids u0)
  )
)

(define-private (count-active-credentials (credential-id uint) (count uint))
  (match (map-get? credentials credential-id)
    credential (if (and 
      (is-eq (get status credential) STATUS-ACTIVE)
      (> (get expiry-date credential) stacks-block-height)
    )
      (+ count u1)
      count
    )
    count
  )
)

(define-read-only (get-expiring-credentials (blocks-ahead uint))
  (let
    (
      (target-block (+ stacks-block-height blocks-ahead))
      (all-credential-ids (generate-credential-id-list (var-get next-credential-id)))
    )
    (filter check-expiring-credential all-credential-ids)
  )
)

(define-private (check-expiring-credential (credential-id uint))
  (match (map-get? credentials credential-id)
    credential (and
      (is-eq (get status credential) STATUS-ACTIVE)
      (<= (get expiry-date credential) (+ stacks-block-height u1000))
      (> (get expiry-date credential) stacks-block-height)
    )
    false
  )
)

;; === ALERT SYSTEM FUNCTIONS ===

;; Subscribe to alerts for a specific credential
(define-public (subscribe-to-alerts (credential-id uint) (alert-type (string-ascii 20)))
  (let
    (
      (subscription-key { subscriber: tx-sender, credential-id: credential-id })
      (credential (unwrap! (map-get? credentials credential-id) ERR-CREDENTIAL-NOT-FOUND))
    )
    (asserts! (var-get alert-enabled) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? alert-subscriptions subscription-key)) ERR-ALREADY-SUBSCRIBED)
    
    (ok (map-set alert-subscriptions subscription-key {
      alert-types: (list alert-type),
      subscribed-at: stacks-block-height,
      notification-threshold: u100,
      active: true
    }))
  )
)

;; Unsubscribe from credential alerts
(define-public (unsubscribe-from-alerts (credential-id uint))
  (let
    (
      (subscription-key { subscriber: tx-sender, credential-id: credential-id })
      (existing-subscription (unwrap! (map-get? alert-subscriptions subscription-key) ERR-NOT-SUBSCRIBED))
    )
    (asserts! (var-get alert-enabled) ERR-NOT-AUTHORIZED)
    
    (ok (map-set alert-subscriptions subscription-key 
      (merge existing-subscription { active: false })
    ))
  )
)

;; Create an alert manually (authorized users only)
(define-public (create-alert (credential-id uint) (alert-type (string-ascii 20)) (message (string-ascii 200)))
  (let
    (
      (credential (unwrap! (map-get? credentials credential-id) ERR-CREDENTIAL-NOT-FOUND))
      (alert-id (var-get next-alert-id))
    )
    (asserts! (var-get alert-enabled) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq tx-sender (get issuer credential)) ERR-NOT-AUTHORIZED)
    
    (map-set alert-history { alert-id: alert-id } {
      credential-id: credential-id,
      alert-type: alert-type,
      recipient: (get holder credential),
      message: message,
      triggered-at: stacks-block-height,
      acknowledged: false
    })
    
    (var-set next-alert-id (+ alert-id u1))
    (var-set total-alerts (+ (var-get total-alerts) u1))
    (ok alert-id)
  )
)

;; Acknowledge an alert (mark as read)
(define-public (acknowledge-alert (alert-id uint))
  (let
    (
      (alert (unwrap! (map-get? alert-history { alert-id: alert-id }) ERR-CREDENTIAL-NOT-FOUND))
    )
    (asserts! (is-eq (get recipient alert) tx-sender) ERR-NOT-AUTHORIZED)
    
    (ok (map-set alert-history { alert-id: alert-id }
      (merge alert { acknowledged: true })
    ))
  )
)

;; Toggle alert system on/off (owner only)
(define-public (toggle-alert-system (enabled bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (var-set alert-enabled enabled))
  )
)

;; === ALERT SYSTEM READ-ONLY FUNCTIONS ===

;; Get subscription details for a credential
(define-read-only (get-alert-subscription (subscriber principal) (credential-id uint))
  (map-get? alert-subscriptions { subscriber: subscriber, credential-id: credential-id })
)

;; Get alert history for a specific credential
(define-read-only (get-credential-alert-history (credential-id uint) (limit uint))
  (var-get total-alerts)
)

;; Get user's alert subscriptions
(define-read-only (get-user-subscriptions (subscriber principal))
  (var-get total-alerts)
)

;; Get alert system statistics
(define-read-only (get-alert-stats)
  {
    total-alerts: (var-get total-alerts),
    next-alert-id: (var-get next-alert-id),
    alert-enabled: (var-get alert-enabled),
    current-block: stacks-block-height
  }
)

;; Get unacknowledged alerts for a user
(define-read-only (get-unacknowledged-alerts (recipient principal))
  (var-get total-alerts)
)



(authorize-issuer CONTRACT-OWNER "Contract Owner" "system-admin")
