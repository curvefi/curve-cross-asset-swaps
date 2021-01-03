import brownie
from brownie import ZERO_ADDRESS


def test_balanceOf(swap):
    with brownie.reverts():
        swap.balanceOf(ZERO_ADDRESS)


def test_ownerOf(swap):
    with brownie.reverts():
        swap.ownerOf(0)
