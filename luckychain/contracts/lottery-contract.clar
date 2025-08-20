;; Play-to-Earn Lottery Contract
;; Players buy tickets, winners selected randomly, multiple prize tiers

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-lottery-not-active (err u103))
(define-constant err-lottery-not-ended (err u104))
(define-constant err-insufficient-funds (err u105))
(define-constant err-max-tickets-reached (err u106))
(define-constant err-invalid-numbers (err u107))
(define-constant err-already-claimed (err u108))
(define-constant err-no-tickets (err u109))

;; Data Variables
(define-data-var current-lottery-id uint u1)
(define-data-var ticket-price uint u100000) ;; 0.1 STX
(define-data-var max-tickets-per-lottery uint u1000)
(define-data-var max-tickets-per-player uint u50)
(define-data-var lottery-duration uint u144) ;; blocks (~24 hours)

;; Lottery structure
(define-map lotteries 
  uint 
  {
    status: (string-ascii 16), ;; "active", "drawing", "ended"
    start-block: uint,
    end-block: uint,
    ticket-count: uint,
    prize-pool: uint,
    winner-count: uint,
    drawn-numbers: (list 6 uint),
    jackpot-winner: (optional principal),
    house-fee: uint
  }
)

;; Ticket structure
(define-map tickets 
  {lottery-id: uint, ticket-id: uint} 
  {
    owner: principal,
    numbers: (list 6 uint),
    purchase-block: uint,
    matches: uint,
    prize-claimed: bool,
    prize-amount: uint
  }
)

;; Player ticket tracking
(define-map player-tickets 
  {lottery-id: uint, player: principal} 
  {
    ticket-ids: (list 50 uint),
    ticket-count: uint,
    total-spent: uint,
    total-won: uint
  }
)

;; Player statistics
(define-map player-stats 
  principal 
  {
    total-tickets-bought: uint,
    total-spent: uint,
    total-won: uint,
    lotteries-played: uint,
    biggest-win: uint,
    jackpots-won: uint
  }
)

;; Lottery statistics
(define-map lottery-stats 
  uint 
  {
    jackpot-amount: uint,
    second-tier-amount: uint,
    third-tier-amount: uint,
    total-distributed: uint,
    house-earnings: uint
  }
)

;; Random seed for number generation
(define-data-var random-seed uint u12345)

;; Initialize new lottery
(define-public (start-new-lottery)
  (let 
    (
      (lottery-id (var-get current-lottery-id))
      (current-block block-height)
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set lotteries lottery-id
      {
        status: "active",
        start-block: current-block,
        end-block: (+ current-block (var-get lottery-duration)),
        ticket-count: u0,
        prize-pool: u0,
        winner-count: u0,
        drawn-numbers: (list),
        jackpot-winner: none,
        house-fee: u0
      }
    )
    
    (var-set current-lottery-id (+ lottery-id u1))
    (ok lottery-id)
  )
)

;; Buy lottery ticket with chosen numbers
(define-public (buy-ticket (lottery-id uint) (numbers (list 6 uint)))
  (let 
    (
      (lottery (unwrap! (map-get? lotteries lottery-id) err-not-found))
      (player-data (default-to 
                     {ticket-ids: (list), ticket-count: u0, total-spent: u0, total-won: u0}
                     (map-get? player-tickets {lottery-id: lottery-id, player: tx-sender})))
      (ticket-id (+ (get ticket-count lottery) u1))
      (player-stats-data (default-to 
                           {total-tickets-bought: u0, total-spent: u0, total-won: u0, lotteries-played: u0, biggest-win: u0, jackpots-won: u0}
                           (map-get? player-stats tx-sender)))
    )
    
    ;; Validate lottery and ticket conditions
    (asserts! (is-eq (get status lottery) "active") err-lottery-not-active)
    (asserts! (<= block-height (get end-block lottery)) err-lottery-not-active)
    (asserts! (< (get ticket-count lottery) (var-get max-tickets-per-lottery)) err-max-tickets-reached)
    (asserts! (< (get ticket-count player-data) (var-get max-tickets-per-player)) err-max-tickets-reached)
    (asserts! (validate-lottery-numbers numbers) err-invalid-numbers)
    
    ;; Transfer ticket price
    (try! (stx-transfer? (var-get ticket-price) tx-sender (as-contract tx-sender)))
    
    ;; Create ticket
    (map-set tickets {lottery-id: lottery-id, ticket-id: ticket-id}
      {
        owner: tx-sender,
        numbers: numbers,
        purchase-block: block-height,
        matches: u0,
        prize-claimed: false,
        prize-amount: u0
      }
    )
    
    ;; Update player ticket data
    (map-set player-tickets {lottery-id: lottery-id, player: tx-sender}
      {
        ticket-ids: (unwrap! (as-max-len? (append (get ticket-ids player-data) ticket-id) u50) err-max-tickets-reached),
        ticket-count: (+ (get ticket-count player-data) u1),
        total-spent: (+ (get total-spent player-data) (var-get ticket-price)),
        total-won: (get total-won player-data)
      }
    )
    
    ;; Update lottery data
    (map-set lotteries lottery-id
      (merge lottery 
        {
          ticket-count: ticket-id,
          prize-pool: (+ (get prize-pool lottery) (var-get ticket-price))
        }
      )
    )
    
    ;; Update player statistics
    (map-set player-stats tx-sender
      {
        total-tickets-bought: (+ (get total-tickets-bought player-stats-data) u1),
        total-spent: (+ (get total-spent player-stats-data) (var-get ticket-price)),
        total-won: (get total-won player-stats-data),
        lotteries-played: (if (is-eq (get ticket-count player-data) u0) 
                            (+ (get lotteries-played player-stats-data) u1) 
                            (get lotteries-played player-stats-data)),
        biggest-win: (get biggest-win player-stats-data),
        jackpots-won: (get jackpots-won player-stats-data)
      }
    )
    
    (ok ticket-id)
  )
)

