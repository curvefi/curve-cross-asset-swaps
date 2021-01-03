import pytest
from brownie import chain
from brownie_tokens import MintableForkToken

pytestmark = pytest.mark.usefixtures("add_synths")


@pytest.mark.parametrize('usd_idx', range(3))
@pytest.mark.parametrize('btc_idx', range(2))
def test_usd_to_btc(Settler, alice, swap, sUSD, sBTC, curve_susd, curve_sbtc, usd_idx, btc_idx):
    initial = MintableForkToken(curve_susd.coins(usd_idx))
    final = MintableForkToken(curve_sbtc.coins(btc_idx))

    amount = 1_000_000 * 10 ** initial.decimals()
    initial._mint_for_testing(alice, amount)
    initial.approve(swap, 2**256-1, {'from': alice})

    tx = swap.swap_into_synth(initial, sBTC, amount, 0, {'from': alice})
    token_id = tx.events['Transfer'][-1]['token_id']

    chain.mine(timedelta=200)
    amount = swap.token_info(token_id)['underlying_balance']
    swap.swap_from_synth(token_id, final, amount, 0, {'from': alice})

    settler = Settler.at(hex(token_id))
    for coin in (initial, sBTC, sUSD):
        assert coin.balanceOf(swap) == 0
        assert coin.balanceOf(settler) == 0
        assert coin.balanceOf(alice) == 0

    assert final.balanceOf(swap) == 0
    assert final.balanceOf(settler) == 0
    assert final.balanceOf(alice) > 0

    assert swap.balanceOf(alice) == 0


@pytest.mark.parametrize('usd_idx', range(3))
@pytest.mark.parametrize('btc_idx', range(2))
def test_btc_to_usd(Settler, alice, swap, sUSD, sBTC, curve_susd, curve_sbtc, usd_idx, btc_idx):
    initial = MintableForkToken(curve_sbtc.coins(btc_idx))
    final = MintableForkToken(curve_susd.coins(usd_idx))

    amount = 50 * 10 ** initial.decimals()
    initial._mint_for_testing(alice, amount)
    initial.approve(swap, 2**256-1, {'from': alice})

    tx = swap.swap_into_synth(initial, sUSD, amount, 0, {'from': alice})
    token_id = tx.events['Transfer'][-1]['token_id']

    chain.mine(timedelta=200)
    amount = swap.token_info(token_id)['underlying_balance']
    swap.swap_from_synth(token_id, final, amount, 0, {'from': alice})

    settler = Settler.at(hex(token_id))
    for coin in (initial, sBTC, sUSD):
        assert coin.balanceOf(swap) == 0
        assert coin.balanceOf(settler) == 0
        assert coin.balanceOf(alice) == 0

    assert final.balanceOf(swap) == 0
    assert final.balanceOf(settler) == 0
    assert final.balanceOf(alice) > 0

    assert swap.balanceOf(alice) == 0
