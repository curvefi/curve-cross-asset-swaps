# curve-cross-asset-swaps

Cross asset swaps using [Curve](https://www.curve.fi/) and [Synthetix](https://www.synthetix.io/).

## Overview

[`SynthSwap`](contracts/SynthSwap.vy) combines Curve and Synthetix to allow large scale swaps between different asset classes with minimal slippage. Utilizing Synthetix' zero-slippage synth conversions and Curve's deep liquidity and low fees, we can perform fully on-chain cross asset swaps at scale with a 0.38% fee and minimal slippage.

### How it Works

As an example, suppose we have asset `A` and wish to exchange it for asset `D`. For this swap to be possible, `A` and `D` must meet the following requirements:

* Must be of different asset classes (e.g. USD, EUR, BTC, ETH)
* Must be exchangeable for a Synthetic asset within one of Curve's pools (e.g. sUSD, sBTC)

The swap can be visualized as `A -> B -> C | C -> D`:

* The initial asset `A` is exchanged on Curve for `B`, a synth of the same asset class.
* `B` is converted to `C`, a synth of the same asset class as `D`.
* A [settlement period](https://docs.synthetix.io/integrations/settlement/) passes to account for sudden price movements between `B` and `C`.
* Once the settlement period has passed, `C` is exchanged on Curve for the desired asset `D`.

These swaps cannot occur atomically due to the settlement period. [`SynthSwap`](contracts/SynthSwap.vy) mints an [ERC721](https://eips.ethereum.org/EIPS/eip-721) non-fungible token to represent the claim on each unsettled swap.

* The token, and associated right to claim, are fully transferable
* Upon completion of the swap the NFT is burned
* Each NFT has a unique token ID that is never re-used
* Token IDs are not sequential

### Considerations

The benefits from these swaps are most apparent when the exchange amount is greater than $1m USD equivalent. As such, the initiation of a swap gives a strong indicator other market participants that a 2nd post-settlement swap will be coming. We attempt to minimize the risks from this in several ways:

* `D` is not declared on-chain when performing the swap from `A -> C`.
* It is possible to perform a partial swap from `C -> D`, and to swap into multiple final assets. The NFT persists until it has no remaining underlying balance of `C`.
* There is no fixed time frame for the second swap. A user can perform it immediately or wait until market conditions are more favorable.
* It is possible to withdraw `C` without performing a second swap.
* It is possible to perform additional `A -> B -> C` swaps to increase the balance of an already existing NFT.

The range of available actions and time frames make it significantly more difficult to predict the outcome of a swap and trade against it.

## Technical Implementation

### Settlers

Unsettled synthetic assets cannot be transferred because the settled balance is not yet known. If any portion of a synth balance at an address is unsettled, the entire balance is frozen. Thus, to allow multiple swaps at the same time there is a requirement to hold each synth balance in a unique address. We achieve this using Vyper's [`create_forwarder_to`](https://vyper.readthedocs.io/en/stable/built-in-functions.html#create_forwarder_to) to deploy proxy contracts which handle the synth swap. These contracts are referred to as "settlers".

The [`Settler`](contracts/Settler.vy) implementation contract is deployed prior to [`SynthSwap`](contracts/SynthSwap.vy). Several settler proxies are deployed during the constructor of [`SynthSwap`](contracts/SynthSwap.vy). Settlers are re-used for subsequent swaps to reduce gas costs. A new settler is only deployed when all existing settlers are currently in use.

Each NFT token ID is a uint256 representation of `[16 byte nonce][20 byte settler address]`. The nonce starts at zero and is incremented each time a settler is re-used in order to ensure a unique token ID for each swap.

## Usage

### Dependencies

* [python3](https://www.python.org/downloads/release/python-368/) version 3.6 or greater, python3-dev
* [brownie](https://github.com/eth-brownie/brownie) - tested with version [1.12.4](https://github.com/eth-brownie/brownie/releases/tag/v1.12.4)
* [brownie-token-tester](https://github.com/iamdefinitelyahuman/brownie-token-tester)
* [ganache-cli](https://github.com/trufflesuite/ganache-cli) - tested with version [6.12.1](https://github.com/trufflesuite/ganache-cli/releases/tag/v6.12.1)

### Testing

Testing is performed in a forked mainnet environment. The test suite is broadly split between [unit](tests/unitary) and [integration](tests/integration) tests.

To run the unit tests:

```bash
brownie test tests/unitary
```

To run the integration tests (this might take a while):

```bash
brownie test tests/integration
```

### Deployment

To deploy the contracts, first modify the [`deployment script`](scripts/deploy.py) to unlock the account you wish to deploy from. Then:

```bash
brownie run deploy --network mainnet
```

## License

This repository is licensed under the [MIT license](LICENSE).
