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

interface Exchanger:
    def maxSecsLeftInWaitingPeriod(account: address, currencyKey: bytes32) -> uint256: view

interface Synth:
    def currencyKey() -> bytes32: nonpayable


ADDRESS_PROVIDER: constant(address) = 0x0000000022D53366457F9d5E68Ec105046FC4383
EXCHANGER: constant(address) = 0x0bfDc04B38251394542586969E2356d0D731f7DE
SNX: constant(address) = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F

is_approved: HashMap[address, HashMap[address, bool]]
currency_keys: HashMap[address, bytes32]

admin: public(address)
synth: public(address)
is_settled: public(bool)


@external
def __init__():
    self.admin = msg.sender


@external
def initialize():
    assert self.admin == ZERO_ADDRESS

    self.admin = msg.sender


@external
def exchange_synth(_initial: address, _target: address, _amount: uint256) -> bool:
    assert msg.sender == self.admin

    source_key: bytes32 = self.currency_keys[_initial]
    if source_key == EMPTY_BYTES32:
        source_key = Synth(_initial).currencyKey()
        self.currency_keys[_initial] = source_key

    dest_key: bytes32 = self.currency_keys[_target]
    if dest_key == EMPTY_BYTES32:
        dest_key = Synth(_target).currencyKey()
        self.currency_keys[_target] = dest_key

    self.synth = _target
    Synthetix(SNX).exchange(source_key, _amount, dest_key)
    self.is_settled = False

    return True


@external
def settle_and_swap(
    _target: address,
    _pool: address,
    _amount: uint256,
    _expected: uint256,
    _receiver: address,
) -> uint256:
    assert msg.sender == self.admin

    synth: address = self.synth
    if not self.is_settled:
        Synthetix(SNX).settle(self.currency_keys[synth])
        self.is_settled = True

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
    if not self.is_settled:
        Synthetix(SNX).settle(self.currency_keys[synth])
        self.is_settled = True

    ERC20(synth).transfer(_receiver, _amount)

    return ERC20(synth).balanceOf(self)


@external
def settle() -> bool:
    Synthetix(SNX).settle(self.currency_keys[self.synth])
    self.is_settled = True

    return True


@view
@external
def time_to_settle() -> uint256:
    return Exchanger(EXCHANGER).maxSecsLeftInWaitingPeriod(self, self.currency_keys[self.synth])