;; Buy single random ticket
(define-public (buy-random-ticket (lottery-id uint))
  (let 
    (
      (random-numbers (generate-random-numbers u1))
    )
    (buy-ticket lottery-id random-numbers)
  )
)

;; Generate random lottery numbers
(define-private (generate-random-numbers (seed-modifier uint))
  (let 
    (
      (seed (+ (var-get random-seed) block-height seed-modifier))
      (num1 (+ (mod seed u49) u1))
      (num2 (+ (mod (/ seed u2) u49) u1))
      (num3 (+ (mod (/ seed u3) u49) u1))
      (num4 (+ (mod (/ seed u5) u49) u1))
      (num5 (+ (mod (/ seed u7) u49) u1))
      (num6 (+ (mod (/ seed u11) u49) u1))
    )
    (var-set random-seed (+ seed u1))
    (list num1 num2 num3 num4 num5 num6)
  )
)

;; Validate lottery numbers (1-49, no duplicates)
(define-private (validate-lottery-numbers (numbers (list 6 uint)))
  (and 
    (is-eq (len numbers) u6)
    (is-all-numbers-valid numbers)
  )
)

;; Check if all numbers are in valid range (1-49)
(define-private (is-all-numbers-valid (numbers (list 6 uint)))
  (fold check-number-valid numbers true)
)

;; Helper function to check individual number validity
(define-private (check-number-valid (num uint) (valid bool))
  (and valid (and (>= num u1) (<= num u49)))
)

;; Draw winning numbers (only owner can call after lottery ends)
(define-public (draw-lottery (lottery-id uint))
  (let 
    (
      (lottery (unwrap! (map-get? lotteries lottery-id) err-not-found))
      (winning-numbers (generate-winning-numbers lottery-id))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> block-height (get end-block lottery)) err-lottery-not-ended)
    (asserts! (is-eq (get status lottery) "active") err-lottery-not-active)
    
    ;; Update lottery with winning numbers and finalize
    (map-set lotteries lottery-id
      (merge lottery 
        {
          status: "ended",
          drawn-numbers: winning-numbers
        }
      )
    )
    
    ;; Calculate and store prize distribution
    (let 
      (
        (total-pool (get prize-pool lottery))
        (house-cut (/ total-pool u10)) ;; 10% house fee
        (prize-pool (- total-pool house-cut))
        (jackpot-prize (/ (* prize-pool u70) u100)) ;; 70% for jackpot
        (second-tier-prize (/ (* prize-pool u20) u100)) ;; 20% for 5 matches
        (third-tier-prize (/ (* prize-pool u10) u100)) ;; 10% for 4 matches
      )
      
      ;; Store lottery statistics
      (map-set lottery-stats lottery-id
        {
          jackpot-amount: jackpot-prize,
          second-tier-amount: second-tier-prize,
          third-tier-amount: third-tier-prize,
          total-distributed: prize-pool,
          house-earnings: house-cut
        }
      )
      
      ;; Update lottery with house fee
      (map-set lotteries lottery-id
        (merge lottery 
          {
            status: "ended",
            drawn-numbers: winning-numbers,
            house-fee: house-cut
          }
        )
      )
      
      ;; Transfer house fee to owner
      (try! (as-contract (stx-transfer? house-cut tx-sender contract-owner)))
      
      (ok winning-numbers)
    )
  )
)

