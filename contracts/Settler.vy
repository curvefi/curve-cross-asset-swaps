# @version 0.3.0
"""
@title Synth Settler
@author Curve.fi
@license MIT
"""

from vyper.interfaces import ERC20


interface AddressProvider:
    def get_address(_id: uint256) -> address: view

interface CurvePool:
    def exchange(i: int128, j: int128, dx: uint256, min_dy: uint256): payable
    def exchange_underlying(i: int128, j: int128, dx: uint256, min_dy: uint256): payable

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

@external
def __init__():
    self.admin = msg.sender


@payable
@external
def __default__():
    # required to receive Ether
    pass


@external
def convert_synth(
    _amount: uint256,
    _source_key: bytes32,
    _dest_key: bytes32
) -> bool:
    """
    @notice Convert between two synths
    @dev Called via `SynthSwap.swap_into_synth`
    @param _amount Amount of the original synth to convert
    @param _source_key Currency key for the initial synth
    @param _dest_key Currency key for the target synth
    @return bool Success
    """
    assert msg.sender == self.admin

    Synthetix(SNX).exchangeWithTracking(_source_key, _amount, _dest_key, msg.sender, TRACKING_CODE)

    return True


@external
@payable
def exchange(
    _pool: address,
    _initial: address,
    _target: address,
    _receiver: address,
    _amount: uint256,
    i: uint256,
    j: uint256,
    _is_underlying: uint256
) -> bool:
    """
    @notice Exchange the synth deposited in this contract for another asset
    @dev Called via `SynthSwap.swap_from_synth`
    @return uint256 Amount of the deposited synth remaining in the contract
    """
    assert msg.sender == self.admin

    if not self.is_approved[_initial][_pool]:
        ERC20(_initial).approve(_pool, MAX_UINT256)
        self.is_approved[_initial][_pool] = True

    if _is_underlying == 0:
        CurvePool(_pool).exchange(convert(i, int128), convert(j, int128), _amount, 0, value=msg.value)
    else:
        CurvePool(_pool).exchange_underlying(convert(i, int128), convert(j, int128), _amount, 0, value=msg.value)

    if _receiver != ZERO_ADDRESS:
        if _target == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE:
            raw_call(_receiver, b"", value=self.balance)
        else:
            amount: uint256 = ERC20(_target).balanceOf(self)  # dev: bad response
            ERC20(_target).transfer(_receiver, amount)

    return True


@external
def withdraw(_token: address, _receiver: address, _amount: uint256) -> bool:
    """
    @notice Withdraw the synth deposited in this contract
    @dev Called via `SynthSwap.withdraw`
    @param _receiver Receiver address for the deposited synth
    @param _amount Amount of the deposited synth to withdraw
    @return uint256 Amount of the deposited synth remaining in the contract
    """
    assert msg.sender == self.admin

    ERC20(_token).transfer(_receiver, _amount)

    return True


@external
def settle(_synth: address) -> bool:
    """
    @notice Settle the synth deposited in this contract
    @dev Settlement is performed when swapping or withdrawing, there
         is no requirement to call this function separately
    @return bool Success
    """
    currency_key: bytes32 = Synth(_synth).currencyKey()
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
