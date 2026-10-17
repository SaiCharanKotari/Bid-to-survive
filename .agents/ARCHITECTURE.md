# Bid to Survive - Architecture & Codebase Map

> **Purpose**: This document provides an instant semantic map of the codebase for AI agents and human developers. Read this before making changes to locate the exact authoritative module in seconds without parsing large multi-hundred-line files.

---

## 1. Directory Tree & Naming Conventions

```
src/
├── character/
│   └── Health.server.luau                      # Standard Roblox health regeneration override
│
├── client/
│   ├── ClientUIController.client.luau          # Thin network coordinator: links ReplicatedStorage.Network to UI views
│   ├── MovementDiveAndHUDClient.client.luau    # Character physics: walk, run, sprint stamina, jetpack bursts, dive
│   ├── GlobalButtonAndSVG3UI.client.luau       # Universal button hover/click micro-animations & sounds
│   ├── GorillaImpactClient.client.luau         # Gorilla boss ground-pound client effects
│   ├── RuinsImpactClient.client.luau           # Ruins door stone hand slam client camera rumble & debris
│   │
│   └── ui/                                     # Synced to ReplicatedStorage.ClientUI
│       ├── components/
│       │   ├── ControlsDockView.luau           # Left dock: Settings gear (Escape menu) & AFK toggle button
│       │   ├── PhaseBannerView.luau            # Floating top banner: Phase name, round count, live ticker
│       │   ├── ActionDockView.luau             # Center dock: Reopen "BID" and "LEADERBOARD" buttons
│       │   ├── HammerRouletteView.luau         # SVG.5 3-slot horizontal hammer spinner reel, ticks, & victory flare
│       │   └── StatusHUDView.luau              # Bottom-left HUD (HP, EP, Lifetime Cash) + Bottom-right Wallet card
│       │
│       ├── modals/
│       │   ├── BiddingModalView.luau           # Numeric input, quick bid percentages (25%, 50%, 75%, MAX), submit
│       │   ├── RankingsModalView.luau          # 4-column leaderboard (SI.NO, PLAYER NAME, BID, TIME), safe/danger
│       │   └── MatchOverModalView.luau         # End-game podium (1st, 2nd, 3rd), winner avatar, survival time
│       │
│       └── effects/
│           └── ScreenEffectsView.luau          # Full-screen red/white flash overlay and spring camera shake
│
├── server/
│   ├── RoundManager.server.luau                # Master match state machine (Intermission -> Phase 1..7 -> MatchOver)
│   ├── SpawnAndAFKManager.server.luau          # Player spawn lifecycle & AFK state management
│   ├── R6AvatarManager.server.luau             # Authentic R6 character scaling and animation loader
│   ├── JetpackManager.server.luau              # Server validation of jetpack burst physics
│   ├── GlobalLeaderboardManager.server.luau    # Top 100 all-time cash leaderboard DataStore & podium display
│   │
│   ├── round/
│   │   ├── BotManager.luau                     # Companion bot dummy creation, appearance, bidding AI, cleanup
│   │   └── ArenaManager.luau                   # Arena/lobby teleports, neon green winner shield, water rescue loop
│   │
│   ├── economy/
│   │   └── CashAndWalletManager.luau           # $20 match wallet vs persistent cash DataStore, payout formula
│   │
│   └── hazards/
│       ├── RuinsDoorHandManager.luau           # Ancient ruins giant stone hand hazard & portal sequence
│       └── GorillaSmashManager.luau            # Giant gorilla boss ground-pound hazard
│
└── shared/                                     # Synced to ReplicatedStorage
    ├── GameConfig.luau                         # Tuning parameters: durations, starting cash, health, rarities
    ├── HammerRarityRoller.luau                 # Probability tables & spinner reel strip generation
    └── GorillaMotionData.luau                  # Procedural bone transforms & motion curves
```

---

## 2. File Role Conventions