;; Generate winning numbers for lottery
(define-private (generate-winning-numbers (lottery-id uint))
  (let 
    (
      (base-seed (+ lottery-id block-height u12345))
    )
    (generate-random-numbers base-seed)
  )
)

;; Check ticket matches (must be called after lottery is drawn)
(define-public (check-ticket-matches (lottery-id uint) (ticket-id uint))
  (let 
    (
      (lottery (unwrap! (map-get? lotteries lottery-id) err-not-found))
      (ticket (unwrap! (map-get? tickets {lottery-id: lottery-id, ticket-id: ticket-id}) err-not-found))
      (winning-numbers (get drawn-numbers lottery))
    )
    
    (asserts! (is-eq (get status lottery) "ended") err-lottery-not-ended)
    
    (let 
      (
        (matches (count-matches (get numbers ticket) winning-numbers))
      )
      ;; Update ticket with match count
      (map-set tickets {lottery-id: lottery-id, ticket-id: ticket-id}
        (merge ticket {matches: matches})
      )
      
      (ok matches)
    )
  )
)

;; Count matching numbers between ticket and winning numbers
(define-private (count-matches (ticket-numbers (list 6 uint)) (winning-numbers (list 6 uint)))
  (let 
    (
      (num1-match (if (is-some (index-of winning-numbers (unwrap! (element-at ticket-numbers u0) u0))) u1 u0))
      (num2-match (if (is-some (index-of winning-numbers (unwrap! (element-at ticket-numbers u1) u0))) u1 u0))
      (num3-match (if (is-some (index-of winning-numbers (unwrap! (element-at ticket-numbers u2) u0))) u1 u0))
      (num4-match (if (is-some (index-of winning-numbers (unwrap! (element-at ticket-numbers u3) u0))) u1 u0))
      (num5-match (if (is-some (index-of winning-numbers (unwrap! (element-at ticket-numbers u4) u0))) u1 u0))
      (num6-match (if (is-some (index-of winning-numbers (unwrap! (element-at ticket-numbers u5) u0))) u1 u0))
    )
    (+ num1-match num2-match num3-match num4-match num5-match num6-match)
  )
)

;; Claim prize for winning ticket
(define-public (claim-prize (lottery-id uint) (ticket-id uint))
  (let 
    (
      (lottery (unwrap! (map-get? lotteries lottery-id) err-not-found))
      (ticket (unwrap! (map-get? tickets {lottery-id: lottery-id, ticket-id: ticket-id}) err-not-found))
      (lottery-stats-data (unwrap! (map-get? lottery-stats lottery-id) err-not-found))
    )
    (asserts! (is-eq (get owner ticket) tx-sender) err-unauthorized)
    (asserts! (is-eq (get status lottery) "ended") err-lottery-not-ended)
    (asserts! (not (get prize-claimed ticket)) err-already-claimed)
    (asserts! (> (get matches ticket) u3) err-no-tickets) ;; Need at least 4 matches to win
    
    (let 
      (
        (prize-amount (calculate-prize-amount (get matches ticket) lottery-stats-data))
        (player-stats-data (default-to 
                             {total-tickets-bought: u0, total-spent: u0, total-won: u0, lotteries-played: u0, biggest-win: u0, jackpots-won: u0}
                             (map-get? player-stats tx-sender)))
      )
      
      ;; Update ticket as claimed
      (map-set tickets {lottery-id: lottery-id, ticket-id: ticket-id}
        (merge ticket {prize-claimed: true, prize-amount: prize-amount})
      )
      
      ;; Update player statistics
      (map-set player-stats tx-sender
        {
          total-tickets-bought: (get total-tickets-bought player-stats-data),
          total-spent: (get total-spent player-stats-data),
          total-won: (+ (get total-won player-stats-data) prize-amount),
          lotteries-played: (get lotteries-played player-stats-data),
          biggest-win: (if (> prize-amount (get biggest-win player-stats-data)) prize-amount (get biggest-win player-stats-data)),
          jackpots-won: (if (is-eq (get matches ticket) u6) (+ (get jackpots-won player-stats-data) u1) (get jackpots-won player-stats-data))
        }
      )
      
      ;; Transfer prize to winner
      (try! (as-contract (stx-transfer? prize-amount tx-sender (get owner ticket))))
      (ok prize-amount)
    )
  )
)

;; Calculate prize amount based on matches
(define-private (calculate-prize-amount (matches uint) (lottery-stats-data {jackpot-amount: uint, second-tier-amount: uint, third-tier-amount: uint, total-distributed: uint, house-earnings: uint}))
  (if (is-eq matches u6)
    (get jackpot-amount lottery-stats-data) ;; Jackpot for 6 matches
    (if (is-eq matches u5)
      (/ (get second-tier-amount lottery-stats-data) u5) ;; Split among up to 5 winners
      (if (is-eq matches u4)
        (/ (get third-tier-amount lottery-stats-data) u20) ;; Split among up to 20 winners
        u0 ;; No prize for less than 4 matches
      )
    )
  )
)

