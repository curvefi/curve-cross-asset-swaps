
import brownie
import pytest

from brownie import ZERO_ADDRESS


@pytest.fixture(scope="module")
def token_id(settler_sbtc, settler_susd, settler_seth):
    yield settler_sbtc.token_id()


def test_approve(swap, alice, bob, token_id):

    assert swap.getApproved(token_id) == ZERO_ADDRESS
    swap.approve(bob, token_id, {'from': alice})
    assert swap.getApproved(token_id) == bob


def test_change_approve(swap, alice, bob, charlie, token_id):

    swap.approve(bob, token_id, {'from': alice})
    swap.approve(charlie, token_id, {'from': alice})
    assert swap.getApproved(token_id) == charlie


def test_revoke_approve(swap, alice, bob, token_id):
    swap.approve(alice, token_id, {'from': alice})
    swap.approve(ZERO_ADDRESS, token_id, {'from': alice})
    assert swap.getApproved(token_id) == ZERO_ADDRESS


def test_no_return_value(swap, alice, bob, token_id):

    tx = swap.approve(bob, token_id, {'from': alice})
    assert tx.return_value is None


def test_approval_event_fire(swap, alice, bob, token_id):
    tx = swap.approve(bob, token_id, {'from': alice})
    assert len(tx.events) == 1
    assert tx.events["Approval"].values() == [alice, bob, token_id]


def test_illegal_approval(swap, alice, bob, token_id):
    with brownie.reverts("Caller is not owner or operator"):
        swap.approve(bob, token_id, {'from': bob})


def test_get_approved_nonexistent(swap):
    with brownie.reverts():
        swap.getApproved(1337)
