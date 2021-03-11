import brownie
import pytest


@pytest.fixture(scope="module")
def token_id(settler_sbtc):
    return int(settler_sbtc.address, 16)


def test_is_settled_initial_value(alice, swap, token_id):
    assert not swap.is_settled(token_id)


def test_cannot_settle_immediately(alice, swap, token_id):
    with brownie.reverts("dev: settlement failed"):
        swap.settle(token_id, {"from": alice})


def test_unknown_id(alice, swap):
    with brownie.reverts("Unknown Token ID"):
        swap.settle(31337, {"from": alice})


def test_settle(chain, alice, swap, token_id):
    chain.sleep(600)
    swap.settle(token_id, {"from": alice})

    assert swap.is_settled(token_id)


def test_settle_twice(chain, alice, swap, token_id):
    chain.sleep(600)
    swap.settle(token_id, {"from": alice})
    swap.settle(token_id, {"from": alice})

    assert swap.is_settled(token_id)


def test_can_settle_directly(chain, alice, swap, settler_sbtc, token_id):
    chain.sleep(600)
    settler_sbtc.settle({"from": alice})

    assert not swap.is_settled(token_id)


def test_settle_indirect_after_settle_direct(
    chain, alice, swap, settler_sbtc, token_id
):
    chain.sleep(600)
    settler_sbtc.settle({"from": alice})
    swap.settle(token_id, {"from": alice})

    assert swap.is_settled(token_id)
