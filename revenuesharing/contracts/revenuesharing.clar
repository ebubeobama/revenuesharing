;; Revenue Sharing - Decentralized Creator Monetization Platform
;; Automated revenue distribution with vesting and flexible splits

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u800))
(define-constant err-not-authorized (err u801))
(define-constant err-project-not-found (err u802))
(define-constant err-invalid-amount (err u803))
(define-constant err-stakeholder-not-found (err u804))
(define-constant err-stakeholder-exists (err u805))
(define-constant err-invalid-percentage (err u806))
(define-constant err-allocation-overflow (err u807))
(define-constant err-insufficient-balance (err u808))
(define-constant err-nothing-to-withdraw (err u809))
(define-constant err-project-inactive (err u810))
(define-constant err-invalid-vesting (err u811))
(define-constant err-not-fully-vested (err u812))
(define-constant err-cannot-remove (err u813))
(define-constant err-distribution-locked (err u814))
(define-constant err-zero-stakeholders (err u815))
(define-constant err-already-distributed (err u816))
(define-constant err-invalid-cliff (err u817))
(define-constant err-percentage-sum-invalid (err u818))
(define-constant err-no-revenue (err u819))

;; Project status
(define-constant status-active u1)
(define-constant status-paused u2)
(define-constant status-closed u3)

;; Data Variables
(define-data-var total-projects uint u0)
(define-data-var total-revenue-distributed uint u0)
(define-data-var total-stakeholders uint u0)

;; Data Maps

;; Projects
(define-map projects
  uint
  {
    creator: principal,
    name: (string-ascii 100),
    description: (string-ascii 500),
    total-revenue-received: uint,
    total-distributed: uint,
    pool-balance: uint,
    stakeholder-count: uint,
    distribution-frequency: uint,
    last-distribution: uint,
    status: uint,
    created-at: uint
  }
)

;; Stakeholders
(define-map stakeholders
  { project-id: uint, stakeholder: principal }
  {
    allocation-percentage: uint,
    role: (string-ascii 50),
    vesting-duration: uint,
    vesting-start: uint,
    cliff-period: uint,
    total-allocated: uint,
    total-withdrawn: uint,
    pending-balance: uint,
    active: bool,
    added-at: uint
  }
)

;; Track all stakeholders per project for iteration
(define-map project-stakeholder-list
  { project-id: uint, index: uint }
  principal
)

;; Distribution records
(define-map distributions
  { project-id: uint, distribution-id: uint }
  {
    amount: uint,
    timestamp: uint,
    stakeholders-paid: uint
  }
)

(define-map project-distribution-count uint uint)

;; Total allocation tracking per project
(define-map project-total-allocation uint uint)

;; Private Functions

(define-private (is-contract-owner)
  (is-eq tx-sender contract-owner)
)

(define-private (is-project-creator (project-id uint))
  (match (map-get? projects project-id)
    project (is-eq tx-sender (get creator project))
    false
  )
)

(define-private (get-stakeholder-info (project-id uint) (stakeholder principal))
  (map-get? stakeholders { project-id: project-id, stakeholder: stakeholder })
)

(define-private (calculate-vested-percentage (vesting-start uint) (vesting-duration uint) (cliff-period uint))
  (let
    (
      (elapsed (if (>= stacks-block-height vesting-start) (- stacks-block-height vesting-start) u0))
      (cliff-passed (>= elapsed cliff-period))
    )
    (if (not cliff-passed)
      u0
      (if (is-eq vesting-duration u0)
        u10000
        (if (>= elapsed vesting-duration)
          u10000
          (/ (* elapsed u10000) vesting-duration)
        )
      )
    )
  )
)

(define-private (calculate-stakeholder-vested-amount 
    (total-allocated uint)
    (already-withdrawn uint)
    (vesting-start uint)
    (vesting-duration uint)
    (cliff-period uint)
  )
  (let
    (
      (vested-pct (calculate-vested-percentage vesting-start vesting-duration cliff-period))
      (total-vested (/ (* total-allocated vested-pct) u10000))
      (available (if (> total-vested already-withdrawn)
        (- total-vested already-withdrawn)
        u0
      ))
    )
    available
  )
)

;; Public Functions

