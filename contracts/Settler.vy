# @version 0.2.8
"""
@title Synth Settler
@author Curve.fi
@license MIT
"""

from vyper.interfaces import ERC20


interface AddressProvider:
    def get_address(_id: uint256) -> address: view

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
    def exchangeWithTracking(
        sourceCurrencyKey: bytes32,
        sourceAmount: uint256,
        destinationCurrencyKey: bytes32,
        originator: address,
        trackingCode: bytes32,
    ): nonpayable
    def settle(currencyKey: bytes32) -> uint256[3]: nonpayable

interface Synth:
    def currencyKey() -> bytes32: nonpayable


ADDRESS_PROVIDER: constant(address) = 0x0000000022D53366457F9d5E68Ec105046FC4383
SNX: constant(address) = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F

# "CURVE" as a bytes32
TRACKING_CODE: constant(bytes32) = 0x4355525645000000000000000000000000000000000000000000000000000000

# synth -> spender -> is approved?
is_approved: HashMap[address, HashMap[address, bool]]

admin: public(address)
synth: public(address)

@external
def __init__():
    self.admin = msg.sender


@external
def convert_synth(
    _target: address,
    _amount: uint256,
    _source_key: bytes32,
    _dest_key: bytes32
) -> bool:
    """
    @notice Convert between two synths
    @dev Called via `SynthSwap.swap_into_synth`
    @param _target Address of the synth being converted into
    @param _amount Amount of the original synth to convert
    @param _source_key Currency key for the initial synth
    @param _dest_key Currency key for the target synth
    @return bool Success
    """
    assert msg.sender == self.admin

    self.synth = _target
    Synthetix(SNX).exchangeWithTracking(_source_key, _amount, _dest_key, msg.sender, TRACKING_CODE)

    return True


@external
def exchange(
    _target: address,
    _pool: address,
    _amount: uint256,
    _expected: uint256,
    _receiver: address,
) -> uint256:
    """
    @notice Exchange the synth deposited in this contract for another asset
    @dev Called via `SynthSwap.swap_from_synth`
    @param _target Address of the asset being swapped into
    @param _pool Address of the Curve pool used in the exchange
    @param _amount Amount of the deposited synth to exchange
    @param _expected Minimum amount of `_target` to receive in the exchange
    @param _receiver Receiver address for `_target`
    @return uint256 Amount of the deposited synth remaining in the contract
    """
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
    """
    @notice Withdraw the synth deposited in this contract
    @dev Called via `SynthSwap.withdraw`
    @param _receiver Receiver address for the deposited synth
    @param _amount Amount of the deposited synth to withdraw
    @return uint256 Amount of the deposited synth remaining in the contract
    """
    assert msg.sender == self.admin

    synth: address = self.synth
    ERC20(synth).transfer(_receiver, _amount)

    return ERC20(synth).balanceOf(self)


@external
def settle() -> bool:
    """
    @notice Settle the synth deposited in this contract
    @dev Settlement is performed when swapping or withdrawing, there
         is no requirement to call this function separately
    @return bool Success
    """
    currency_key: bytes32 = Synth(self.synth).currencyKey()
    Synthetix(SNX).settle(currency_key)

    return True


@external
def initialize():
    """
    @notice Initialize the contract
    @dev This function is seperate from `__init__` because of the factory
         pattern used in `SynthSwap`. It may be called once per deployment.
    """
    assert self.admin == ZERO_ADDRESS

    self.admin = msg.sender
