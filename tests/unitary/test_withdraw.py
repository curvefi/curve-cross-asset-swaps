import brownie
from brownie import ZERO_ADDRESS


def test_cannot_withdraw_immediately(alice, swap, settler_sbtc):
    with brownie.reverts():
        swap.withdraw(settler_sbtc.token_id(), 1, {'from': alice})


def test_only_owner(chain, bob, swap, settler_sbtc):
    chain.sleep(300)
    with brownie.reverts():
        swap.withdraw(settler_sbtc.token_id(), 1, {'from': bob})


def test_only_owner_direct(chain, alice, swap, settler_sbtc):
    chain.sleep(300)
    with brownie.reverts():
        # alice owns the token ID, but only `swap`
        # can call to the NFT contract
        settler_sbtc.withdraw(alice, 1, {'from': alice})


def test_withdraw_all(chain, alice, swap, settler_sbtc, sBTC):
    chain.mine(timedelta=300)
    token_id = settler_sbtc.token_id()
    balance = swap.token_info(token_id)['underlying_balance']

    swap.withdraw(token_id, balance, {'from': alice})

    assert sBTC.balanceOf(alice) == balance
    assert sBTC.balanceOf(settler_sbtc) == 0
    assert sBTC.balanceOf(swap) == 0


def test_withdraw_all_burns(chain, alice, swap, settler_sbtc, sBTC):
    chain.mine(timedelta=300)
    token_id = settler_sbtc.token_id()
    balance = swap.token_info(token_id)['underlying_balance']

    tx = swap.withdraw(token_id, balance, {'from': alice})

    # withdrawing the entire balance should burn the related NFT
    assert swap.balanceOf(alice) == 0
    assert tx.events['Transfer'][-1].values() == [alice, ZERO_ADDRESS, token_id]
    with brownie.reverts():
        swap.ownerOf(token_id)


def test_withdraw_partial(chain, alice, swap, settler_sbtc, sBTC):
    chain.mine(timedelta=300)
    token_id = settler_sbtc.token_id()
    initial = swap.token_info(token_id)['underlying_balance']
    amount = initial // 4

    swap.withdraw(token_id, amount, {'from': alice})

    assert sBTC.balanceOf(alice) == amount
    assert sBTC.balanceOf(settler_sbtc) == initial - amount
    assert sBTC.balanceOf(swap) == 0


def test_withdraw_partial_does_not_burn(chain, alice, swap, settler_sbtc, sBTC):
    chain.mine(timedelta=300)
    token_id = settler_sbtc.token_id()
    initial = swap.token_info(token_id)['underlying_balance']
    amount = initial // 4

    swap.withdraw(token_id, amount, {'from': alice})

    assert swap.balanceOf(alice) == 1
    assert swap.ownerOf(token_id) == alice


def test_withdraw_multiple(chain, alice, swap, settler_sbtc, sBTC):
    chain.mine(timedelta=300)
    token_id = settler_sbtc.token_id()
    initial = swap.token_info(token_id)['underlying_balance']
    amount = initial // 4

    swap.withdraw(token_id, amount, {'from': alice})
    swap.withdraw(token_id, amount * 2, {'from': alice})

    assert sBTC.balanceOf(alice) == amount * 3
    assert sBTC.balanceOf(settler_sbtc) == initial - amount * 3
    assert sBTC.balanceOf(swap) == 0


def test_withdraw_zero(chain, alice, swap, settler_sbtc, sBTC):
    chain.mine(timedelta=300)
    token_id = settler_sbtc.token_id()
    initial = swap.token_info(token_id)['underlying_balance']

    swap.withdraw(token_id, 0, {'from': alice})

    assert sBTC.balanceOf(alice) == 0
    assert sBTC.balanceOf(settler_sbtc) == initial
    assert sBTC.balanceOf(swap) == 0


def test_withdraw_different_receiver(chain, alice, bob, swap, settler_sbtc, sBTC):
    chain.mine(timedelta=300)
    token_id = settler_sbtc.token_id()
    balance = swap.token_info(token_id)['underlying_balance']

    swap.withdraw(token_id, balance, bob, {'from': alice})

    assert sBTC.balanceOf(alice) == 0
    assert sBTC.balanceOf(bob) == balance
    assert sBTC.balanceOf(settler_sbtc) == 0
    assert sBTC.balanceOf(swap) == 0


def test_withdraw_exceeds_balance(chain, alice, swap, settler_sbtc, sBTC):
    chain.mine(timedelta=300)
    token_id = settler_sbtc.token_id()
    balance = swap.token_info(token_id)['underlying_balance']

    with brownie.reverts():
        swap.withdraw(token_id, balance+1, {'from': alice})