;; Create a revenue-sharing project
(define-public (create-project
    (name (string-ascii 100))
    (description (string-ascii 500))
    (distribution-frequency uint)
  )
  (let
    (
      (project-id (var-get total-projects))
      (creator tx-sender)
    )
    (asserts! (> (len name) u0) err-invalid-amount)
    (asserts! (> distribution-frequency u0) err-invalid-amount)
    
    (map-set projects project-id
      {
        creator: creator,
        name: name,
        description: description,
        total-revenue-received: u0,
        total-distributed: u0,
        pool-balance: u0,
        stakeholder-count: u0,
        distribution-frequency: distribution-frequency,
        last-distribution: stacks-block-height,
        status: status-active,
        created-at: stacks-block-height
      }
    )
    
    (map-set project-total-allocation project-id u0)
    (var-set total-projects (+ project-id u1))
    (ok project-id)
  )
)

;; Add a stakeholder with vesting
(define-public (add-stakeholder
    (project-id uint)
    (stakeholder principal)
    (allocation-percentage uint)
    (role (string-ascii 50))
    (vesting-duration uint)
    (cliff-period uint)
  )
  (let
    (
      (project (unwrap! (map-get? projects project-id) err-project-not-found))
      (current-total (default-to u0 (map-get? project-total-allocation project-id)))
      (new-total (+ current-total allocation-percentage))
    )
    (asserts! (is-project-creator project-id) err-not-authorized)
    (asserts! (is-eq (get status project) status-active) err-project-inactive)
    (asserts! (is-none (get-stakeholder-info project-id stakeholder)) err-stakeholder-exists)
    (asserts! (> allocation-percentage u0) err-invalid-percentage)
    (asserts! (<= new-total u10000) err-allocation-overflow)
    (asserts! (<= cliff-period vesting-duration) err-invalid-cliff)
    
    (map-set stakeholders
      { project-id: project-id, stakeholder: stakeholder }
      {
        allocation-percentage: allocation-percentage,
        role: role,
        vesting-duration: vesting-duration,
        vesting-start: stacks-block-height,
        cliff-period: cliff-period,
        total-allocated: u0,
        total-withdrawn: u0,
        pending-balance: u0,
        active: true,
        added-at: stacks-block-height
      }
    )
    
    (map-set project-stakeholder-list
      { project-id: project-id, index: (get stakeholder-count project) }
      stakeholder
    )
    
    (map-set projects project-id
      (merge project {
        stakeholder-count: (+ (get stakeholder-count project) u1)
      })
    )
    
    (map-set project-total-allocation project-id new-total)
    (var-set total-stakeholders (+ (var-get total-stakeholders) u1))
    
    (ok true)
  )
)

;; Deposit revenue to project pool
(define-public (deposit-revenue (project-id uint) (amount uint))
  (let
    (
      (project (unwrap! (map-get? projects project-id) err-project-not-found))
      (depositor tx-sender)
    )
    (asserts! (is-eq (get status project) status-active) err-project-inactive)
    (asserts! (> amount u0) err-invalid-amount)
    
    (try! (stx-transfer? amount depositor (as-contract tx-sender)))
    
    (map-set projects project-id
      (merge project {
        total-revenue-received: (+ (get total-revenue-received project) amount),
        pool-balance: (+ (get pool-balance project) amount)
      })
    )
    
    (ok true)
  )
)

;; Distribute revenue to a single stakeholder (called individually)
(define-public (distribute-to-stakeholder (project-id uint) (stakeholder principal))
  (let
    (
      (project (unwrap! (map-get? projects project-id) err-project-not-found))
      (stakeholder-data (unwrap! (get-stakeholder-info project-id stakeholder) err-stakeholder-not-found))
      (pool-balance (get pool-balance project))
      (share (/ (* pool-balance (get allocation-percentage stakeholder-data)) u10000))
    )
    (asserts! (is-project-creator project-id) err-not-authorized)
    (asserts! (is-eq (get status project) status-active) err-project-inactive)
    (asserts! (get active stakeholder-data) err-not-authorized)
    
    (map-set stakeholders
      { project-id: project-id, stakeholder: stakeholder }
      (merge stakeholder-data {
        total-allocated: (+ (get total-allocated stakeholder-data) share),
        pending-balance: (+ (get pending-balance stakeholder-data) share)
      })
    )
    
    (ok share)
  )
)

