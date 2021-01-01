# @version 0.2.8
"""
@title Synth Settler
@author Curve.fi
@license MIT
"""

from vyper.interfaces import ERC20


interface AddressProvider:
    def get_address(_id: uint256) -> address: view

interface Registry:
    def find_pool_for_coins(_from: address, _to: address) -> address: view

interface RegistrySwap:
    def exchange(
        _pool: address,
        _from: address,
        _to: address,
        _amount: uint256,
        _expected: uint256,
        _receiver: address,
    ) -> uint256: payable

interface Synthetix:
    def exchange(
        sourceCurrencyKey: bytes32,
        sourceAmount: uint256,
        destinationCurrencyKey: bytes32,
    ): nonpayable
    def settle(currencyKey: bytes32) -> uint256[3]: nonpayable

interface Synth:
    def currencyKey() -> bytes32: nonpayable


ADDRESS_PROVIDER: constant(address) = 0x0000000022D53366457F9d5E68Ec105046FC4383
SNX: constant(address) = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F

is_approved: HashMap[address, HashMap[address, bool]]

admin: public(address)
synth: public(address)


@external
def __init__():
    self.admin = msg.sender


@external
def initialize():
    assert self.admin == ZERO_ADDRESS

    self.admin = msg.sender


@external
def exchange_via_snx(_target: address, _amount: uint256, _source_key: bytes32, _dest_key: bytes32) -> bool:
    assert msg.sender == self.admin

    self.synth = _target
    Synthetix(SNX).exchange(_source_key, _amount, _dest_key)

    return True


@external
def exchange_via_curve(
    _target: address,
    _pool: address,
    _amount: uint256,
    _expected: uint256,
    _receiver: address,
) -> uint256:
    assert msg.sender == self.admin

    synth: address = self.synth
    registry_swap: address = AddressProvider(ADDRESS_PROVIDER).get_address(2)

    if not self.is_approved[synth][registry_swap]:
        ERC20(synth).approve(registry_swap, MAX_UINT256)
        self.is_approved[synth][registry_swap] = True

    RegistrySwap(registry_swap).exchange(_pool, synth, _target, _amount, _expected, _receiver)

    return ERC20(synth).balanceOf(self)


@external
def withdraw(_receiver: address, _amount: uint256) -> uint256:
    assert msg.sender == self.admin

    synth: address = self.synth
    ERC20(synth).transfer(_receiver, _amount)

    return ERC20(synth).balanceOf(self)


@external
def settle() -> bool:
    currency_key: bytes32 = Synth(self.synth).currencyKey()
    Synthetix(SNX).settle(currency_key)

    return True


@view
@external
def token_id() -> uint256:
    return convert(self, uint256)
