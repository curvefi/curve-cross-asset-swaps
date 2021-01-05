import brownie


def test_is_settled_initial_value(alice, swap, settler_sbtc):
    assert not swap.is_settled(settler_sbtc.token_id())


def test_cannot_settle_immediately(alice, swap, settler_sbtc):
    with brownie.reverts("dev: settlement failed"):
        swap.settle(settler_sbtc.token_id(), {'from': alice})


def test_unknown_id(alice, swap):
    with brownie.reverts("Unknown Token ID"):
        swap.settle(31337, {'from': alice})


def test_settle(chain, alice, swap, settler_sbtc):
    chain.sleep(600)
    swap.settle(settler_sbtc.token_id(), {'from': alice})

    assert swap.is_settled(settler_sbtc.token_id())


def test_settle_twice(chain, alice, swap, settler_sbtc):
    chain.sleep(600)
    swap.settle(settler_sbtc.token_id(), {'from': alice})
    swap.settle(settler_sbtc.token_id(), {'from': alice})

    assert swap.is_settled(settler_sbtc.token_id())


def test_can_settle_directly(chain, alice, swap, settler_sbtc):
    chain.sleep(600)
    settler_sbtc.settle({'from': alice})

    assert not swap.is_settled(settler_sbtc.token_id())



def test_settle_indirect_after_settle_direct(chain, alice, swap, settler_sbtc):
    chain.sleep(600)
    settler_sbtc.settle({'from': alice})
    swap.settle(settler_sbtc.token_id(), {'from': alice})

    assert swap.is_settled(settler_sbtc.token_id())