;; Finalize distribution after all stakeholders are paid
(define-public (finalize-distribution (project-id uint))
  (let
    (
      (project (unwrap! (map-get? projects project-id) err-project-not-found))
      (pool-balance (get pool-balance project))
      (distribution-id (default-to u0 (map-get? project-distribution-count project-id)))
    )
    (asserts! (is-project-creator project-id) err-not-authorized)
    (asserts! (is-eq (get status project) status-active) err-project-inactive)
    (asserts! (> pool-balance u0) err-no-revenue)
    
    (map-set distributions
      { project-id: project-id, distribution-id: distribution-id }
      {
        amount: pool-balance,
        timestamp: stacks-block-height,
        stakeholders-paid: (get stakeholder-count project)
      }
    )
    
    (map-set project-distribution-count project-id (+ distribution-id u1))
    
    (map-set projects project-id
      (merge project {
        pool-balance: u0,
        total-distributed: (+ (get total-distributed project) pool-balance),
        last-distribution: stacks-block-height
      })
    )
    
    (var-set total-revenue-distributed (+ (var-get total-revenue-distributed) pool-balance))
    (ok pool-balance)
  )
)

;; Withdraw available earnings
(define-public (withdraw-earnings (project-id uint))
  (let
    (
      (project (unwrap! (map-get? projects project-id) err-project-not-found))
      (withdrawer tx-sender)
      (stakeholder-data (unwrap! (get-stakeholder-info project-id withdrawer) err-stakeholder-not-found))
      (vested-amount (calculate-stakeholder-vested-amount
        (get total-allocated stakeholder-data)
        (get total-withdrawn stakeholder-data)
        (get vesting-start stakeholder-data)
        (get vesting-duration stakeholder-data)
        (get cliff-period stakeholder-data)
      ))
      (withdrawable (if (<= vested-amount (get pending-balance stakeholder-data))
        vested-amount
        (get pending-balance stakeholder-data)
      ))
    )
    (asserts! (get active stakeholder-data) err-not-authorized)
    (asserts! (> withdrawable u0) err-nothing-to-withdraw)
    
    (map-set stakeholders
      { project-id: project-id, stakeholder: withdrawer }
      (merge stakeholder-data {
        total-withdrawn: (+ (get total-withdrawn stakeholder-data) withdrawable),
        pending-balance: (- (get pending-balance stakeholder-data) withdrawable)
      })
    )
    
    (try! (as-contract (stx-transfer? withdrawable tx-sender withdrawer)))
    (ok withdrawable)
  )
)

;; Update stakeholder allocation (only if no distributions yet)
(define-public (update-stakeholder-allocation (project-id uint) (stakeholder principal) (new-percentage uint))
  (let
    (
      (project (unwrap! (map-get? projects project-id) err-project-not-found))
      (stakeholder-data (unwrap! (get-stakeholder-info project-id stakeholder) err-stakeholder-not-found))
      (current-total (default-to u0 (map-get? project-total-allocation project-id)))
      (old-percentage (get allocation-percentage stakeholder-data))
      (new-total (+ (- current-total old-percentage) new-percentage))
    )
    (asserts! (is-project-creator project-id) err-not-authorized)
    (asserts! (is-eq (get total-allocated stakeholder-data) u0) err-already-distributed)
    (asserts! (<= new-total u10000) err-allocation-overflow)
    (asserts! (> new-percentage u0) err-invalid-percentage)
    
    (map-set stakeholders
      { project-id: project-id, stakeholder: stakeholder }
      (merge stakeholder-data { allocation-percentage: new-percentage })
    )
    
    (map-set project-total-allocation project-id new-total)
    (ok true)
  )
)

;; Remove stakeholder (only if no earnings pending)
(define-public (remove-stakeholder (project-id uint) (stakeholder principal))
  (let
    (
      (project (unwrap! (map-get? projects project-id) err-project-not-found))
      (stakeholder-data (unwrap! (get-stakeholder-info project-id stakeholder) err-stakeholder-not-found))
      (current-total (default-to u0 (map-get? project-total-allocation project-id)))
    )
    (asserts! (is-project-creator project-id) err-not-authorized)
    (asserts! (is-eq (get pending-balance stakeholder-data) u0) err-cannot-remove)
    (asserts! (is-eq (get total-allocated stakeholder-data) (get total-withdrawn stakeholder-data)) err-cannot-remove)
    
    (map-set stakeholders
      { project-id: project-id, stakeholder: stakeholder }
      (merge stakeholder-data { active: false })
    )
    
    (map-set project-total-allocation project-id 
      (- current-total (get allocation-percentage stakeholder-data))
    )
    
    (ok true)
  )
)

