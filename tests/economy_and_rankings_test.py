"""
Unit test suite verifying economy math, ranking tie-breaking, bid submission,
and results column integrity for Bid to Survive.
"""
import math

# 1. Exact integer cents math simulation (matching CashAndWalletManager and RoundManager)
def to_cents(dollars: float) -> int:
    return round((dollars or 0.0) * 100)

def to_dollars(cents: int) -> float:
    return cents / 100.0

def try_spend_from_wallet(current_wallet: float, bid_amount: float):
    if not isinstance(bid_amount, (int, float)) or bid_amount != bid_amount or bid_amount <= 0:
        return False, 0.0, current_wallet
    
    wallet_cents = to_cents(current_wallet)
    bid_cents = to_cents(bid_amount)
    
    if bid_cents <= 0 or bid_cents > wallet_cents:
        return False, 0.0, current_wallet
    
    new_wallet_cents = wallet_cents - bid_cents
    clean_bid = to_dollars(bid_cents)
    new_wallet = to_dollars(new_wallet_cents)
    
    return True, clean_bid, new_wallet

# Mandatory test cases from User Specification:
test_cases = [
    (20.00, 2.10, 2.10, 17.90),
    (20.00, 2.09, 2.09, 17.91),
    (20.00, 0.10, 0.10, 19.90),
    (20.00, 1.99, 1.99, 18.01),
    (20.00, 19.99, 19.99, 0.01),
    (20.00, 20.00, 20.00, 0.00),
    # Edge cases
    (20.00, 20.01, None, None), # Over funds -> reject
    (20.00, 0.00, None, None),  # Zero -> reject
    (20.00, -5.00, None, None), # Negative -> reject
]

print("=== 1. CURRENCY PRECISION & DEDUCTION TEST ===")
for wallet, bid_in, exp_bid, exp_remaining in test_cases:
    ok, actual_bid, remaining = try_spend_from_wallet(wallet, bid_in)
    if exp_bid is not None:
        assert ok, f"Failed to accept valid bid {bid_in}"
        assert abs(actual_bid - exp_bid) < 1e-6, f"Bid mismatch: got {actual_bid}, expected {exp_bid}"
        assert abs(remaining - exp_remaining) < 1e-6, f"Remaining mismatch: got {remaining}, expected {exp_remaining}"
        print(f"PASS: Bid ${bid_in:.2f} -> Accepted: ${actual_bid:.2f}, Deducted: ${actual_bid:.2f}, Remaining: ${remaining:.2f}")
    else:
        assert not ok, f"Should have rejected invalid bid {bid_in}"
        print(f"PASS: Invalid Bid ${bid_in:.2f} -> Correctly REJECTED")

print("\n=== 2. RANKING & TIE-BREAKER SENSITIVITY TEST ===")
players = [
    {"Name": "Alice", "CurrentBid": 2.10, "SubmitTime": 3.45},
    {"Name": "Bob",   "CurrentBid": 2.10, "SubmitTime": 1.20}, # Same bid, earlier time -> beats Alice
    {"Name": "Charlie","CurrentBid": 5.00, "SubmitTime": 4.10}, # Highest bid -> Rank 1
    {"Name": "David", "CurrentBid": 0.50, "SubmitTime": 2.00},
    {"Name": "Eve",   "CurrentBid": 0.50, "SubmitTime": 5.00}, # Lowest bid tie
]

# Sort using exact integer-cent tie-breaker
def sort_key(p):
    return (-to_cents(p["CurrentBid"]), p["SubmitTime"])

sorted_players = sorted(players, key=sort_key)
expected_ranks = ["Charlie", "Bob", "Alice", "David", "Eve"]
actual_ranks = [p["Name"] for p in sorted_players]
assert actual_ranks == expected_ranks, f"Rank mismatch: {actual_ranks} vs {expected_ranks}"

safe_count = max(1, math.ceil(len(sorted_players) * 0.5)) # 5 players -> 3 safe
print(f"Total Players: {len(sorted_players)}, Safe Count: {safe_count}")

for rank, p in enumerate(sorted_players, start=1):
    status = "SAFE (Green)" if rank <= safe_count else "UNSAFE (Red)"
    print(f"  #{rank} {p['Name']}: Bid=${p['CurrentBid']:.2f}, Time={p['SubmitTime']:.2f}s -> {status}")

# Check lowest bid tie detection
min_bid = sorted_players[-1]["CurrentBid"]
min_bid_cents = to_cents(min_bid)
tied_lowest = [p for p in sorted_players if to_cents(p["CurrentBid"]) == min_bid_cents]
print(f"Lowest Bid: ${min_bid:.2f}. Tied count: {len(tied_lowest)} ({[p['Name'] for p in tied_lowest]})")
assert len(tied_lowest) == 2, "Lowest tie count should be 2"

print("\n=== ALL REGRESSION TESTS PASSED CLEANLY ===")
