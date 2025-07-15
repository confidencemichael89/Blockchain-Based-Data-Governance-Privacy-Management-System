;; Compliance Monitoring Contract
;; Monitors system-wide privacy compliance and generates reports

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-INPUT (err u101))
(define-constant ERR-NOT-FOUND (err u102))

;; Data Variables
(define-data-var next-audit-id uint u1)
(define-data-var last-compliance-check uint u0)
(define-data-var compliance-score uint u100)
(define-data-var contract-admin principal tx-sender)
(define-map authorized-officers
  { officer: principal }
  { authorized: bool }
)

;; Data Maps
(define-map compliance-audits
  { audit-id: uint }
  {
    auditor: principal,
    audit-type: (string-ascii 50),
    scope: (list 10 (string-ascii 50)),
    findings: (string-ascii 1000),
    compliance-score: uint,
    recommendations: (string-ascii 1000),
    audit-block: uint,
    status: (string-ascii 20)
  }
)

(define-map compliance-metrics
  { metric-name: (string-ascii 50), period-block: uint }
  {
    value: uint,
    threshold: uint,
    status: (string-ascii 20),
    last-updated: uint
  }
)

(define-map violation-records
  { violation-id: uint }
  {
    violation-type: (string-ascii 100),
    severity: uint,
    description: (string-ascii 500),
    detected-block: uint,
    resolved: bool,
    resolution-block: (optional uint)
  }
)

;; Private Functions
(define-private (is-valid-compliance-score (score uint))
  (and (>= score u0) (<= score u100))
)

(define-private (is-valid-audit-status (status (string-ascii 20)))
  (or
    (is-eq status "planned")
    (is-eq status "in-progress")
    (is-eq status "completed")
    (is-eq status "reviewed")
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

;; Create compliance audit
(define-public (create-audit
  (audit-type (string-ascii 50))
  (scope (list 10 (string-ascii 50)))
  (findings (string-ascii 1000))
  (score uint)
  (recommendations (string-ascii 1000))
)
  (let
    (
      (audit-id (var-get next-audit-id))
    )
    ;; Only verified privacy officers can create audits
    (asserts! (is-authorized-officer tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-compliance-score score) ERR-INVALID-INPUT)
    (asserts! (> (len scope) u0) ERR-INVALID-INPUT)

    (map-set compliance-audits
      { audit-id: audit-id }
      {
        auditor: tx-sender,
        audit-type: audit-type,
        scope: scope,
        findings: findings,
        compliance-score: score,
        recommendations: recommendations,
        audit-block: block-height,
        status: "completed"
      }
    )

    ;; Update overall compliance score
    (var-set compliance-score score)
    (var-set last-compliance-check block-height)
    (var-set next-audit-id (+ audit-id u1))
    (ok audit-id)
  )
)

;; Record compliance metric
(define-public (record-metric
  (metric-name (string-ascii 50))
  (value uint)
  (threshold uint)
)
  (begin
    ;; Only verified privacy officers can record metrics
    (asserts! (is-authorized-officer tx-sender) ERR-NOT-AUTHORIZED)

    (let
      (
        (status (if (<= value threshold) "compliant" "non-compliant"))
      )
      (map-set compliance-metrics
        { metric-name: metric-name, period-block: block-height }
        {
          value: value,
          threshold: threshold,
          status: status,
          last-updated: block-height
        }
      )
      (ok true)
    )
  )
)

;; Record compliance violation
(define-public (record-violation
  (violation-type (string-ascii 100))
  (severity uint)
  (description (string-ascii 500))
)
  (let
    (
      (violation-id (var-get next-audit-id))
    )
    ;; Only verified privacy officers can record violations
    (asserts! (is-authorized-officer tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= severity u1) (<= severity u5)) ERR-INVALID-INPUT)

    (map-set violation-records
      { violation-id: violation-id }
      {
        violation-type: violation-type,
        severity: severity,
        description: description,
        detected-block: block-height,
        resolved: false,
        resolution-block: none
      }
    )

    ;; Adjust compliance score based on severity
    (let
      (
        (current-score (var-get compliance-score))
        (penalty (* severity u5))
        (new-score (if (>= current-score penalty) (- current-score penalty) u0))
      )
      (var-set compliance-score new-score)
    )

    (var-set next-audit-id (+ violation-id u1))
    (ok violation-id)
  )
)

;; Resolve compliance violation
(define-public (resolve-violation (violation-id uint))
  (let
    (
      (violation-data (unwrap! (map-get? violation-records { violation-id: violation-id }) ERR-NOT-FOUND))
    )
    ;; Only verified privacy officers can resolve violations
    (asserts! (is-authorized-officer tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (get resolved violation-data)) ERR-INVALID-INPUT)

    (map-set violation-records
      { violation-id: violation-id }
      (merge violation-data
        {
          resolved: true,
          resolution-block: (some block-height)
        }
      )
    )

    ;; Improve compliance score when violation is resolved
    (let
      (
        (current-score (var-get compliance-score))
        (improvement (* (get severity violation-data) u3))
        (new-score (if (<= (+ current-score improvement) u100)
                     (+ current-score improvement)
                     u100))
      )
      (var-set compliance-score new-score)
    )
    (ok true)
  )
)

;; Perform automated compliance check
(define-public (perform-compliance-check)
  (begin
    ;; Only verified privacy officers can perform checks
    (asserts! (is-authorized-officer tx-sender) ERR-NOT-AUTHORIZED)

    ;; Check for active breaches
    (let
      (
        ;; Assuming active breaches are tracked locally, replace with appropriate logic
        (active-breaches u0)
        (breach-penalty (* active-breaches u10))
        (current-score (var-get compliance-score))
        (adjusted-score (if (>= current-score breach-penalty)
                          (- current-score breach-penalty)
                          u0))
      )
      (var-set compliance-score adjusted-score)
      (var-set last-compliance-check block-height)
      (ok adjusted-score)
    )
  )
)

;; Read-only Functions

;; Get audit details
(define-read-only (get-audit (audit-id uint))
  (map-get? compliance-audits { audit-id: audit-id })
)

;; Get compliance metric
(define-read-only (get-metric (metric-name (string-ascii 50)) (period-block uint))
  (map-get? compliance-metrics { metric-name: metric-name, period-block: period-block })
)

;; Get violation record
(define-read-only (get-violation (violation-id uint))
  (map-get? violation-records { violation-id: violation-id })
)

;; Get current compliance score
(define-read-only (get-compliance-score)
  (var-get compliance-score)
)

;; Get last compliance check block
(define-read-only (get-last-compliance-check)
  (var-get last-compliance-check)
)

;; Check if system is compliant
(define-read-only (is-system-compliant)
  (>= (var-get compliance-score) u80)
)

;; Get compliance status
(define-read-only (get-compliance-status)
  (let
    (
      (score (var-get compliance-score))
    )
    (if (>= score u90)
      "excellent"
      (if (>= score u80)
        "good"
        (if (>= score u70)
          "acceptable"
          (if (>= score u50)
            "needs-improvement"
            "critical"
          )
        )
      )
    )
  )
)
