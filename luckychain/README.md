# 🎲 Play-to-Earn Lottery Contract

A decentralized lottery system designed for **Play-to-Earn mechanics** on the Stacks blockchain.  
Players can buy tickets, choose their own numbers or generate random ones, and compete for multiple prize tiers. Winnings are distributed automatically and transparently on-chain.

---

## ✨ Features

- **Lottery lifecycle**
  - Start new lotteries (owner only)
  - Automatic lottery expiration (based on block height)
  - Random number drawing after lottery ends
- **Tickets**
  - Players can buy tickets with chosen numbers (6 numbers from 1–49)
  - Option to buy multiple random tickets at once
  - Enforces max tickets per lottery and per player
- **Prizes**
  - Jackpot (6/6 matches) → 70% of prize pool
  - Second tier (5/6 matches) → 20% of prize pool
  - Third tier (4/6 matches) → 10% of prize pool
  - Automatic house fee (10%) sent to contract owner
- **Player statistics**
  - Track total tickets bought, spent, winnings, biggest win, jackpots won
- **Lottery statistics**
  - Track prize amounts, house earnings, total distributed
- **Fairness**
  - Uses a pseudo-random seed for number generation (block height + internal seed)

---

## 📂 Contract Structure

### Constants
- Errors (e.g., `err-owner-only`, `err-lottery-not-active`)
- Configurable values:  
  - `ticket-price` (default: 0.1 STX)  
  - `max-tickets-per-lottery` (1000)  
  - `max-tickets-per-player` (50)  
  - `lottery-duration` (~24 hours in blocks)

### Data Maps
- `lotteries` → Stores each lottery’s state
- `tickets` → Individual tickets with numbers, owner, and prize status
- `player-tickets` → Ticket ownership tracking per player
- `player-stats` → Lifetime player statistics
- `lottery-stats` → Prize distributions & house fee per lottery

### Key Public Functions
- `start-new-lottery` → Start a fresh lottery (owner only)
- `buy-ticket` → Buy a ticket with chosen numbers
- `buy-random-tickets` → Buy multiple tickets with random numbers
- `draw-lottery` → End lottery & generate winning numbers (owner only)
- `claim-prize` → Claim winnings for a winning ticket