;; Pause project distributions
(define-public (pause-project (project-id uint))
  (let
    (
      (project (unwrap! (map-get? projects project-id) err-project-not-found))
    )
    (asserts! (is-project-creator project-id) err-not-authorized)
    
    (map-set projects project-id
      (merge project { status: status-paused })
    )
    
    (ok true)
  )
)

;; Resume project distributions
(define-public (resume-project (project-id uint))
  (let
    (
      (project (unwrap! (map-get? projects project-id) err-project-not-found))
    )
    (asserts! (is-project-creator project-id) err-not-authorized)
    
    (map-set projects project-id
      (merge project { status: status-active })
    )
    
    (ok true)
  )
)

;; Read-Only Functions

(define-read-only (get-project-details (project-id uint))
  (map-get? projects project-id)
)

(define-read-only (get-stakeholder-details (project-id uint) (stakeholder principal))
  (get-stakeholder-info project-id stakeholder)
)

(define-read-only (get-project-balance (project-id uint))
  (match (map-get? projects project-id)
    project (ok (get pool-balance project))
    err-project-not-found
  )
)

(define-read-only (calculate-stakeholder-share (project-id uint) (stakeholder principal) (amount uint))
  (match (get-stakeholder-info project-id stakeholder)
    stakeholder-data (ok (/ (* amount (get allocation-percentage stakeholder-data)) u10000))
    err-stakeholder-not-found
  )
)

(define-read-only (get-vested-amount (project-id uint) (stakeholder principal))
  (match (get-stakeholder-info project-id stakeholder)
    stakeholder-data (ok (calculate-stakeholder-vested-amount
      (get total-allocated stakeholder-data)
      (get total-withdrawn stakeholder-data)
      (get vesting-start stakeholder-data)
      (get vesting-duration stakeholder-data)
      (get cliff-period stakeholder-data)
    ))
    err-stakeholder-not-found
  )
)

(define-read-only (get-withdrawable-amount (project-id uint) (stakeholder principal))
  (match (get-stakeholder-info project-id stakeholder)
    stakeholder-data (let
      (
        (vested (calculate-stakeholder-vested-amount
          (get total-allocated stakeholder-data)
          (get total-withdrawn stakeholder-data)
          (get vesting-start stakeholder-data)
          (get vesting-duration stakeholder-data)
          (get cliff-period stakeholder-data)
        ))
        (pending (get pending-balance stakeholder-data))
      )
      (ok (if (<= vested pending) vested pending))
    )
    err-stakeholder-not-found
  )
)

(define-read-only (get-total-earnings (project-id uint) (stakeholder principal))
  (match (get-stakeholder-info project-id stakeholder)
    stakeholder-data (ok (get total-allocated stakeholder-data))
    err-stakeholder-not-found
  )
)

(define-read-only (get-project-stats)
  {
    total-projects: (var-get total-projects),
    total-distributed: (var-get total-revenue-distributed),
    total-stakeholders: (var-get total-stakeholders)
  }
)

(define-read-only (verify-allocations (project-id uint))
  (ok (default-to u0 (map-get? project-total-allocation project-id)))
)

(define-read-only (is-fully-vested (project-id uint) (stakeholder principal))
  (match (get-stakeholder-info project-id stakeholder)
    stakeholder-data (ok (is-eq
      (calculate-vested-percentage
        (get vesting-start stakeholder-data)
        (get vesting-duration stakeholder-data)
        (get cliff-period stakeholder-data)
      )
      u10000
    ))
    err-stakeholder-not-found
  )
)

(define-read-only (get-allocation-percentage (project-id uint) (stakeholder principal))
  (match (get-stakeholder-info project-id stakeholder)
    stakeholder-data (ok (get allocation-percentage stakeholder-data))
    err-stakeholder-not-found
  )
)

(define-read-only (get-stakeholder-at-index (project-id uint) (index uint))
  (map-get? project-stakeholder-list { project-id: project-id, index: index })
)