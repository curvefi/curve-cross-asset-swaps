import brownie
from brownie import ZERO_ADDRESS


def test_cannot_swap_from_immediately(alice, swap, settler_sbtc, WBTC):
    with brownie.reverts():
        swap.swap_from_synth(settler_sbtc.token_id(), WBTC, 1, 0, {'from': alice})


def test_only_owner(chain, bob, swap, settler_sbtc, WBTC):
    chain.sleep(300)
    with brownie.reverts("Caller is not owner or operator"):
        swap.swap_from_synth(settler_sbtc.token_id(), WBTC, 1, 0, {'from': bob})


def test_swap_all(chain, alice, swap, settler_sbtc, sBTC, WBTC):
    chain.mine(timedelta=300)
    token_id = settler_sbtc.token_id()
    balance = swap.token_info(token_id)['underlying_balance']
    expected = swap.get_swap_from_synth_amount(sBTC, WBTC, balance)

    swap.swap_from_synth(settler_sbtc.token_id(), WBTC, balance, 0, {'from': alice})

    assert abs(WBTC.balanceOf(alice)-expected) <= 1
    assert WBTC.balanceOf(settler_sbtc) == 0
    assert WBTC.balanceOf(swap) == 0


def test_swap_all_burns(chain, alice, swap, settler_sbtc, WBTC):
    chain.mine(timedelta=300)
    token_id = settler_sbtc.token_id()
    balance = swap.token_info(token_id)['underlying_balance']

    tx = swap.swap_from_synth(settler_sbtc.token_id(), WBTC, balance, 0, {'from': alice})

    # swapping the entire balance should burn the related NFT
    assert swap.balanceOf(alice) == 0
    assert tx.events['Transfer'][-1].values() == [alice, ZERO_ADDRESS, token_id]
    with brownie.reverts():
        swap.ownerOf(token_id)


def test_swap_partial(chain, alice, swap, settler_sbtc, sBTC, WBTC):
    chain.mine(timedelta=300)
    token_id = settler_sbtc.token_id()
    initial = swap.token_info(token_id)['underlying_balance']
    amount = initial // 4

    expected = swap.get_swap_from_synth_amount(sBTC, WBTC, amount)
    swap.swap_from_synth(settler_sbtc.token_id(), WBTC, amount, 0, {'from': alice})

    assert sBTC.balanceOf(alice) == 0
    assert sBTC.balanceOf(settler_sbtc) == initial - amount
    assert sBTC.balanceOf(swap) == 0

    assert abs(WBTC.balanceOf(alice)-expected) <= 1
    assert WBTC.balanceOf(settler_sbtc) == 0
    assert WBTC.balanceOf(swap) == 0


def test_swap_partial_does_not_burn(chain, alice, swap, settler_sbtc, WBTC):
    chain.mine(timedelta=300)
    token_id = settler_sbtc.token_id()
    initial = swap.token_info(token_id)['underlying_balance']
    amount = initial // 4

    swap.swap_from_synth(token_id, WBTC, amount, 0, {'from': alice})

    assert swap.balanceOf(alice) == 1
    assert swap.ownerOf(token_id) == alice


def test_swap_multiple(chain, alice, swap, settler_susd, sUSD, DAI, USDT):
    chain.mine(timedelta=300)
    token_id = settler_susd.token_id()
    initial = swap.token_info(token_id)['underlying_balance']
    amount = initial // 4

    expected_1 = swap.get_swap_from_synth_amount(sUSD, DAI, amount)-1
    swap.swap_from_synth(token_id, DAI, amount, expected_1, {'from': alice})

    expected_2 = swap.get_swap_from_synth_amount(sUSD, USDT, amount * 2)-1
    swap.swap_from_synth(token_id, USDT, amount * 2, expected_2, {'from': alice})

    assert sUSD.balanceOf(settler_susd) == initial - amount * 3
    assert abs(DAI.balanceOf(alice) - expected_1) <= 1
    assert abs(USDT.balanceOf(alice) - expected_2) <= 1


def test_different_receiver(chain, alice, bob, swap, settler_sbtc, sBTC, WBTC):
    chain.mine(timedelta=300)
    token_id = settler_sbtc.token_id()
    balance = swap.token_info(token_id)['underlying_balance']
    expected = swap.get_swap_from_synth_amount(sBTC, WBTC, balance)

    swap.swap_from_synth(settler_sbtc.token_id(), WBTC, balance, 0, bob, {'from': alice})

    assert abs(WBTC.balanceOf(bob)-expected) <= 1
    assert WBTC.balanceOf(alice) == 0
    assert WBTC.balanceOf(settler_sbtc) == 0
    assert WBTC.balanceOf(swap) == 0


def test_exceeds_balance(chain, alice, bob, swap, settler_sbtc, sBTC, WBTC):
    chain.mine(timedelta=300)
    token_id = settler_sbtc.token_id()
    balance = swap.token_info(token_id)['underlying_balance']

    with brownie.reverts():
        swap.swap_from_synth(settler_sbtc.token_id(), WBTC, balance+1, 0, {'from': alice})