| Suffix | Role | Authority | Example |
| :--- | :--- | :--- | :--- |
| `*Controller.client.luau` | Primary client coordinator | Client | `ClientUIController.client.luau` |
| `*Controller.server.luau` / `*.server.luau` | Primary server orchestrator | Server Authoritative | `RoundManager.server.luau` |
| `*View.luau` | Pure visual UI construction & animation | Client View | `HammerRouletteView.luau` |
| `*Manager.luau` | Core game system or domain logic | Server or Shared | `BotManager.luau`, `CashAndWalletManager.luau` |
| `*Config.luau` / `*Data.luau` | Static configurations or math tables | Shared (Pure Data) | `GameConfig.luau`, `GorillaMotionData.luau` |

---

## 3. Fast Feature Lookup Guide (Where to make changes)

| I want to change... | Go to file... |
| :--- | :--- |
| **Hammer Roulette Spinner** (speed, sound, 3-slot card animation) | `src/client/ui/components/HammerRouletteView.luau` |
| **Bidding Input / Quick Percent Buttons** | `src/client/ui/modals/BiddingModalView.luau` |
| **Rankings Leaderboard** (4 columns, colors, avatar thumbs) | `src/client/ui/modals/RankingsModalView.luau` |
| **Match Over Podium** (1st, 2nd, 3rd layout, avatar headshots) | `src/client/ui/modals/MatchOverModalView.luau` |
| **AFK Button / Settings Gear** | `src/client/ui/components/ControlsDockView.luau` |
| **Top Phase Banner & Countdown Ticker** | `src/client/ui/components/PhaseBannerView.luau` |
| **Bottom-Left HUD (HP, EP, Lifetime Cash) & Wallet** | `src/client/ui/components/StatusHUDView.luau` |
| **Character Movement, Sprint Stamina, Jetpack Burst** | `src/client/MovementDiveAndHUDClient.client.luau` |
| **Bot AI, Bot Bids, or Bot Spawning** | `src/server/round/BotManager.luau` |
| **Arena Teleportation, Neon Shields, Water Rescue** | `src/server/round/ArenaManager.luau` |
| **Match Round Loop & Phase Transitions** | `src/server/RoundManager.server.luau` |
| **Economy, $20 Wallet Deductions, Survival Payouts** | `src/server/economy/CashAndWalletManager.luau` |
| **Ruins Stone Hand Slam Hazard** | `src/server/hazards/RuinsDoorHandManager.luau` |
| **Phase Timers, Health, Rarity Probabilities** | `src/shared/GameConfig.luau` |

---

## 4. Network Data Flow

### Server -> Client (`ReplicatedStorage.Network`)
- `StateChanged(phase, data)`: Notifies client of phase transitions (`Intermission`, `Phase1_Spawn`..`Phase7_Settlement`, `MatchOver`). Handled by `ClientUIController.client.luau`.
- `PromptBid(data)`: Opens `BiddingModalView` for active participants.
- `RankingsRevealed(data)`: Opens `RankingsModalView` with sorted bidders and safe cutoff.
- `HammerSmash(data)`: Triggers camera shake and ruins impact FX.
- `MatchOver(data)`: Opens `MatchOverModalView` with podium results.
- `StatsUpdated(stats)`: Syncs Money, Health, AFK, and ParticipationState to client.
- `CashPayoutEvent(earnedCash, secondsSurvived, newOverall)`: Triggers animated cash roll and floating payout toast.

### Client -> Server (`ReplicatedStorage.Network`)
- `SetAFK(isAFK: boolean)`: Toggles player AFK status (handled by `SpawnAndAFKManager.server.luau`).
- `BidSubmitted(amount: number)`: Submits player bid (validated by `RoundManager.server.luau` and `CashAndWalletManager.luau`).
- `JetpackBurstEvent(direction, origin)`: Requests verified jetpack burst impulse.

---

## 5. Player Attributes Source of Truth
- `player:GetAttribute("IsInGame")`: `true` when active on the Walkway during a round; `false` in Lobby.
- `player:GetAttribute("IsAFK")`: `true` when AFK button is toggled ON (excluded from rounds).
- `player:GetAttribute("Wallet")`: Current match wallet ($20 starting balance; decrements on accepted bid).
- `player:GetAttribute("OverallCash")`: Persistent all-time cash saved to DataStore.
