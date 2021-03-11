import brownie
import pytest
from brownie import ZERO_ADDRESS, chain


@pytest.fixture(scope="module")
def token_id(settler_sbtc):
    return int(settler_sbtc.address, 16)


def test_cannot_swap_from_immediately(alice, swap, token_id, WBTC):
    with brownie.reverts():
        swap.swap_from_synth(token_id, WBTC, 1, 0, {"from": alice})


def test_only_owner(bob, swap, token_id, WBTC):
    chain.sleep(600)
    with brownie.reverts("Caller is not owner or operator"):
        swap.swap_from_synth(token_id, WBTC, 1, 0, {"from": bob})


def test_swap_all(alice, swap, settler_sbtc, sBTC, WBTC, token_id):
    chain.mine(timedelta=600)
    balance = swap.token_info(token_id)["underlying_balance"]
    expected = swap.get_swap_from_synth_amount(sBTC, WBTC, balance)

    swap.swap_from_synth(token_id, WBTC, balance, 0, {"from": alice})

    assert abs(WBTC.balanceOf(alice) - expected) <= 1
    assert WBTC.balanceOf(settler_sbtc) == 0
    assert WBTC.balanceOf(swap) == 0


def test_swap_all_burns(alice, swap, WBTC, token_id):
    chain.mine(timedelta=600)
    balance = swap.token_info(token_id)["underlying_balance"]

    tx = swap.swap_from_synth(token_id, WBTC, balance, 0, {"from": alice})

    # swapping the entire balance should burn the related NFT
    assert swap.balanceOf(alice) == 0
    assert tx.events["Transfer"][-1].values() == [alice, ZERO_ADDRESS, token_id]
    with brownie.reverts():
        swap.ownerOf(token_id)


def test_swap_partial(alice, swap, settler_sbtc, sBTC, WBTC, token_id):
    chain.mine(timedelta=600)
    initial = swap.token_info(token_id)["underlying_balance"]
    amount = initial // 4

    expected = swap.get_swap_from_synth_amount(sBTC, WBTC, amount)
    swap.swap_from_synth(token_id, WBTC, amount, 0, {"from": alice})

    assert sBTC.balanceOf(alice) == 0
    assert sBTC.balanceOf(settler_sbtc) == initial - amount
    assert sBTC.balanceOf(swap) == 0

    assert abs(WBTC.balanceOf(alice) - expected) <= 1
    assert WBTC.balanceOf(settler_sbtc) == 0
    assert WBTC.balanceOf(swap) == 0


def test_swap_partial_does_not_burn(alice, swap, token_id, WBTC):
    chain.mine(timedelta=600)
    initial = swap.token_info(token_id)["underlying_balance"]
    amount = initial // 4

    swap.swap_from_synth(token_id, WBTC, amount, 0, {"from": alice})

    assert swap.balanceOf(alice) == 1
    assert swap.ownerOf(token_id) == alice


def test_swap_multiple(alice, swap, settler_susd, sUSD, DAI, USDT):
    chain.mine(timedelta=600)
    token_id = int(settler_susd.address, 16)
    initial = swap.token_info(token_id)["underlying_balance"]
    amount = initial // 4

    expected_1 = swap.get_swap_from_synth_amount(sUSD, DAI, amount) - 1
    swap.swap_from_synth(token_id, DAI, amount, expected_1, {"from": alice})

    expected_2 = swap.get_swap_from_synth_amount(sUSD, USDT, amount * 2) - 1
    swap.swap_from_synth(token_id, USDT, amount * 2, expected_2, {"from": alice})

    assert sUSD.balanceOf(settler_susd) == initial - amount * 3
    assert abs(DAI.balanceOf(alice) - expected_1) <= 1
    assert abs(USDT.balanceOf(alice) - expected_2) <= 1


def test_different_receiver(alice, bob, swap, settler_sbtc, sBTC, WBTC, token_id):
    chain.mine(timedelta=600)
    balance = swap.token_info(token_id)["underlying_balance"]
    expected = swap.get_swap_from_synth_amount(sBTC, WBTC, balance)

    swap.swap_from_synth(token_id, WBTC, balance, 0, bob, {"from": alice})

    assert abs(WBTC.balanceOf(bob) - expected) <= 1
    assert WBTC.balanceOf(alice) == 0
    assert WBTC.balanceOf(settler_sbtc) == 0
    assert WBTC.balanceOf(swap) == 0


def test_exceeds_balance(alice, bob, swap, token_id, sBTC, WBTC):
    chain.mine(timedelta=600)
    balance = swap.token_info(token_id)["underlying_balance"]

    with brownie.reverts():
        swap.swap_from_synth(token_id, WBTC, balance + 1, 0, {"from": alice})


def test_approved_operator(swap, alice, bob, WBTC, token_id):
    swap.setApprovalForAll(bob, True, {"from": alice})
    chain.sleep(600)
    swap.swap_from_synth(token_id, WBTC, 1, 0, {"from": bob})


def test_approved_one_token_operator(swap, alice, bob, WBTC, token_id):
    swap.approve(bob, token_id, {"from": alice})
    chain.sleep(600)
    swap.swap_from_synth(token_id, WBTC, 1, 0, {"from": bob})
