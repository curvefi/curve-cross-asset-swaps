import brownie
import pytest


@pytest.fixture(scope="module")
def token_id(settler_sbtc):
    return int(settler_sbtc.address, 16)


@pytest.fixture(scope="module", autouse=True)
def setup(alice, bob, swap, DAI, USDT, add_synths):
    DAI._mint_for_testing(alice, 1_000_000 * 10 ** 18)
    DAI.approve(swap, 2**256-1, {'from': alice})
    USDT._mint_for_testing(bob, 1_000_000 * 10 ** 6)
    USDT.approve(swap, 2**256-1, {'from': bob})


def test_swap_into_existing_increases_balance(swap, alice, DAI, sUSD, sBTC, settler_sbtc, token_id):
    initial = sBTC.balanceOf(settler_sbtc)

    amount = 1_000_000 * 10 ** 18
    expected = swap.get_swap_into_synth_amount(DAI, sBTC, amount)
    swap.swap_into_synth(DAI, sBTC, amount, 0, alice, token_id, {'from': alice})

    assert DAI.balanceOf(alice) == 0
    assert DAI.balanceOf(swap) == 0
    assert DAI.balanceOf(settler_sbtc) == 0

    assert sUSD.balanceOf(alice) == 0
    assert sUSD.balanceOf(swap) == 0
    assert sUSD.balanceOf(settler_sbtc) == 0

    assert sBTC.balanceOf(alice) == 0
    assert sBTC.balanceOf(swap) == 0
    assert sBTC.balanceOf(settler_sbtc) == expected + initial


def test_swap_into_existing_does_not_mint(swap, alice, DAI, sBTC, token_id):
    amount = 1_000_000 * 10 ** 18
    tx = swap.swap_into_synth(DAI, sBTC, amount, 0, alice, token_id, {'from': alice})
    new_token_id = tx.return_value

    assert not tx.new_contracts
    assert new_token_id == token_id
    assert swap.balanceOf(alice) == 1


def test_only_owner(swap, alice, bob, DAI, sBTC, token_id):
    amount = 1_000_000 * 10 ** 18

    with brownie.reverts("Caller is not owner or operator"):
        swap.swap_into_synth(DAI, sBTC, amount, 0, bob, token_id, {'from': bob})


def test_wrong_receiver(swap, alice, bob, DAI, sBTC, token_id):
    amount = 1_000_000 * 10 ** 18

    with brownie.reverts("Receiver is not owner"):
        swap.swap_into_synth(DAI, sBTC, amount, 0, bob, token_id, {'from': alice})


def test_wrong_synth(swap, alice, DAI, sETH, token_id):
    amount = 1_000_000 * 10 ** 18

    with brownie.reverts("Incorrect synth for Token ID"):
        swap.swap_into_synth(DAI, sETH, amount, 0, alice, token_id, {'from': alice})


def test_cannot_add_after_burn(chain, swap, alice, token_id, DAI, sBTC):
    chain.mine(timedelta=600)
    balance = swap.token_info(token_id)['underlying_balance']

    swap.withdraw(token_id, balance, {'from': alice})

    with brownie.reverts("Unknown Token ID"):
        swap.swap_into_synth(DAI, sBTC, 10**18, 0, alice, token_id, {'from': alice})


def test_approved_operator(swap, alice, bob, USDT, sBTC, token_id):
    amount = 1_000_000 * 10 ** 6

    swap.setApprovalForAll(bob, True, {'from': alice})
    swap.swap_into_synth(USDT, sBTC, amount, 0, alice, token_id, {'from': bob})


def test_approved_one_token_operator(swap, alice, bob, USDT, sBTC, token_id):
    amount = 1_000_000 * 10 ** 6

    swap.approve(bob, token_id, {'from': alice})
    swap.swap_into_synth(USDT, sBTC, amount, 0, alice, token_id, {'from': bob})
