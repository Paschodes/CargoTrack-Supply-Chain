;; CargoTrack Supply Chain
;; Decentralized automotive parts tracking system for supply chain management
(define-data-var contract-owner principal tx-sender)

;; Part status enum values
(define-constant STATUS-MANUFACTURED u1)
(define-constant STATUS-SHIPPED u2)
(define-constant STATUS-RECEIVED u3)
(define-constant STATUS-INSTALLED u4)
(define-constant STATUS-RECALLED u5)

;; Map of part serial numbers to part data
(define-map parts
  {serial: (string-ascii 50)}
  {
    part-type: (string-ascii 100),
    manufacturer: principal,
    production-date: uint,
    current-status: uint,
    current-owner: principal,
    vehicle-vin: (optional (string-ascii 17))
  }
)

;; Map of part history events
(define-map part-history
  {serial: (string-ascii 50), index: uint}
  {
    timestamp: uint,
    status: uint,
    handler: principal,
    location: (string-ascii 100),
    notes: (string-ascii 500)
  }
)

;; Map of history event count for each part
(define-map history-count
  {serial: (string-ascii 50)}
  {count: uint}
)

;; Map of authorized manufacturers
(define-map authorized-manufacturers
  {address: principal}
  {name: (string-ascii 100), is-active: bool}
)

;; Function to register a new manufacturer
(define-public (register-manufacturer (manufacturer principal) (name (string-ascii 100)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err u1)) ;; Error code 1: Not authorized
    (asserts! (> (len name) u0) (err u6)) ;; Error code 6: Empty name
    (asserts! (not (is-eq manufacturer tx-sender)) (err u13)) ;; Error code 13: Cannot register self as manufacturer
    (map-set authorized-manufacturers
      {address: manufacturer}
      {name: name, is-active: true}
    )
    (ok true)
  )
)

;; Function to register a new part
(define-public (register-part 
                (serial (string-ascii 50))
                (part-type (string-ascii 100))
                (production-date uint))
  (let ((manufacturer-data (map-get? authorized-manufacturers {address: tx-sender})))
    (asserts! (and (is-some manufacturer-data) 
                   (get is-active (unwrap-panic manufacturer-data))) 
              (err u2)) ;; Error code 2: Not an authorized manufacturer
    (asserts! (> (len serial) u0) (err u7)) ;; Error code 7: Empty serial
    (asserts! (> (len part-type) u0) (err u8)) ;; Error code 8: Empty part type
    (asserts! (> production-date u0) (err u14)) ;; Error code 14: Invalid production date
    (asserts! (is-none (map-get? parts {serial: serial})) (err u3)) ;; Error code 3: Part already exists
    
    (map-set parts
      {serial: serial}
      {
        part-type: part-type,
        manufacturer: tx-sender,
        production-date: production-date,
        current-status: STATUS-MANUFACTURED,
        current-owner: tx-sender,
        vehicle-vin: none
      }
    )
    
    ;; Initialize history with first entry
    (map-set part-history
      {serial: serial, index: u0}
      {
        timestamp: stacks-block-height,
        status: STATUS-MANUFACTURED,
        handler: tx-sender,
        location: "Manufacturing",
        notes: "Part manufactured and registered"
      }
    )
    (map-set history-count {serial: serial} {count: u1})
    
    (ok true)
  )
)

;; Function to update part status
(define-public (update-part-status 
                (serial (string-ascii 50))
                (new-status uint)
                (location (string-ascii 100))
                (notes (string-ascii 500)))
  (let ((part-data (map-get? parts {serial: serial}))
        (history-data (default-to {count: u0} (map-get? history-count {serial: serial})))
        (history-index (get count history-data)))
    
    (asserts! (> (len serial) u0) (err u7)) ;; Error code 7: Empty serial
    (asserts! (> (len location) u0) (err u9)) ;; Error code 9: Empty location
    (asserts! (> (len notes) u0) (err u10)) ;; Error code 10: Empty notes
    (asserts! (is-some part-data) (err u4)) ;; Error code 4: Part not found
    (asserts! (and (>= new-status STATUS-MANUFACTURED) (<= new-status STATUS-RECALLED)) 
              (err u5)) ;; Error code 5: Invalid status
    
    ;; Update part status
    (map-set parts
      {serial: serial}
      (merge (unwrap-panic part-data)
             {
               current-status: new-status,
               current-owner: tx-sender
             }
      )
    )
    
    ;; Add history entry
    (map-set part-history
      {serial: serial, index: history-index}
      {
        timestamp: stacks-block-height,
        status: new-status,
        handler: tx-sender,
        location: location,
        notes: notes
      }
    )
    (map-set history-count 
      {serial: serial} 
      {count: (+ history-index u1)}
    )
    
    (ok true)
  )
)

