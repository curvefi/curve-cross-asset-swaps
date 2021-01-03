
def test_approve_all(swap, alice, bob):
    assert swap.isApprovedForAll(alice, bob) is False
    swap.setApprovalForAll(bob, True, {'from': alice})
    assert swap.isApprovedForAll(alice, bob) is True


def test_approve_all_multiple(swap, alice, accounts):
    operators = accounts[4:8]
    for acct in operators:
        assert swap.isApprovedForAll(alice, acct) is False

    for acct in operators:
        swap.setApprovalForAll(acct, True, {'from': alice})

    for acct in operators:
        assert swap.isApprovedForAll(alice, acct) is True


def test_revoke_operator(swap, alice, bob):
    swap.setApprovalForAll(bob, True, {'from': alice})
    assert swap.isApprovedForAll(alice, bob) is True

    swap.setApprovalForAll(bob, False, {'from': alice})
    assert swap.isApprovedForAll(alice, bob) is False


def test_approval_all_event_fire(swap, alice, bob):
    tx = swap.setApprovalForAll(bob, True, {'from': alice})
    assert len(tx.events) == 1
    assert tx.events["ApprovalForAll"].values() == [alice, bob, True]


def test_operator_approval(swap, alice, bob, charlie, settler_sbtc):
    swap.setApprovalForAll(bob, True, {'from': alice})
    swap.approve(charlie, settler_sbtc.token_id(), {'from': bob})
