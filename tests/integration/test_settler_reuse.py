import brownie
import itertools
import pytest


@pytest.fixture(scope="module")
def token_ids(chain, alice, bob, swap, DAI, USDT, sBTC, add_synths):
    DAI._mint_for_testing(alice, 1_000_000 * 10 ** 18)
    DAI.approve(swap, 2**256-1, {'from': alice})
    USDT._mint_for_testing(bob, 1_000_000 * 10 ** 6)
    USDT.approve(swap, 2**256-1, {'from': bob})

    token_ids = []

    # mint 4 NFTs for alice
    amount = (1_000_000 * 10 ** 18) // 4
    for i in range(4):
        tx = swap.swap_into_synth(DAI, sBTC, amount, 0, {'from': alice})
        token_ids.append(tx.events['Transfer'][-1]['token_id'])

    chain.sleep(600)

    yield token_ids


@pytest.mark.parametrize("idx", itertools.permutations(range(4), 3))
def test_reuse_settler(Settler, swap, alice, bob, USDT, sBTC, sETH, token_ids, idx):
    for i in idx:
        balance = swap.token_info(token_ids[i])['underlying_balance']
        swap.withdraw(token_ids[i], balance, {'from': alice})

    for i in idx[::-1]:
        settler = Settler.at(hex(token_ids[i]))
        assert settler.synth() == sBTC
        with brownie.reverts():
            swap.ownerOf(token_ids[i])

        tx = swap.swap_into_synth(USDT, sETH, 1000 * 10 ** 6, 0, {'from': bob})
        token_id = tx.events['Transfer'][-1]['token_id']
        assert token_id == token_ids[i] + 2**160
        assert not swap.is_settled(token_id)
        assert swap.ownerOf(token_id) == bob
        assert settler.synth() == sETH

    assert swap.balanceOf(bob) == 3
    assert swap.balanceOf(alice) == 1
