import brownie
import pytest

from brownie import ZERO_ADDRESS


@pytest.fixture(scope="module")
def token_id(settler_sbtc, settler_susd, settler_seth):
    yield int(settler_sbtc.address, 16)


def test_assumptions(swap, alice, bob, token_id):
    assert swap.balanceOf(alice) == 3
    assert swap.balanceOf(bob) == 0
    assert swap.ownerOf(token_id) == alice


def test_transfer_adjusts_ownership(alice, bob, swap, token_id):
    swap.transferFrom(alice, bob, token_id, {'from': alice})

    assert swap.ownerOf(token_id) == bob


def test_transfer_adjusts_balance(alice, bob, swap, token_id):
    swap.transferFrom(alice, bob, token_id, {'from': alice})
    assert swap.balanceOf(alice) == 2
    assert swap.balanceOf(bob) == 1


def test_transfer_clears_operator(alice, bob, swap, token_id):
    swap.approve(bob, token_id, {'from': alice})
    assert swap.getApproved(token_id) == bob

    swap.transferFrom(alice, bob, token_id, {'from': alice})

    assert swap.getApproved(token_id) == ZERO_ADDRESS


def test_transfer_event(alice, bob, swap, token_id):
    tx = swap.transferFrom(alice, bob, token_id, {'from': alice})

    assert tx.events['Transfer'][-1].values() == [alice, bob, token_id]


def test_transfer_via_operator(alice, bob, swap, token_id):
    swap.setApprovalForAll(bob, True, {'from': alice})
    swap.transferFrom(alice, bob, token_id, {'from': bob})

    assert swap.ownerOf(token_id) == bob


def test_transfer_via_one_token_operator(alice, bob, swap, token_id):
    swap.approve(bob, token_id, {'from': alice})
    swap.transferFrom(alice, bob, token_id, {'from': bob})

    assert swap.ownerOf(token_id) == bob


def test_from_zero_address(alice, bob, swap, token_id):
    with brownie.reverts("Cannot send from zero address"):
        swap.transferFrom(ZERO_ADDRESS, bob, token_id, {'from': alice})


def test_to_zero_address(alice, bob, swap, token_id):
    with brownie.reverts("Cannot send to zero address"):
        swap.transferFrom(alice, ZERO_ADDRESS, token_id, {'from': alice})


def test_incorrect_from(alice, bob, swap, token_id):
    with brownie.reverts("Incorrect owner for Token ID"):
        swap.transferFrom(bob, bob, token_id, {'from': alice})


def test_caller_not_owner(alice, bob, swap, token_id):
    with brownie.reverts("Caller is not owner or operator"):
        swap.transferFrom(alice, bob, token_id, {'from': bob})