;; Function to assign part to a vehicle
(define-public (assign-to-vehicle (serial (string-ascii 50)) (vin (string-ascii 17)))
  (let ((part-data (map-get? parts {serial: serial}))
        (history-data (default-to {count: u0} (map-get? history-count {serial: serial})))
        (history-index (get count history-data)))
    
    (asserts! (> (len serial) u0) (err u7)) ;; Error code 7: Empty serial
    (asserts! (> (len vin) u0) (err u11)) ;; Error code 11: Empty VIN
    (asserts! (is-some part-data) (err u4)) ;; Error code 4: Part not found
    
    ;; Update part with VIN and status
    (map-set parts
      {serial: serial}
      (merge (unwrap-panic part-data)
             {
               current-status: STATUS-INSTALLED,
               vehicle-vin: (some vin)
             }
      )
    )
    
    ;; Add history entry
    (map-set part-history
      {serial: serial, index: history-index}
      {
        timestamp: stacks-block-height,
        status: STATUS-INSTALLED,
        handler: tx-sender,
        location: "Vehicle Assembly",
        notes: (concat "Installed in vehicle VIN: " vin)
      }
    )
    (map-set history-count 
      {serial: serial} 
      {count: (+ history-index u1)}
    )
    
    (ok true)
  )
)

;; Function to recall a part
(define-public (recall-part (serial (string-ascii 50)) (reason (string-ascii 500)))
  (let ((part-data (map-get? parts {serial: serial}))
        (history-data (default-to {count: u0} (map-get? history-count {serial: serial})))
        (history-index (get count history-data)))
    
    (asserts! (> (len serial) u0) (err u7)) ;; Error code 7: Empty serial
    (asserts! (> (len reason) u0) (err u12)) ;; Error code 12: Empty reason
    (asserts! (is-some part-data) (err u4)) ;; Error code 4: Part not found
    (asserts! (is-eq tx-sender (get manufacturer (unwrap-panic part-data))) 
              (err u1)) ;; Error code 1: Not authorized
    
    ;; Update part status to recalled
    (map-set parts
      {serial: serial}
      (merge (unwrap-panic part-data)
             {current-status: STATUS-RECALLED}
      )
    )
    
    ;; Add history entry
    (map-set part-history
      {serial: serial, index: history-index}
      {
        timestamp: stacks-block-height,
        status: STATUS-RECALLED,
        handler: tx-sender,
        location: "Manufacturer",
        notes: reason
      }
    )
    (map-set history-count 
      {serial: serial} 
      {count: (+ history-index u1)}
    )
    
    (ok true)
  )
)

;; Read-only function to get part information
(define-read-only (get-part-info (serial (string-ascii 50)))
  (map-get? parts {serial: serial})
)

;; Read-only function to get history entry
(define-read-only (get-history-entry (serial (string-ascii 50)) (index uint))
  (map-get? part-history {serial: serial, index: index})
)

;; Read-only function to get history count
(define-read-only (get-history-count (serial (string-ascii 50)))
  (default-to {count: u0} (map-get? history-count {serial: serial}))
)

;; Read-only function to check if a manufacturer is authorized
(define-read-only (is-authorized-manufacturer (address principal))
  (let ((manufacturer-data (map-get? authorized-manufacturers {address: address})))
    (if (is-some manufacturer-data)
        (get is-active (unwrap-panic manufacturer-data))
        false
    )
  )
)