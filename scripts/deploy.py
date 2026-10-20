import json, os
from web3 import Web3
from eth_account import Account

w3 = Web3(Web3.HTTPProvider(os.getenv("RPC_URL", "http://127.0.0.1:8545")))
art = json.load(open("artifacts/contracts/Pharmatrace.sol/PharmaTrace.json"))
acct = Account.from_key(os.environ["ADMIN_KEY"])

C = w3.eth.contract(abi=art["abi"], bytecode=art["bytecode"])
tx = C.constructor().build_transaction({
    "from": acct.address,
    "nonce": w3.eth.get_transaction_count(acct.address),
    "gas": 6_000_000,
    "gasPrice": w3.eth.gas_price,
})
s = acct.sign_transaction(tx)
raw = getattr(s, "raw_transaction", None) or s.rawTransaction
r = w3.eth.wait_for_transaction_receipt(w3.eth.send_raw_transaction(raw))
print("CONTRACT_ADDRESS=" + r.contractAddress)