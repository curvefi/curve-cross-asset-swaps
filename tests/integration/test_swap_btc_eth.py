import pytest
from brownie import ETH_ADDRESS, chain
from brownie_tokens import MintableForkToken

pytestmark = pytest.mark.usefixtures("add_synths")


@pytest.mark.parametrize('btc_idx', range(2))
def test_btc_to_eth(Settler, alice, bob, swap, sBTC, sETH, curve_sbtc, curve_seth, btc_idx):
    initial = MintableForkToken(curve_sbtc.coins(btc_idx))

    amount = 5 * 10 ** initial.decimals()
    initial._mint_for_testing(alice, amount)
    initial.approve(swap, 2**256-1, {'from': alice})
    alice.transfer(bob, alice.balance())

    tx = swap.swap_into_synth(initial, sETH, amount, 0, {'from': alice})
    token_id = tx.events['Transfer'][-1]['tokenId']

    chain.mine(timedelta=200)
    amount = swap.token_info(token_id)['underlying_balance']
    swap.swap_from_synth(token_id, ETH_ADDRESS, amount, 0, {'from': alice})

    settler = Settler.at(hex(token_id))
    for coin in (initial, sETH, sBTC):
        assert coin.balanceOf(swap) == 0
        assert coin.balanceOf(settler) == 0
        assert coin.balanceOf(alice) == 0

    assert swap.balance() == 0
    assert settler.balance() == 0
    assert alice.balance() > 0

    assert swap.balanceOf(alice) == 0


@pytest.mark.parametrize('btc_idx', range(2))
def test_eth_to_btc(Settler, alice, swap, sBTC, sETH, curve_sbtc, curve_seth, btc_idx):
    final = MintableForkToken(curve_sbtc.coins(btc_idx))

    tx = swap.swap_into_synth(ETH_ADDRESS, sBTC, alice.balance(), 0, {'from': alice, 'value': alice.balance()})
    token_id = tx.events['Transfer'][-1]['tokenId']

    chain.mine(timedelta=200)
    amount = swap.token_info(token_id)['underlying_balance']
    swap.swap_from_synth(token_id, final, amount, 0, {'from': alice})

    settler = Settler.at(hex(token_id))
    for coin in (sETH, sBTC):
        assert coin.balanceOf(swap) == 0
        assert coin.balanceOf(settler) == 0
        assert coin.balanceOf(alice) == 0

    assert swap.balance() == 0
    assert settler.balance() == 0
    assert alice.balance() == 0

    assert final.balanceOf(swap) == 0
    assert final.balanceOf(settler) == 0
    assert final.balanceOf(alice) > 0

    assert swap.balanceOf(alice) == 0
