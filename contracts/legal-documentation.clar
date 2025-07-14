;; Legal Documentation Contract
;; Handles divorce paperwork preparation and filing

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVALID-INPUT (err u301))
(define-constant ERR-DOCUMENT-NOT-FOUND (err u302))
(define-constant ERR-DOCUMENT-ALREADY-FILED (err u303))
(define-constant ERR-INVALID-STATUS (err u304))

;; Data Variables
(define-data-var next-doc-case-id uint u1)
(define-data-var next-document-id uint u1)
(define-data-var filing-fee uint u1000000) ;; 1 STX in microSTX

;; Data Maps
(define-map documentation-cases
  { doc-case-id: uint }
  {
    petitioner: principal,
    respondent: principal,
    attorney: (optional principal),
    case-type: (string-ascii 50),
    jurisdiction: (string-ascii 100),
    status: (string-ascii 20),
    created-at: uint
  }
)

(define-map legal-documents
  { doc-case-id: uint, document-id: uint }
  {
    document-type: (string-ascii 100),
    title: (string-ascii 200),
    content-hash: (buff 32),
    filing-status: (string-ascii 20),
    required: bool,
    filed-at: (optional uint),
    filed-by: (optional principal)
  }
)

(define-map document-templates
  { template-id: uint }
  {
    name: (string-ascii 100),
    category: (string-ascii 50),
    required-fields: (string-ascii 500),
    template-hash: (buff 32)
  }
)

(define-map filing-requirements
  { jurisdiction: (string-ascii 100), requirement-id: uint }
  {
    document-type: (string-ascii 100),
    mandatory: bool,
    deadline-days: uint,
    fee-amount: uint
  }
)

;; Public Functions

;; Create documentation case
(define-public (create-documentation-case (respondent principal) (attorney (optional principal)) (case-type (string-ascii 50)) (jurisdiction (string-ascii 100)))
  (let
    (
      (doc-case-id (var-get next-doc-case-id))
    )
    (asserts! (not (is-eq tx-sender respondent)) ERR-INVALID-INPUT)

    (map-set documentation-cases
      { doc-case-id: doc-case-id }
      {
        petitioner: tx-sender,
        respondent: respondent,
        attorney: attorney,
        case-type: case-type,
        jurisdiction: jurisdiction,
        status: "preparation",
        created-at: block-height
      }
    )

    (var-set next-doc-case-id (+ doc-case-id u1))
    (ok doc-case-id)
  )
)

;; Add document to case
(define-public (add-document (doc-case-id uint) (document-type (string-ascii 100)) (title (string-ascii 200)) (content-hash (buff 32)) (required bool))
  (let
    (
      (case-data (unwrap! (map-get? documentation-cases { doc-case-id: doc-case-id }) ERR-INVALID-INPUT))
      (document-id (var-get next-document-id))
    )
    (asserts! (or (is-eq tx-sender (get petitioner case-data))
                  (is-eq tx-sender (get respondent case-data))
                  (match (get attorney case-data) attorney (is-eq tx-sender attorney) false)) ERR-NOT-AUTHORIZED)

    (map-set legal-documents
      { doc-case-id: doc-case-id, document-id: document-id }
      {
        document-type: document-type,
        title: title,
        content-hash: content-hash,
        filing-status: "draft",
        required: required,
        filed-at: none,
        filed-by: none
      }
    )

    (var-set next-document-id (+ document-id u1))
    (ok document-id)
  )
)

;; File document
(define-public (file-document (doc-case-id uint) (document-id uint))
  (let
    (
      (case-data (unwrap! (map-get? documentation-cases { doc-case-id: doc-case-id }) ERR-INVALID-INPUT))
      (doc-data (unwrap! (map-get? legal-documents { doc-case-id: doc-case-id, document-id: document-id }) ERR-DOCUMENT-NOT-FOUND))
    )
    (asserts! (or (is-eq tx-sender (get petitioner case-data))
                  (match (get attorney case-data) attorney (is-eq tx-sender attorney) false)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get filing-status doc-data) "draft") ERR-DOCUMENT-ALREADY-FILED)

    ;; Pay filing fee
    (try! (stx-transfer? (var-get filing-fee) tx-sender CONTRACT-OWNER))

    (map-set legal-documents
      { doc-case-id: doc-case-id, document-id: document-id }
      (merge doc-data {
        filing-status: "filed",
        filed-at: (some block-height),
        filed-by: (some tx-sender)
      })
    )

    (ok true)
  )
)

;; Update document status
(define-public (update-document-status (doc-case-id uint) (document-id uint) (new-status (string-ascii 20)))
  (let
    (
      (case-data (unwrap! (map-get? documentation-cases { doc-case-id: doc-case-id }) ERR-INVALID-INPUT))
      (doc-data (unwrap! (map-get? legal-documents { doc-case-id: doc-case-id, document-id: document-id }) ERR-DOCUMENT-NOT-FOUND))
    )
    (asserts! (or (is-eq tx-sender (get petitioner case-data))
                  (is-eq tx-sender (get respondent case-data))
                  (match (get attorney case-data) attorney (is-eq tx-sender attorney) false)) ERR-NOT-AUTHORIZED)

    (map-set legal-documents
      { doc-case-id: doc-case-id, document-id: document-id }
      (merge doc-data { filing-status: new-status })
    )

    (ok true)
  )
)

;; Update case status
(define-public (update-case-status (doc-case-id uint) (new-status (string-ascii 20)))
  (let
    (
      (case-data (unwrap! (map-get? documentation-cases { doc-case-id: doc-case-id }) ERR-INVALID-INPUT))
    )
    (asserts! (or (is-eq tx-sender (get petitioner case-data))
                  (match (get attorney case-data) attorney (is-eq tx-sender attorney) false)) ERR-NOT-AUTHORIZED)

    (map-set documentation-cases
      { doc-case-id: doc-case-id }
      (merge case-data { status: new-status })
    )

    (ok true)
  )
)

;; Add document template
(define-public (add-template (template-id uint) (name (string-ascii 100)) (category (string-ascii 50)) (required-fields (string-ascii 500)) (template-hash (buff 32)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set document-templates
      { template-id: template-id }
      {
        name: name,
        category: category,
        required-fields: required-fields,
        template-hash: template-hash
      }
    )

    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-documentation-case (doc-case-id uint))
  (map-get? documentation-cases { doc-case-id: doc-case-id })
)

(define-read-only (get-document (doc-case-id uint) (document-id uint))
  (map-get? legal-documents { doc-case-id: doc-case-id, document-id: document-id })
)

(define-read-only (get-template (template-id uint))
  (map-get? document-templates { template-id: template-id })
)

(define-read-only (get-filing-fee)
  (var-get filing-fee)
)
