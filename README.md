# ICP_eth_payments
Prototype for allowing canisters to receive eth payments in ethereum network

Utilizes ICP Https outcalls and Etherscan.io

Current version only includes a single source, which leaves it vulnerable for ethereum transaction data.

Encode and decode functions allow for easy implementation of extra sources. 
*I tried for Ethplorer API, but HTTPS outcalls dont work with the IPv4.

To set up, set "receiver address" and functionality for (different) payment amounts.
The cost is ~$0.01 per tx confirmation.

The backend canister is hosted at:
https://a4gq6-oaaaa-aaaab-qaa4q-cai.raw.ic0.app/?id=jo4ub-7iaaa-aaaal-qbucq-cai

You need to use Internet Identity to reserve your "eth tx decimal id" and confirm the transactions in ICP.

getSendInfo(amountOfEthInThousandths) returns receivers address and "0.0xx000...00_decimalId", which can be copied to Metamask

confirmTx(amountOfEthInThousandths, txHash) returns #ok([Bool]) or #err("issue") depending on the result.
