import brownie
from brownie import Contract, Settler, ZERO_ADDRESS, accounts, chain
from brownie.test import strategy

from brownie_tokens import MintableForkToken

WEEK = 86400 * 7
YEAR = 86400 * 365


TOKENS = [
    (
        "0x57ab1ec28d129707052df4df418d58a2d46d5f51",  # sUSD
        "0xdac17f958d2ee523a2206206994597c13d831ec7",  # DAI
        "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",  # USDC
        "0x6b175474e89094c44da98b954eedeac495271d0f",  # USDT
    ),
    (
        "0xfe18be6b3bd88a2d2a7f928d00292e7a9963cfc6",  # sBTC
        "0xeb4c2781e4eba804ce9a9803c67d0893436bb27d",  # renBTC
        "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599",  # wBTC
    ),
    (
        "0xD71eCFF9342A5Ced620049e616c5035F1dB98620",  # sEUR
        "0xdB25f211AB05b1c97D595516F45794528a807ad8",  # EURS
    ),
]

CURRENCY_KEYS = [
    "0x7342544300000000000000000000000000000000000000000000000000000000",  # sBTC
    "0x7345555200000000000000000000000000000000000000000000000000000000",  # sEUR
]


class StateMachine:

    st_acct = strategy('address', length=5)
    st_token = strategy('uint', max_value=2)
    st_synth = strategy('uint', max_value=2)
    st_idx = strategy('decimal', min_value=0, max_value="0.99", places=2)
    st_amount = strategy('decimal', min_value=1, max_value=10, places=3)

    def __init__(cls, swap):
        cls.swap = swap

    def setup(self):
        self.settlers = {
            ZERO_ADDRESS: [int(i['addr'], 16) for i in self.swap.tx.events['NewSettler']]
        }
        chain.mine(timestamp=1600000000)

    def _mint(self, acct, token, amount):
        token = MintableForkToken(token)
        amount = int(amount * 10**token.decimals())
        if not token.allowance(acct, self.swap):
            token.approve(self.swap, 2**256-1, {'from': acct})
        balance = token.balanceOf(acct)
        if balance < amount:
            token._mint_for_testing(acct, amount - balance)

        return amount

    def rule_swap_into(self, st_acct, st_token, st_synth, st_idx, st_amount):
        """
        Generate a new NFT via a cross-asset swap.
        """
        idx = int(st_idx * len(TOKENS[st_token]))

        initial = TOKENS[st_token][idx]
        synth = TOKENS[st_synth][0]
        amount = self._mint(st_acct, initial, st_amount)
        if st_token == st_synth:
            # initial token and target synth come from the same asset class
            # no cross-asset swap is possible
            with brownie.reverts():
                self.swap.swap_into_synth(initial, synth, amount, 0, {'from': st_acct})
        else:
            tx = self.swap.swap_into_synth(initial, synth, amount, 0, {'from': st_acct})
            token_id = tx.events['Transfer'][-1]['token_id']

            if "NewSettler" not in tx.events:
                # if `NewSettler` did not fire, an already deployed settler is being re-used
                # this will raise if `token_id` is missing from list of unused settlers
                self.settlers[ZERO_ADDRESS].remove(token_id)

            # make sure `token_id` isn't previously assigned
            assert token_id not in list(self.settlers.values())

            self.settlers.setdefault(st_acct, []).append(token_id)
            chain.sleep(600)

    def rule_swap_into_existing(self, st_acct, st_token, st_amount, st_idx):
        """
        Increase the underyling balance of an existing NFT via a cross-asset swap.
        """
        if self.settlers.get(st_acct):
            idx = int(st_idx * len(self.settlers[st_acct]))
            token_id = self.settlers[st_acct][idx]
        else:
            token_ids = [x for v in self.settlers.values() for x in v]
            idx = int(st_idx * len(token_ids))
            token_id = token_ids[idx]

        synth = Settler.at(hex(token_id)).synth()
        idx = int(st_idx * len(TOKENS[st_token]))
        initial = TOKENS[st_token][idx]
        amount = self._mint(st_acct, initial, st_amount)

        if self.settlers.get(st_acct) and TOKENS[st_token][0] != synth:
            self.swap.swap_into_synth(initial, synth, amount, 0, st_acct, token_id, {'from': st_acct})
            chain.sleep(600)
        else:
            with brownie.reverts():
                self.swap.swap_into_synth(initial, synth, amount, 0, st_acct, token_id, {'from': st_acct})

    def rule_withdraw(self, st_acct, st_amount, st_idx):
        """
        Withdraw a synth from an NFT.
        """
        if self.settlers.get(st_acct):
            # choose from the caller's valid NFT token IDs, if there are any
            idx = int(st_idx * len(self.settlers[st_acct]))
            token_id = self.settlers[st_acct][idx]
        else:
            # if the caller does not own any NFTs, choose from any token ID
            token_ids = [x for v in self.settlers.values() for x in v]
            idx = int(st_idx * len(token_ids))
            token_id = token_ids[idx]

        amount = int(st_amount * 10 ** 18)
        if token_id not in self.settlers[ZERO_ADDRESS]:
            # when the action is possible, don't exceed the max underlying balance
            balance = self.swap.token_info(token_id)['underlying_balance']
            amount = min(amount, balance)

        if self.settlers.get(st_acct):
            self.swap.withdraw(token_id, amount, {'from': st_acct})
            if balance == amount:
                self.settlers[st_acct].remove(token_id)
                self.settlers[ZERO_ADDRESS].append(token_id)
        else:
            with brownie.reverts():
                self.swap.withdraw(token_id, amount, {'from': st_acct})

    def rule_swap_from(self, st_acct, st_token, st_amount, st_idx):
        """
        Swap a synth out of an NFT.
        """
        if self.settlers.get(st_acct):
            # choose from the caller's valid NFT token IDs, if there are any
            idx = int(st_idx * len(self.settlers[st_acct]))
            token_id = self.settlers[st_acct][idx]
        else:
            # if the caller does not own any NFTs, choose from any token ID
            token_ids = [x for v in self.settlers.values() for x in v]
            idx = int(st_idx * len(token_ids))
            token_id = token_ids[idx]

        # choose a target coin for the swap
        synth = Settler.at(hex(token_id)).synth()
        if synth == ZERO_ADDRESS:
            # if the token ID is not active, choose from any possible token - all should fail
            token_list = [x for v in TOKENS for x in v]
        else:
            # if the token ID is active, choose from the list of possible targets
            token_list = next(i for i in TOKENS if i[0] == synth)
        idx = int(st_idx * len(token_list))
        target = token_list[idx]

        amount = int(st_amount * 10 ** 18)
        if token_id not in self.settlers[ZERO_ADDRESS]:
            # when the action is possible, don't exceed the max underlying balance
            balance = self.swap.token_info(token_id)['underlying_balance']
            amount = min(amount, balance)

        if self.settlers.get(st_acct) and synth != target:
            # sender own the NFT, target is not the same as the underlying synth
            self.swap.swap_from_synth(token_id, target, amount, 0, {'from': st_acct})
            if balance == amount:
                self.settlers[st_acct].remove(token_id)
                self.settlers[ZERO_ADDRESS].append(token_id)
        else:
            with brownie.reverts():
                self.swap.swap_from_synth(token_id, target, amount, 0, {'from': st_acct})

    def teardown(self):
        """
        Withdraw the full underlying balance from all active NFTs and
        verify that there are no remaining balances or ownerships.
        """
        for acct, token_id in [(k, x) for k, v in self.settlers.items() for x in v]:
            settler = Settler.at(hex(token_id))
            if settler.synth() != ZERO_ADDRESS:
                synth = Contract(settler.synth())
                balance = synth.balanceOf(settler)
                if balance > 0:
                    self.swap.withdraw(token_id, balance, {'from': acct})
                assert synth.balanceOf(settler) == 0

            with brownie.reverts():
                self.swap.ownerOf(token_id)

        for acct in accounts[:5]:
            assert self.swap.balanceOf(acct) == 0


def test_stateful(state_machine, swap, add_synths):
    state_machine(
        StateMachine,
        swap,
        settings={'stateful_step_count': 30}
    )
