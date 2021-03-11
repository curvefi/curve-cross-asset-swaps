import pytest

import brownie
from brownie import Settler, ETH_ADDRESS, ZERO_ADDRESS


@pytest.fixture(scope="module", autouse=True)
def setup(alice, swap, DAI, USDT, add_synths):
    DAI._mint_for_testing(alice, 1_000_000 * 10 ** 18)
    DAI.approve(swap, 2 ** 256 - 1, {"from": alice})
    USDT._mint_for_testing(alice, 1_000_000 * 10 ** 6)
    USDT.approve(swap, 2 ** 256 - 1, {"from": alice})


def test_swap_into_deploys_settler(swap, alice, DAI, sUSD, sBTC):
    amount = 1_000_000 * 10 ** 18
    tx = swap.swap_into_synth(DAI, sBTC, amount, 0, {"from": alice})
    token_id = tx.events["Transfer"][-1]["token_id"]

    # this will fail if no bytecode exists at `token_id`
    settler = Settler.at(hex(token_id))
    assert settler.synth() == sBTC


def test_swap_into_mints(swap, alice, DAI, sBTC):
    amount = 1_000_000 * 10 ** 18
    tx = swap.swap_into_synth(DAI, sBTC, amount, 0, {"from": alice})
    token_id = tx.events["Transfer"][-1]["token_id"]

    assert swap.balanceOf(alice) == 1
    assert tx.events["Transfer"][-1].values() == [ZERO_ADDRESS, alice, token_id]
    assert swap.ownerOf(token_id) == alice


def test_swap_into_dai(swap, alice, DAI, sUSD, sBTC):
    amount = 1_000_000 * 10 ** 18
    expected = swap.get_swap_into_synth_amount(DAI, sBTC, amount)
    tx = swap.swap_into_synth(DAI, sBTC, amount, 0, {"from": alice})
    token_id = tx.events["Transfer"][-1]["token_id"]

    settler = Settler.at(hex(token_id))
    assert DAI.balanceOf(alice) == 0
    assert DAI.balanceOf(swap) == 0
    assert DAI.balanceOf(settler) == 0

    assert sUSD.balanceOf(alice) == 0
    assert sUSD.balanceOf(swap) == 0
    assert sUSD.balanceOf(settler) == 0

    assert sBTC.balanceOf(alice) == 0
    assert sBTC.balanceOf(swap) == 0
    assert sBTC.balanceOf(settler) == expected


def test_swap_into_usdt(swap, alice, USDT, sUSD, sBTC):
    # test USDT to make sure we handle tokens that return None
    amount = 1_000_000 * 10 ** 6
    expected = swap.get_swap_into_synth_amount(USDT, sBTC, amount)
    tx = swap.swap_into_synth(USDT, sBTC, amount, 0, {"from": alice})
    token_id = tx.events["Transfer"][-1]["token_id"]

    settler = Settler.at(hex(token_id))
    assert USDT.balanceOf(alice) == 0
    assert USDT.balanceOf(swap) == 0
    assert USDT.balanceOf(settler) == 0

    assert sUSD.balanceOf(alice) == 0
    assert sUSD.balanceOf(swap) == 0
    assert sUSD.balanceOf(settler) == 0

    assert sBTC.balanceOf(alice) == 0
    assert sBTC.balanceOf(swap) == 0
    assert sBTC.balanceOf(settler) == expected


def test_swap_into_eth(swap, alice, sETH, sBTC):
    amount = 50 * 10 ** 18
    expected = swap.get_swap_into_synth_amount(ETH_ADDRESS, sBTC, amount)
    tx = swap.swap_into_synth(
        ETH_ADDRESS, sBTC, amount, 0, {"from": alice, "value": amount}
    )
    token_id = tx.events["Transfer"][-1]["token_id"]

    settler = Settler.at(hex(token_id))

    assert sETH.balanceOf(alice) == 0
    assert sETH.balanceOf(swap) == 0
    assert sETH.balanceOf(settler) == 0

    assert sBTC.balanceOf(alice) == 0
    assert sBTC.balanceOf(swap) == 0
    assert sBTC.balanceOf(settler) == expected


def test_different_receiver(swap, alice, bob, DAI, sBTC):
    amount = 1_000_000 * 10 ** 18
    tx = swap.swap_into_synth(DAI, sBTC, amount, 0, bob, {"from": alice})
    token_id = tx.events["Transfer"][-1]["token_id"]

    assert swap.balanceOf(alice) == 0
    assert swap.balanceOf(bob) == 1
    assert tx.events["Transfer"][-1].values() == [ZERO_ADDRESS, bob, token_id]
    assert swap.ownerOf(token_id) == bob


@pytest.mark.parametrize("amount", [0, (50 * 10 ** 18) + 1, (50 * 10 ** 18) - 1])
def test_incorrect_eth_amount(swap, alice, sETH, sBTC, amount):
    with brownie.reverts():
        swap.swap_into_synth(
            ETH_ADDRESS, sBTC, 50 * 10 ** 18, 0, {"from": alice, "value": amount}
        )


def test_slippage(swap, alice, DAI, sBTC):
    amount = 1_000_000 * 10 ** 18
    expected = swap.get_swap_into_synth_amount(DAI, sBTC, amount)
    with brownie.reverts("Rekt by slippage"):
        swap.swap_into_synth(DAI, sBTC, amount, expected + 1, {"from": alice})


def test_swap_into_multiple_different_synths(swap, alice, DAI, USDT, sETH, sBTC):
    amount = 1_000_000 * 10 ** 18
    tx = swap.swap_into_synth(DAI, sBTC, amount, 0, {"from": alice})
    token_id1 = tx.events["Transfer"][-1]["token_id"]

    amount = 1_000_000 * 10 ** 6
    tx = swap.swap_into_synth(USDT, sETH, amount, 0, {"from": alice})
    token_id2 = tx.events["Transfer"][-1]["token_id"]

    assert token_id1 != token_id2
    assert swap.balanceOf(alice) == 2
    assert swap.ownerOf(token_id1) == alice
    assert swap.ownerOf(token_id2) == alice
    assert Settler.at(hex(token_id1)).synth() == sBTC
    assert Settler.at(hex(token_id2)).synth() == sETH


def test_swap_into_multiple_same_synth(swap, alice, DAI, sBTC):
    amount = (1_000_000 * 10 ** 18) // 4
    tx = swap.swap_into_synth(DAI, sBTC, amount, 0, {"from": alice})
    token_id1 = tx.events["Transfer"][-1]["token_id"]

    tx = swap.swap_into_synth(DAI, sBTC, amount, 0, {"from": alice})
    token_id2 = tx.events["Transfer"][-1]["token_id"]

    assert token_id1 != token_id2
    assert swap.balanceOf(alice) == 2
    assert swap.ownerOf(token_id1) == alice
    assert swap.ownerOf(token_id2) == alice
    assert Settler.at(hex(token_id1)).synth() == sBTC
    assert Settler.at(hex(token_id2)).synth() == sBTC


def test_unknown_synth(swap, alice, DAI):
    # i sure hope we never have a pool for this
    sTRX = "0x47bD14817d7684082E04934878EE2Dd3576Ae19d"

    with brownie.reverts():
        swap.swap_into_synth(DAI, sTRX, 10 ** 18, 0, {"from": alice})