;; Emergency cancel lottery (owner only)
(define-public (cancel-lottery (lottery-id uint))
  (let 
    (
      (lottery (unwrap! (map-get? lotteries lottery-id) err-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-eq (get status lottery) "active") err-lottery-not-active)
    
    ;; Mark lottery as cancelled
    (map-set lotteries lottery-id
      (merge lottery {status: "cancelled"})
    )
    
    (ok true)
  )
)

;; Refund individual ticket (for cancelled lotteries)
(define-public (refund-ticket (lottery-id uint) (ticket-id uint))
  (let 
    (
      (lottery (unwrap! (map-get? lotteries lottery-id) err-not-found))
      (ticket (unwrap! (map-get? tickets {lottery-id: lottery-id, ticket-id: ticket-id}) err-not-found))
    )
    (asserts! (is-eq (get status lottery) "cancelled") err-lottery-not-active)
    (asserts! (is-eq (get owner ticket) tx-sender) err-unauthorized)
    
    ;; Mark ticket as refunded by setting prize-claimed to true
    (map-set tickets {lottery-id: lottery-id, ticket-id: ticket-id}
      (merge ticket {prize-claimed: true})
    )
    
    ;; Refund ticket price to owner
    (try! (as-contract (stx-transfer? (var-get ticket-price) tx-sender (get owner ticket))))
    (ok true)
  )
)

;; Get lottery information
(define-read-only (get-lottery (lottery-id uint))
  (map-get? lotteries lottery-id)
)

;; Get current active lottery
(define-read-only (get-current-lottery)
  (let 
    (
      (current-id (- (var-get current-lottery-id) u1))
    )
    (map-get? lotteries current-id)
  )
)

;; Get ticket information
(define-read-only (get-ticket (lottery-id uint) (ticket-id uint))
  (map-get? tickets {lottery-id: lottery-id, ticket-id: ticket-id})
)

;; Get player tickets for a lottery
(define-read-only (get-player-tickets (lottery-id uint) (player principal))
  (map-get? player-tickets {lottery-id: lottery-id, player: player})
)

;; Get player statistics
(define-read-only (get-player-stats (player principal))
  (map-get? player-stats player)
)

;; Get lottery statistics
(define-read-only (get-lottery-stats (lottery-id uint))
  (map-get? lottery-stats lottery-id)
)

;; Check if lottery is active
(define-read-only (is-lottery-active (lottery-id uint))
  (match (map-get? lotteries lottery-id)
    lottery (and 
              (is-eq (get status lottery) "active")
              (<= block-height (get end-block lottery)))
    false
  )
)

;; Get time remaining for lottery
(define-read-only (get-lottery-time-remaining (lottery-id uint))
  (match (map-get? lotteries lottery-id)
    lottery (if (<= block-height (get end-block lottery))
              (some (- (get end-block lottery) block-height))
              none)
    none
  )
)

;; Get total tickets sold for lottery
(define-read-only (get-lottery-ticket-count (lottery-id uint))
  (match (map-get? lotteries lottery-id)
    lottery (some (get ticket-count lottery))
    none
  )
)

;; Get lottery prize pool
(define-read-only (get-lottery-prize-pool (lottery-id uint))
  (match (map-get? lotteries lottery-id)
    lottery (some (get prize-pool lottery))
    none
  )
)

;; Check if player has tickets in lottery
(define-read-only (player-has-tickets (lottery-id uint) (player principal))
  (match (map-get? player-tickets {lottery-id: lottery-id, player: player})
    player-ticket-data (> (get ticket-count player-ticket-data) u0)
    false
  )
)

;; Get winning numbers for lottery
(define-read-only (get-winning-numbers (lottery-id uint))
  (match (map-get? lotteries lottery-id)
    lottery (if (is-eq (get status lottery) "ended")
              (some (get drawn-numbers lottery))
              none)
    none
  )
)

;; Admin functions
(define-public (set-ticket-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set ticket-price new-price)
    (ok true)
  )
)

(define-public (set-max-tickets-per-lottery (new-max uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set max-tickets-per-lottery new-max)
    (ok true)
  )
)

(define-public (set-max-tickets-per-player (new-max uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set max-tickets-per-player new-max)
    (ok true)
  )
)

(define-public (set-lottery-duration (new-duration uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set lottery-duration new-duration)
    (ok true)
  )
)

(define-public (update-random-seed (new-seed uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set random-seed new-seed)
    (ok true)
  )
)