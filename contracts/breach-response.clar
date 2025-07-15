;; Breach Response Contract
;; Manages privacy breach incidents and response procedures

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-INPUT (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-EXISTS (err u103))
(define-constant ERR-BREACH-ACTIVE (err u105))

;; Data Variables
(define-data-var next-incident-id uint u1)
(define-data-var active-breaches-count uint u0)
(define-data-var contract-admin principal tx-sender)
(define-map authorized-officers
  { officer: principal }
  { authorized: bool }
)

;; Data Maps
(define-map breach-incidents
  { incident-id: uint }
  {
    reporter: principal,
    severity-level: uint,
    affected-categories: (list 10 (string-ascii 50)),
    affected-users-count: uint,
    description: (string-ascii 500),
    status: (string-ascii 20),
    reported-block: uint,
    acknowledged-block: (optional uint),
    resolved-block: (optional uint),
    response-officer: (optional principal)
  }
)

(define-map breach-notifications
  { incident-id: uint, user: principal }
  {
    notification-sent: bool,
    notification-block: uint,
    acknowledgment-received: bool,
    acknowledgment-block: (optional uint)
  }
)

(define-map incident-actions
  { incident-id: uint, action-id: uint }
  {
    action-type: (string-ascii 50),
    description: (string-ascii 200),
    responsible-officer: principal,
    status: (string-ascii 20),
    created-block: uint,
    completed-block: (optional uint)
  }
)

;; Private Functions
(define-private (is-valid-severity (level uint))
  (and (>= level u1) (<= level u5))
)

(define-private (is-valid-incident-status (status (string-ascii 20)))
  (or
    (is-eq status "reported")
    (is-eq status "investigating")
    (is-eq status "contained")
    (is-eq status "resolved")
  )
)

(define-private (is-authorized-officer (officer principal))
  (or
    (is-eq officer (var-get contract-admin))
    (default-to false (get authorized (map-get? authorized-officers { officer: officer })))
  )
)

;; Public Functions

;; Add this public function to authorize officers
(define-public (authorize-officer (officer principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) ERR-NOT-AUTHORIZED)
    (map-set authorized-officers { officer: officer } { authorized: true })
    (ok true)
  )
)

;; Report a privacy breach
(define-public (report-breach
  (severity-level uint)
  (affected-categories (list 10 (string-ascii 50)))
  (affected-users-count uint)
  (description (string-ascii 500))
)
  (let
    (
      (incident-id (var-get next-incident-id))
    )
    (asserts! (is-valid-severity severity-level) ERR-INVALID-INPUT)
    (asserts! (> (len affected-categories) u0) ERR-INVALID-INPUT)
    (asserts! (> affected-users-count u0) ERR-INVALID-INPUT)

    (map-set breach-incidents
      { incident-id: incident-id }
      {
        reporter: tx-sender,
        severity-level: severity-level,
        affected-categories: affected-categories,
        affected-users-count: affected-users-count,
        description: description,
        status: "reported",
        reported-block: block-height,
        acknowledged-block: none,
        resolved-block: none,
        response-officer: none
      }
    )

    (var-set next-incident-id (+ incident-id u1))
    (var-set active-breaches-count (+ (var-get active-breaches-count) u1))
    (ok incident-id)
  )
)

;; Acknowledge breach incident
(define-public (acknowledge-breach (incident-id uint))
  (let
    (
      (incident-data (unwrap! (map-get? breach-incidents { incident-id: incident-id }) ERR-NOT-FOUND))
    )
    ;; Only verified privacy officers can acknowledge breaches
    (asserts! (is-authorized-officer tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status incident-data) "reported") ERR-INVALID-INPUT)

    (map-set breach-incidents
      { incident-id: incident-id }
      (merge incident-data
        {
          status: "investigating",
          acknowledged-block: (some block-height),
          response-officer: (some tx-sender)
        }
      )
    )
    (ok true)
  )
)

;; Update breach status
(define-public (update-breach-status (incident-id uint) (new-status (string-ascii 20)))
  (let
    (
      (incident-data (unwrap! (map-get? breach-incidents { incident-id: incident-id }) ERR-NOT-FOUND))
    )
    ;; Only the assigned response officer can update status
    (asserts! (is-some (get response-officer incident-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (some tx-sender) (get response-officer incident-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-incident-status new-status) ERR-INVALID-INPUT)

    (let
      (
        (updated-incident (merge incident-data { status: new-status }))
        (final-incident (if (is-eq new-status "resolved")
          (merge updated-incident { resolved-block: (some block-height) })
          updated-incident
        ))
      )
      (map-set breach-incidents { incident-id: incident-id } final-incident)

      ;; Decrease active breach count if resolved
      (if (is-eq new-status "resolved")
        (var-set active-breaches-count (- (var-get active-breaches-count) u1))
        true
      )
      (ok true)
    )
  )
)

;; Send breach notification to user
(define-public (send-breach-notification (incident-id uint) (user principal))
  (let
    (
      (incident-data (unwrap! (map-get? breach-incidents { incident-id: incident-id }) ERR-NOT-FOUND))
    )
    ;; Only verified privacy officers can send notifications
    (asserts! (is-authorized-officer tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? breach-notifications { incident-id: incident-id, user: user })) ERR-ALREADY-EXISTS)

    (map-set breach-notifications
      { incident-id: incident-id, user: user }
      {
        notification-sent: true,
        notification-block: block-height,
        acknowledgment-received: false,
        acknowledgment-block: none
      }
    )
    (ok true)
  )
)

;; User acknowledges breach notification
(define-public (acknowledge-notification (incident-id uint))
  (let
    (
      (notification-data (unwrap! (map-get? breach-notifications { incident-id: incident-id, user: tx-sender }) ERR-NOT-FOUND))
    )
    (asserts! (get notification-sent notification-data) ERR-INVALID-INPUT)
    (asserts! (not (get acknowledgment-received notification-data)) ERR-ALREADY-EXISTS)

    (map-set breach-notifications
      { incident-id: incident-id, user: tx-sender }
      (merge notification-data
        {
          acknowledgment-received: true,
          acknowledgment-block: (some block-height)
        }
      )
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get breach incident details
(define-read-only (get-breach-incident (incident-id uint))
  (map-get? breach-incidents { incident-id: incident-id })
)

;; Get breach notification status
(define-read-only (get-notification-status (incident-id uint) (user principal))
  (map-get? breach-notifications { incident-id: incident-id, user: user })
)

;; Get active breaches count
(define-read-only (get-active-breaches-count)
  (var-get active-breaches-count)
)

;; Check if there are active high-severity breaches
(define-read-only (has-critical-breaches)
  (> (var-get active-breaches-count) u0)
)

;; Get incident severity
(define-read-only (get-incident-severity (incident-id uint))
  (match (map-get? breach-incidents { incident-id: incident-id })
    incident-data
      (some (get severity-level incident-data))
    none
  )
)
